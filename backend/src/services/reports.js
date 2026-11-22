// Queries shared by the university's own pages AND the admin's view of a
// university, so both always show exactly the same numbers.
import { query, callProcedure } from '../config/db.js';
import { financialYearRange } from '../utils/dates.js';

// Every monthly GST bill of a university in a financial year, with its status:
//   NIL          nothing to pay
//   PAID         tax and interest fully paid
//   INTEREST_DUE tax paid late, interest still unpaid
//   OVERDUE      past the due date, tax unpaid
//   PARTIAL      not yet due, part paid
//   DUE          not yet due, nothing paid
export function getBills(univId, fy, today) {
  return query(
    `SELECT b.*,
            CASE
              WHEN b.Tax_Due = 0 AND b.Interest_Outstanding = 0           THEN 'NIL'
              WHEN b.Tax_Outstanding = 0 AND b.Interest_Outstanding > 0   THEN 'INTEREST_DUE'
              WHEN b.Tax_Outstanding = 0                                  THEN 'PAID'
              WHEN b.Due_Date < ?                                         THEN 'OVERDUE'
              WHEN b.Tax_Paid > 0                                         THEN 'PARTIAL'
              ELSE 'DUE'
            END AS Status
     FROM (
       SELECT tr.Tax_ID, tr.Univ_ID, tr.Period_Start,
              DATE_FORMAT(tr.Period_Start, '%b %Y')        AS Period,
              tr.Financial_Year, tr.Total_Income, tr.Taxable_Income,
              tr.CGST, tr.SGST, tr.IGST, tr.Tax_Due, tr.Tax_Paid,
              GREATEST(tr.Tax_Due - tr.Tax_Paid, 0)        AS Tax_Outstanding,
              tr.Due_Date,
              Calculate_Bill_Interest(tr.Tax_ID, ?)        AS Interest_Accrued,
              tr.Interest_Paid,
              Get_Interest_Outstanding(tr.Tax_ID, ?)       AS Interest_Outstanding,
              (SELECT IFNULL(SUM(p.Amount), 0) FROM payment p
                WHERE p.Tax_ID = tr.Tax_ID AND p.Status = 'Pending') AS Pending_Verification
       FROM tax_record tr
       WHERE tr.Univ_ID = ? AND tr.Financial_Year = ?
     ) AS b
     ORDER BY b.Period_Start DESC`,
    [today, today, today, univId, fy]
  );
}

// One bill with the income entries and payments behind it
export async function getBillDetail(univId, taxId, today) {
  const [bill] = await query(
    `SELECT tr.*, DATE_FORMAT(tr.Period_Start, '%b %Y') AS Period,
            GREATEST(tr.Tax_Due - tr.Tax_Paid, 0)    AS Tax_Outstanding,
            Calculate_Bill_Interest(tr.Tax_ID, ?)    AS Interest_Accrued,
            Get_Interest_Outstanding(tr.Tax_ID, ?)   AS Interest_Outstanding
     FROM tax_record tr WHERE tr.Tax_ID = ? AND tr.Univ_ID = ?`,
    [today, today, taxId, univId]
  );
  if (!bill) return null;

  // invoices of that month + credit notes that correct an invoice of that month
  const entries = await query(
    `SELECT t.Trans_ID, t.Entry_Type, t.Original_Trans_ID, t.Trans_Date, d.Name AS Department,
            s.Source_Name, IF(t.Entry_Type = 'CREDIT_NOTE', -t.Amount, t.Amount) AS Amount,
            t.GST_Rate, IF(t.Entry_Type = 'CREDIT_NOTE', -t.GST_Amount, t.GST_Amount) AS GST_Amount,
            t.Payer_Name, t.Place_Of_Supply
     FROM revenue_transaction t
     JOIN department d ON d.Dept_ID = t.Dept_ID
     JOIN income_source s ON s.Source_ID = t.Source_ID
     LEFT JOIN revenue_transaction o ON o.Trans_ID = t.Original_Trans_ID
     WHERE d.Univ_ID = ?
       AND DATE_FORMAT(IF(t.Entry_Type = 'CREDIT_NOTE', o.Trans_Date, t.Trans_Date), '%Y-%m-01') = ?
     ORDER BY t.Trans_Date, t.Trans_ID`,
    [univId, bill.Period_Start]
  );

  const payments = await query(
    'SELECT * FROM payment WHERE Tax_ID = ? ORDER BY Payment_Date, Payment_ID',
    [taxId]
  );

  return { bill, entries, payments };
}

// ---------------- the dashboard numbers and charts ----------------

export async function getOverview(univId, fy, today) {
  const [summary] = await callProcedure('University_Tax_Summary', [univId, fy, today]);
  const [counts] = await query(
    `SELECT
       (SELECT COUNT(*) FROM alert   WHERE Univ_ID = ? AND Is_Read = FALSE)     AS Unread_Alerts,
       (SELECT COUNT(*) FROM notice  WHERE Univ_ID = ? AND Status = 'Open')     AS Open_Notices,
       (SELECT COUNT(*) FROM payment p JOIN tax_record tr ON tr.Tax_ID = p.Tax_ID
         WHERE tr.Univ_ID = ? AND p.Status = 'Pending')                         AS Pending_Payments,
       (SELECT COUNT(*) FROM anomaly WHERE Univ_ID = ? AND Status = 'Open')     AS Open_Anomalies`,
    [univId, univId, univId, univId]
  );
  return { ...summary, ...counts };
}

// income per month, split into taxable and exempt (line/area chart)
export function getMonthlyRevenue(univId, fy) {
  return query(
    `SELECT DATE_FORMAT(Period_Start, '%b %y') AS Month, Period_Start,
            Total_Income, Taxable_Income, Total_Income - Taxable_Income AS Exempt_Income
     FROM tax_record WHERE Univ_ID = ? AND Financial_Year = ?
     ORDER BY Period_Start`,
    [univId, fy]
  );
}

// GST per month: CGST / SGST / IGST and how much was paid (bar chart)
export function getMonthlyTax(univId, fy) {
  return query(
    `SELECT DATE_FORMAT(Period_Start, '%b %y') AS Month, Period_Start,
            CGST, SGST, IGST, Tax_Due, Tax_Paid
     FROM tax_record WHERE Univ_ID = ? AND Financial_Year = ?
     ORDER BY Period_Start`,
    [univId, fy]
  );
}

// how many bills are in each status (pie chart)
export async function getTaxStatus(univId, fy, today) {
  const bills = await getBills(univId, fy, today);
  const groups = {};
  for (const b of bills) {
    groups[b.Status] ??= { Status: b.Status, Bills: 0, Amount: 0 };
    groups[b.Status].Bills += 1;
    groups[b.Status].Amount += b.Tax_Outstanding + b.Interest_Outstanding;
  }
  return Object.values(groups).map((g) => ({ ...g, Amount: Math.round(g.Amount * 100) / 100 }));
}

// payments made in the year (table)
export function getPaymentHistory(univId, fy) {
  return query(
    `SELECT p.Payment_ID, p.Payment_Date, p.Payment_For, p.Amount, p.Mode, p.Reference_No,
            p.Status, p.Remarks, DATE_FORMAT(tr.Period_Start, '%b %Y') AS Period
     FROM payment p JOIN tax_record tr ON tr.Tax_ID = p.Tax_ID
     WHERE tr.Univ_ID = ? AND tr.Financial_Year = ?
     ORDER BY p.Payment_Date DESC, p.Payment_ID DESC`,
    [univId, fy]
  );
}

// income by type, with GST category (donut chart)
export function getIncomeByType(univId, fy) {
  const { from, to } = financialYearRange(fy);
  return query(
    `SELECT r.Income_Type, r.GST_Category,
            SUM(IF(t.Entry_Type = 'CREDIT_NOTE', -t.Amount, t.Amount))         AS Amount,
            SUM(IF(t.Entry_Type = 'CREDIT_NOTE', -t.GST_Amount, t.GST_Amount)) AS GST
     FROM revenue_transaction t
     JOIN department d    ON d.Dept_ID    = t.Dept_ID
     JOIN income_source s ON s.Source_ID  = t.Source_ID
     JOIN tax_rule r      ON r.TaxRule_ID = s.TaxRule_ID
     WHERE d.Univ_ID = ? AND t.Trans_Date BETWEEN ? AND ?
     GROUP BY r.TaxRule_ID, r.Income_Type, r.GST_Category
     ORDER BY Amount DESC`,
    [univId, from, to]
  );
}
