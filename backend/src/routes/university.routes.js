// /api/university : everything a logged-in UNIVERSITY user can do.
// Every query is limited to req.user.univId, which comes from the verified
// login token - never from the request - so one university can never read
// or change another university's data, even by guessing IDs.
import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { z } from 'zod';
import { query, callProcedure } from '../config/db.js';
import { requireAuth, requireRole } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { HttpError } from '../utils/httpError.js';
import { todayIST } from '../utils/dates.js';
import { dateString, money, gstin, idParam, fyQuery, password } from '../utils/schemas.js';
import * as reports from '../services/reports.js';

const router = Router();
router.use(requireAuth, requireRole('UNIVERSITY'));

// ---------------- profile, departments, staff logins ----------------

router.get('/profile', async (req, res) => {
  const [uni] = await query(
    `SELECT Univ_ID, Name, GSTIN, PAN, Institution_Type, IT_Exemption, Address, City, State,
            Contact_Person, Phone, Email, Status, Registered_At, Reviewed_At
     FROM university WHERE Univ_ID = ?`,
    [req.user.univId]
  );
  res.json(uni);
});

const profileSchema = z.object({
  address: z.string().trim().max(255).optional(),
  city: z.string().trim().max(80).optional(),
  contactPerson: z.string().trim().min(2).max(100).optional(),
  phone: z.string().regex(/^[6-9]\d{9}$/, 'Enter a 10-digit Indian mobile number').optional(),
});

// GSTIN, state and name are locked after approval; only contact details can change
router.patch('/profile', validate(profileSchema), async (req, res) => {
  const d = req.valid.body;
  await query(
    `UPDATE university SET Address = COALESCE(?, Address), City = COALESCE(?, City),
            Contact_Person = COALESCE(?, Contact_Person), Phone = COALESCE(?, Phone)
     WHERE Univ_ID = ?`,
    [d.address ?? null, d.city ?? null, d.contactPerson ?? null, d.phone ?? null, req.user.univId]
  );
  res.json({ message: 'Profile updated' });
});

router.get('/departments', async (req, res) => {
  res.json(await query(
    `SELECT d.Dept_ID, d.Name,
            (SELECT COUNT(*) FROM revenue_transaction t WHERE t.Dept_ID = d.Dept_ID) AS Entries
     FROM department d WHERE d.Univ_ID = ? ORDER BY d.Name`,
    [req.user.univId]
  ));
});

router.post('/departments', validate(z.object({ name: z.string().trim().min(2).max(100) })),
  async (req, res) => {
    const result = await query('INSERT INTO department (Name, Univ_ID) VALUES (?, ?)',
      [req.valid.body.name, req.user.univId]);
    res.status(201).json({ Dept_ID: result.insertId, Name: req.valid.body.name });
  });

router.get('/users', async (req, res) => {
  res.json(await query(
    'SELECT User_ID, Name, Email, Last_Login, Created_At FROM users WHERE Univ_ID = ? ORDER BY User_ID',
    [req.user.univId]
  ));
});

// a university can add more staff logins for its own finance team
router.post('/users',
  validate(z.object({ name: z.string().trim().min(2).max(100), email: z.email().toLowerCase(), password })),
  async (req, res) => {
    const d = req.valid.body;
    const hash = await bcrypt.hash(d.password, 10);
    const result = await query(
      `INSERT INTO users (Name, Email, Password_Hash, Role, Univ_ID) VALUES (?, ?, ?, 'UNIVERSITY', ?)`,
      [d.name, d.email, hash, req.user.univId]
    );
    res.status(201).json({ User_ID: result.insertId, Name: d.name, Email: d.email });
  });

// ---------------- income entries ----------------

const listSchema = z.object({
  from: dateString.optional(),
  to: dateString.optional(),
  deptId: z.coerce.number().int().positive().optional(),
  sourceId: z.coerce.number().int().positive().optional(),
  search: z.string().trim().max(100).optional(),
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(20),
});

router.get('/transactions', validate(listSchema, 'query'), async (req, res) => {
  const q = req.valid.query;

  // build the WHERE clause from whichever filters were given (values stay in params)
  const where = ['d.Univ_ID = ?'];
  const params = [req.user.univId];
  if (q.from)     { where.push('t.Trans_Date >= ?'); params.push(q.from); }
  if (q.to)       { where.push('t.Trans_Date <= ?'); params.push(q.to); }
  if (q.deptId)   { where.push('t.Dept_ID = ?');     params.push(q.deptId); }
  if (q.sourceId) { where.push('t.Source_ID = ?');   params.push(q.sourceId); }
  if (q.search) {
    where.push('(t.Payer_Name LIKE ? OR t.Reference_No LIKE ? OR t.Description LIKE ?)');
    params.push(`%${q.search}%`, `%${q.search}%`, `%${q.search}%`);
  }
  const whereSql = where.join(' AND ');

  const [{ total }] = await query(
    `SELECT COUNT(*) AS total FROM revenue_transaction t
     JOIN department d ON d.Dept_ID = t.Dept_ID WHERE ${whereSql}`,
    params
  );

  const rows = await query(
    `SELECT t.Trans_ID, t.Entry_Type, t.Original_Trans_ID, t.Trans_Date, t.Amount, t.Mode,
            d.Name AS Department, s.Source_Name, r.Income_Type, r.GST_Category,
            t.GST_Rate, t.GST_Amount, t.TDS_Deducted, t.TDS_Source, t.Payer_Name,
            t.Payer_GSTIN, t.Place_Of_Supply, t.Reference_No, t.Beneficiaries, t.Stay_Days,
            t.Description, t.Created_At,
            (SELECT IFNULL(SUM(c.Amount), 0) FROM revenue_transaction c
              WHERE c.Original_Trans_ID = t.Trans_ID) AS Credited,
            (SELECT COUNT(*) FROM anomaly a WHERE a.Trans_ID = t.Trans_ID) AS Anomalies
     FROM revenue_transaction t
     JOIN department d    ON d.Dept_ID    = t.Dept_ID
     JOIN income_source s ON s.Source_ID  = t.Source_ID
     JOIN tax_rule r      ON r.TaxRule_ID = s.TaxRule_ID
     WHERE ${whereSql}
     ORDER BY t.Trans_Date DESC, t.Trans_ID DESC
     LIMIT ? OFFSET ?`,
    [...params, q.pageSize, (q.page - 1) * q.pageSize]
  );

  res.json({ rows, total, page: q.page, pageSize: q.pageSize });
});

const transactionSchema = z.object({
  transDate: dateString,
  amount: money,
  mode: z.enum(['Cash', 'Bank Transfer', 'Cheque', 'UPI']),
  deptId: z.coerce.number().int().positive(),
  sourceId: z.coerce.number().int().positive(),
  payerName: z.string().trim().max(150).optional(),
  payerGstin: gstin.optional(),
  placeOfSupply: z.string().trim().max(60).optional(),
  referenceNo: z.string().trim().max(50).optional(),
  beneficiaries: z.coerce.number().int().positive().optional(),
  stayDays: z.coerce.number().int().positive().optional(),
  tdsDeducted: z.coerce.number().min(0).optional(),
  description: z.string().trim().max(255).optional(),
});

// the triggers do the rest: GST, TDS, monthly bill, anomaly checks
router.post('/transactions', validate(transactionSchema), async (req, res) => {
  const d = req.valid.body;

  const [dept] = await query('SELECT Dept_ID FROM department WHERE Dept_ID = ? AND Univ_ID = ?',
    [d.deptId, req.user.univId]);
  if (!dept) throw new HttpError(400, 'Choose one of your own departments');

  const result = await query(
    `INSERT INTO revenue_transaction
       (Trans_Date, Amount, Mode, Dept_ID, Source_ID, Payer_Name, Payer_GSTIN, Place_Of_Supply,
        Reference_No, Beneficiaries, Stay_Days, TDS_Deducted, Description, Created_By)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [d.transDate, d.amount, d.mode, d.deptId, d.sourceId, d.payerName ?? null,
     d.payerGstin ?? null, d.placeOfSupply ?? null, d.referenceNo ?? null,
     d.beneficiaries ?? null, d.stayDays ?? null, d.tdsDeducted ?? null,
     d.description ?? null, req.user.id]
  );

  res.status(201).json(await entryWithAnomalies(result.insertId));
});

// correct a mistake: a credit note against one of your invoices
const creditSchema = z.object({
  amount: money,
  transDate: dateString,
  reason: z.string().trim().min(3).max(255),
});

router.post('/transactions/:id/credit-note', validate(idParam, 'params'), validate(creditSchema),
  async (req, res) => {
    const [orig] = await query(
      `SELECT t.* FROM revenue_transaction t JOIN department d ON d.Dept_ID = t.Dept_ID
       WHERE t.Trans_ID = ? AND d.Univ_ID = ?`,
      [req.valid.params.id, req.user.univId]
    );
    if (!orig) throw new HttpError(404, 'Entry not found');

    const d = req.valid.body;
    const result = await query(
      `INSERT INTO revenue_transaction
         (Entry_Type, Original_Trans_ID, Trans_Date, Amount, Mode, Dept_ID, Source_ID,
          Payer_Name, Description, Created_By)
       VALUES ('CREDIT_NOTE', ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [orig.Trans_ID, d.transDate, d.amount, orig.Mode, orig.Dept_ID, orig.Source_ID,
       orig.Payer_Name, d.reason, req.user.id]
    );
    res.status(201).json(await entryWithAnomalies(result.insertId));
  });

async function entryWithAnomalies(transId) {
  const [entry] = await query('SELECT * FROM revenue_transaction WHERE Trans_ID = ?', [transId]);
  const anomalies = await query(
    'SELECT Rule_Code, Severity, Details FROM anomaly WHERE Trans_ID = ?', [transId]);
  return { entry, anomalies };
}

router.get('/breakdown', validate(z.object({ from: dateString, to: dateString }), 'query'),
  async (req, res) => {
    res.json(await callProcedure('University_Income_Breakdown',
      [req.user.univId, req.valid.query.from, req.valid.query.to]));
  });

// ---------------- monthly GST bills ----------------

router.get('/tax-records', validate(fyQuery, 'query'), async (req, res) => {
  res.json(await reports.getBills(req.user.univId, req.valid.query.fy, todayIST()));
});

router.get('/tax-records/:id', validate(idParam, 'params'), async (req, res) => {
  const detail = await reports.getBillDetail(req.user.univId, req.valid.params.id, todayIST());
  if (!detail) throw new HttpError(404, 'Bill not found');
  res.json(detail);
});

// ---------------- payments ----------------

router.get('/payments', validate(fyQuery, 'query'), async (req, res) => {
  res.json(await reports.getPaymentHistory(req.user.univId, req.valid.query.fy));
});

const paymentSchema = z.object({
  taxId: z.coerce.number().int().positive(),
  paymentFor: z.enum(['Tax', 'Interest']).default('Tax'),
  amount: money,
  paymentDate: dateString,
  mode: z.enum(['Net Banking', 'NEFT/RTGS', 'UPI', 'Card', 'Over the Counter']),
  referenceNo: z.string().trim().min(5).max(50),   // CIN of the challan
});

router.post('/payments', validate(paymentSchema), async (req, res) => {
  const d = req.valid.body;
  const [bill] = await query('SELECT Tax_ID FROM tax_record WHERE Tax_ID = ? AND Univ_ID = ?',
    [d.taxId, req.user.univId]);
  if (!bill) throw new HttpError(404, 'Bill not found');

  const result = await query(
    `INSERT INTO payment (Tax_ID, Payment_For, Amount, Payment_Date, Mode, Reference_No)
     VALUES (?, ?, ?, ?, ?, ?)`,
    [d.taxId, d.paymentFor, d.amount, d.paymentDate, d.mode, d.referenceNo]
  );
  res.status(201).json({
    Payment_ID: result.insertId,
    message: 'Payment recorded. It will count once the tax office verifies it.',
  });
});

// ---------------- alerts ----------------

router.get('/alerts', validate(z.object({ unread: z.enum(['true', 'false']).optional() }), 'query'),
  async (req, res) => {
    const onlyUnread = req.valid.query.unread === 'true';
    res.json(await query(
      `SELECT a.*, DATE_FORMAT(tr.Period_Start, '%b %Y') AS Period
       FROM alert a JOIN tax_record tr ON tr.Tax_ID = a.Tax_ID
       WHERE a.Univ_ID = ? ${onlyUnread ? 'AND a.Is_Read = FALSE' : ''}
       ORDER BY a.Alert_Date DESC, a.Alert_ID DESC
       LIMIT 200`,
      [req.user.univId]
    ));
  });

router.get('/alerts/unread-count', async (req, res) => {
  const [row] = await query('SELECT COUNT(*) AS count FROM alert WHERE Univ_ID = ? AND Is_Read = FALSE',
    [req.user.univId]);
  res.json(row);
});

router.patch('/alerts/read-all', async (req, res) => {
  await query('UPDATE alert SET Is_Read = TRUE WHERE Univ_ID = ? AND Is_Read = FALSE', [req.user.univId]);
  res.json({ message: 'All alerts marked as read' });
});

router.patch('/alerts/:id/read', validate(idParam, 'params'), async (req, res) => {
  const result = await query('UPDATE alert SET Is_Read = TRUE WHERE Alert_ID = ? AND Univ_ID = ?',
    [req.valid.params.id, req.user.univId]);
  if (result.affectedRows === 0) throw new HttpError(404, 'Alert not found');
  res.json({ message: 'Marked as read' });
});

// ---------------- notices and anomalies ----------------

router.get('/notices', async (req, res) => {
  res.json(await query(
    `SELECT n.*, u.Name AS Issued_By_Name, DATE_FORMAT(tr.Period_Start, '%b %Y') AS Period
     FROM notice n
     JOIN users u ON u.User_ID = n.Issued_By
     LEFT JOIN tax_record tr ON tr.Tax_ID = n.Tax_ID
     WHERE n.Univ_ID = ?
     ORDER BY n.Issued_At DESC`,
    [req.user.univId]
  ));
});

router.patch('/notices/:id/respond', validate(idParam, 'params'),
  validate(z.object({ response: z.string().trim().min(5).max(5000) })),
  async (req, res) => {
    const result = await query(
      `UPDATE notice SET Response = ?, Status = 'Responded', Responded_At = NOW()
       WHERE Notice_ID = ? AND Univ_ID = ? AND Status = 'Open'`,
      [req.valid.body.response, req.valid.params.id, req.user.univId]
    );
    if (result.affectedRows === 0) throw new HttpError(400, 'Notice not found or already answered');
    res.json({ message: 'Response sent' });
  });

router.get('/anomalies', async (req, res) => {
  res.json(await query(
    `SELECT a.Anomaly_ID, a.Rule_Code, a.Severity, a.Details, a.Status, a.Detected_At,
            a.Trans_ID, a.Payment_ID
     FROM anomaly a WHERE a.Univ_ID = ? ORDER BY a.Detected_At DESC`,
    [req.user.univId]
  ));
});

// ---------------- dashboard statistics (your 5 original endpoints + 1) ----------------

router.get('/stats/overview', validate(fyQuery, 'query'), async (req, res) => {
  res.json(await reports.getOverview(req.user.univId, req.valid.query.fy, todayIST()));
});
router.get('/stats/monthly-revenue', validate(fyQuery, 'query'), async (req, res) => {
  res.json(await reports.getMonthlyRevenue(req.user.univId, req.valid.query.fy));
});
router.get('/stats/monthly-tax', validate(fyQuery, 'query'), async (req, res) => {
  res.json(await reports.getMonthlyTax(req.user.univId, req.valid.query.fy));
});
router.get('/stats/tax-status', validate(fyQuery, 'query'), async (req, res) => {
  res.json(await reports.getTaxStatus(req.user.univId, req.valid.query.fy, todayIST()));
});
router.get('/stats/payments', validate(fyQuery, 'query'), async (req, res) => {
  res.json(await reports.getPaymentHistory(req.user.univId, req.valid.query.fy));
});
router.get('/stats/income-by-type', validate(fyQuery, 'query'), async (req, res) => {
  res.json(await reports.getIncomeByType(req.user.univId, req.valid.query.fy));
});

export default router;
