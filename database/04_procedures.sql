-- =====================================================================
-- University Tax Compliance Portal
-- File: database/04_procedures.sql
-- Purpose: stored procedures = named blocks of SQL the backend CALLs.
--   Reports   : return rows for dashboards / tables
--   Actions   : change data safely inside a TRANSACTION (all-or-nothing)
--   Scheduled : Generate_Daily_Alerts, run every morning by node-cron
-- Run (inside mysql):  SOURCE database/04_procedures.sql;
-- Errors are raised with SIGNAL SQLSTATE '45000' -> the backend turns them
-- into a 400 response with the same message.
-- =====================================================================

USE university_tax;

DROP PROCEDURE IF EXISTS University_Income_Breakdown;
DROP PROCEDURE IF EXISTS Unpaid_Tax_Details_By_University;
DROP PROCEDURE IF EXISTS University_Tax_Summary;
DROP PROCEDURE IF EXISTS Overdue_Report;
DROP PROCEDURE IF EXISTS Approve_University;
DROP PROCEDURE IF EXISTS Reject_University;
DROP PROCEDURE IF EXISTS Verify_Payment;
DROP PROCEDURE IF EXISTS Generate_Daily_Alerts;
DROP PROCEDURE IF EXISTS Extend_Due_Date;

DELIMITER //

-- =====================================================================
-- REPORTS
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. University_Income_Breakdown(1, '2025-04-01', '2026-03-31')
--    Every income entry in a date range with its GST split and TDS.
--    (your old procedure, now with CGST/SGST/IGST and a date filter)
-- ---------------------------------------------------------------------
CREATE PROCEDURE University_Income_Breakdown(IN p_univ_id INT,
                                             IN p_from    DATE,
                                             IN p_to      DATE)
BEGIN
    SELECT
        t.Trans_ID,
        t.Entry_Type,
        t.Original_Trans_ID,
        t.Trans_Date,
        d.Name                                   AS Department,
        s.Source_Name                            AS Income_Source,
        r.Income_Type,
        r.GST_Category,
        x.Sign * t.Amount                        AS Amount,        -- credit notes show as minus
        t.GST_Rate,
        x.Sign * t.GST_Amount                    AS GST_Amount,
        IF(x.Inter = 1, 0, x.Sign * ROUND(t.GST_Amount / 2, 2))                    AS CGST,
        IF(x.Inter = 1, 0, x.Sign * (t.GST_Amount - ROUND(t.GST_Amount / 2, 2)))   AS SGST,
        IF(x.Inter = 1, x.Sign * t.GST_Amount, 0)                                  AS IGST,
        x.Sign * t.TDS_Deducted                  AS TDS_Deducted,
        t.Mode,
        t.Payer_Name,
        t.Reference_No
    FROM revenue_transaction t
    JOIN department    d ON d.Dept_ID    = t.Dept_ID
    JOIN income_source s ON s.Source_ID  = t.Source_ID
    JOIN tax_rule      r ON r.TaxRule_ID = s.TaxRule_ID
    -- small helper row: +1/-1 and same-state/other-state, worked out once per entry
    JOIN LATERAL (SELECT IF(t.Entry_Type = 'CREDIT_NOTE', -1, 1)          AS Sign,
                         Is_Inter_State(d.Univ_ID, t.Place_Of_Supply)     AS Inter) AS x
    WHERE d.Univ_ID = p_univ_id
      AND t.Trans_Date BETWEEN p_from AND p_to
    ORDER BY t.Trans_Date, t.Trans_ID;
END //

-- ---------------------------------------------------------------------
-- 2. Unpaid_Tax_Details_By_University(1, CURDATE())
--    One row per monthly bill that still has GST OR interest unpaid.
--    FIX: the old version joined tax_record to every transaction of the
--    year, so each transaction appeared once per tax row (duplicates).
--    Now it reads the monthly bills directly: one bill = one row.
-- ---------------------------------------------------------------------
CREATE PROCEDURE Unpaid_Tax_Details_By_University(IN p_univ_id INT,
                                                  IN p_as_of   DATE)
BEGIN
    SELECT
        b.*,
        b.Tax_Outstanding + b.Interest_Outstanding AS Total_Payable
    FROM (
        SELECT
            tr.Tax_ID,
            DATE_FORMAT(tr.Period_Start, '%b %Y')            AS Tax_Period,
            tr.Financial_Year,
            tr.Tax_Due,
            tr.Tax_Paid,
            GREATEST(tr.Tax_Due - tr.Tax_Paid, 0)             AS Tax_Outstanding,
            tr.Due_Date,
            IF(tr.Tax_Paid < tr.Tax_Due,
               GREATEST(DATEDIFF(p_as_of, tr.Due_Date), 0), 0) AS Days_Late,
            Calculate_Bill_Interest(tr.Tax_ID, p_as_of)       AS Interest_Accrued,
            tr.Interest_Paid,
            Get_Interest_Outstanding(tr.Tax_ID, p_as_of)      AS Interest_Outstanding,
            -- money the university says it paid but the admin hasn't verified yet
            (SELECT IFNULL(SUM(p.Amount), 0) FROM payment p
              WHERE p.Tax_ID = tr.Tax_ID AND p.Status = 'Pending') AS Pending_Verification
        FROM tax_record tr
        WHERE tr.Univ_ID = p_univ_id
    ) AS b
    WHERE b.Tax_Outstanding > 0 OR b.Interest_Outstanding > 0
    ORDER BY b.Due_Date;
END //

-- ---------------------------------------------------------------------
-- 3. University_Tax_Summary(1, '2025-26', CURDATE())
--    One row with the headline numbers for the university dashboard.
--    (your old University_Total_Tax, extended)
-- ---------------------------------------------------------------------
CREATE PROCEDURE University_Tax_Summary(IN p_univ_id        INT,
                                        IN p_financial_year CHAR(7),
                                        IN p_as_of          DATE)
BEGIN
    DECLARE v_fy_start DATE;
    DECLARE v_fy_end   DATE;

    -- '2025-26' -> 2025-04-01 .. 2026-03-31  (a date range lets MySQL use the index)
    SET v_fy_start = STR_TO_DATE(CONCAT(LEFT(p_financial_year, 4), '-04-01'), '%Y-%m-%d');
    SET v_fy_end   = DATE_SUB(DATE_ADD(v_fy_start, INTERVAL 1 YEAR), INTERVAL 1 DAY);

    SELECT
        u.Univ_ID,
        u.Name                                                   AS University,
        p_financial_year                                         AS Financial_Year,
        IFNULL(SUM(tr.Total_Income), 0)                          AS Total_Income,
        IFNULL(SUM(tr.Taxable_Income), 0)                        AS Taxable_Income,
        IFNULL(SUM(tr.Total_Income - tr.Taxable_Income), 0)      AS Exempt_Income,
        IFNULL(SUM(tr.Tax_Due), 0)                               AS GST_Due,
        IFNULL(SUM(tr.Tax_Paid), 0)                              AS GST_Paid,
        IFNULL(SUM(GREATEST(tr.Tax_Due - tr.Tax_Paid, 0)), 0)    AS Outstanding,   -- overpaid bill counts as 0
        IFNULL(SUM(Calculate_Bill_Interest(tr.Tax_ID, p_as_of)), 0) AS Interest_Accrued,
        IFNULL(SUM(tr.Interest_Paid), 0)                         AS Interest_Paid,
        IFNULL(SUM(Get_Interest_Outstanding(tr.Tax_ID, p_as_of)), 0) AS Interest_Outstanding,
        (SELECT IFNULL(SUM(IF(t.Entry_Type = 'CREDIT_NOTE', -t.TDS_Deducted, t.TDS_Deducted)), 0)
           FROM revenue_transaction t
           JOIN department d ON d.Dept_ID = t.Dept_ID
          WHERE d.Univ_ID = p_univ_id
            AND t.Trans_Date BETWEEN v_fy_start AND v_fy_end)    AS TDS_Refund_Claimable,
        Compliance_Status(u.Univ_ID, p_as_of)                    AS Compliance
    FROM university u
    LEFT JOIN tax_record tr ON tr.Univ_ID = u.Univ_ID
                           AND tr.Financial_Year = p_financial_year
    WHERE u.Univ_ID = p_univ_id
    GROUP BY u.Univ_ID, u.Name;
END //

-- ---------------------------------------------------------------------
-- 4. Overdue_Report(CURDATE())
--    Admin view: every approved university with its compliance position.
-- ---------------------------------------------------------------------
CREATE PROCEDURE Overdue_Report(IN p_as_of DATE)
BEGIN
    SELECT
        u.Univ_ID,
        u.Name                                         AS University,
        u.GSTIN,
        u.State,
        COUNT(CASE WHEN tr.Due_Date < p_as_of
                    AND (tr.Tax_Paid < tr.Tax_Due
                         OR Get_Interest_Outstanding(tr.Tax_ID, p_as_of) > 0)
                   THEN 1 END)                         AS Overdue_Bills,
        IFNULL(SUM(GREATEST(tr.Tax_Due - tr.Tax_Paid, 0)), 0) AS Tax_Outstanding,
        IFNULL(SUM(Get_Interest_Outstanding(tr.Tax_ID, p_as_of)), 0) AS Interest_Outstanding,
        Compliance_Status(u.Univ_ID, p_as_of)          AS Compliance
    FROM university u
    LEFT JOIN tax_record tr ON tr.Univ_ID = u.Univ_ID
    WHERE u.Status = 'APPROVED'
    GROUP BY u.Univ_ID, u.Name, u.GSTIN, u.State
    ORDER BY Overdue_Bills DESC, Tax_Outstanding DESC;
END //

-- =====================================================================
-- ACTIONS  (each one is a transaction: everything succeeds or nothing does)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 5. Approve_University(univ_id, admin_id)
--    PENDING -> APPROVED, records who approved it, creates default departments.
-- ---------------------------------------------------------------------
CREATE PROCEDURE Approve_University(IN p_univ_id INT, IN p_admin_id INT)
BEGIN
    DECLARE v_status VARCHAR(20);

    -- if ANY statement below fails: undo everything, then pass the error on
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- FOR UPDATE locks this row, so two admins can't approve at the same moment
    SELECT Status INTO v_status FROM university
    WHERE Univ_ID = p_univ_id FOR UPDATE;

    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'University not found';
    END IF;
    IF v_status <> 'PENDING' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only a PENDING registration can be approved';
    END IF;

    UPDATE university
    SET Status = 'APPROVED', Reviewed_By = p_admin_id, Reviewed_At = NOW(),
        Rejection_Reason = NULL
    WHERE Univ_ID = p_univ_id;

    -- every university starts with these two departments; it can add more
    INSERT INTO department (Name, Univ_ID) VALUES
        ('Administration', p_univ_id),
        ('Accounts',       p_univ_id)
    ON DUPLICATE KEY UPDATE Name = Name;          -- already there -> do nothing

    COMMIT;
END //

-- ---------------------------------------------------------------------
-- 6. Reject_University(univ_id, admin_id, 'GSTIN does not match records')
-- ---------------------------------------------------------------------
CREATE PROCEDURE Reject_University(IN p_univ_id INT, IN p_admin_id INT,
                                   IN p_reason  VARCHAR(255))
BEGIN
    DECLARE v_status VARCHAR(20);

    SELECT Status INTO v_status FROM university WHERE Univ_ID = p_univ_id;

    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'University not found';
    END IF;
    IF v_status <> 'PENDING' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only a PENDING registration can be rejected';
    END IF;
    IF p_reason IS NULL OR TRIM(p_reason) = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A rejection reason is required';
    END IF;

    UPDATE university
    SET Status = 'REJECTED', Rejection_Reason = p_reason,
        Reviewed_By = p_admin_id, Reviewed_At = NOW()
    WHERE Univ_ID = p_univ_id;
END //

-- ---------------------------------------------------------------------
-- 7. Verify_Payment(payment_id, admin_id, 'Verified' | 'Rejected', remarks)
--    Verified + Payment_For 'Tax'      -> the bill's Tax_Paid goes up
--    Verified + Payment_For 'Interest' -> the bill's Interest_Paid goes up
--    Paid MORE than was owed -> OVERPAYMENT anomaly for the admin.
-- ---------------------------------------------------------------------
CREATE PROCEDURE Verify_Payment(IN p_payment_id INT, IN p_admin_id INT,
                                IN p_decision   VARCHAR(10), IN p_remarks VARCHAR(255))
BEGIN
    DECLARE v_status      VARCHAR(10);
    DECLARE v_amount      DECIMAL(15,2);
    DECLARE v_for         VARCHAR(10);
    DECLARE v_pay_date    DATE;
    DECLARE v_tax_id      INT;
    DECLARE v_univ_id     INT;
    DECLARE v_outstanding DECIMAL(15,2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_decision NOT IN ('Verified', 'Rejected') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Decision must be Verified or Rejected';
    END IF;
    IF p_decision = 'Rejected' AND (p_remarks IS NULL OR TRIM(p_remarks) = '') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Give a reason when rejecting a payment';
    END IF;

    START TRANSACTION;

    -- lock the payment so it can't be verified twice at the same time
    SELECT Status, Amount, Payment_For, Payment_Date, Tax_ID
      INTO v_status, v_amount, v_for, v_pay_date, v_tax_id
    FROM payment WHERE Payment_ID = p_payment_id FOR UPDATE;

    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Payment not found';
    END IF;
    IF v_status <> 'Pending' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'This payment has already been processed';
    END IF;

    UPDATE payment
    SET Status = p_decision, Verified_By = p_admin_id, Verified_At = NOW(),
        Remarks = p_remarks
    WHERE Payment_ID = p_payment_id;

    IF p_decision = 'Verified' THEN
        -- lock the bill too
        SELECT Univ_ID INTO v_univ_id FROM tax_record WHERE Tax_ID = v_tax_id FOR UPDATE;

        IF v_for = 'Tax' THEN
            SELECT Tax_Due - Tax_Paid INTO v_outstanding FROM tax_record WHERE Tax_ID = v_tax_id;
            UPDATE tax_record SET Tax_Paid = Tax_Paid + v_amount WHERE Tax_ID = v_tax_id;
        ELSE
            -- interest owed as on the day the money was paid
            SET v_outstanding = Get_Interest_Outstanding(v_tax_id, v_pay_date);
            UPDATE tax_record SET Interest_Paid = Interest_Paid + v_amount WHERE Tax_ID = v_tax_id;
        END IF;

        IF v_amount > v_outstanding THEN
            INSERT INTO anomaly (Univ_ID, Payment_ID, Rule_Code, Severity, Details)
            VALUES (v_univ_id, p_payment_id, 'OVERPAYMENT', 'Low',
                    CONCAT(v_for, ' payment of Rs ', v_amount, ' against Rs ',
                           GREATEST(v_outstanding, 0), ' due; excess Rs ',
                           v_amount - GREATEST(v_outstanding, 0),
                           ' can be refunded or adjusted'));
        END IF;
    END IF;

    COMMIT;
END //

-- ---------------------------------------------------------------------
-- 7b. Extend_Due_Date('2025-10-01', '2025-11-30')
--     The government often extends GST due dates. The admin applies the new
--     date to every bill of that month. Interest is then counted from it.
-- ---------------------------------------------------------------------
CREATE PROCEDURE Extend_Due_Date(IN p_period_start DATE, IN p_new_due_date DATE)
BEGIN
    IF DAY(p_period_start) <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Period must be the 1st of a month';
    END IF;
    IF p_new_due_date <= Get_Due_Date(p_period_start) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'New due date must be later than the normal due date';
    END IF;

    UPDATE tax_record SET Due_Date = p_new_due_date
    WHERE Period_Start = p_period_start;

    SELECT ROW_COUNT() AS Bills_Updated;
END //

-- =====================================================================
-- SCHEDULED JOB
-- =====================================================================

-- ---------------------------------------------------------------------
-- 8. Generate_Daily_Alerts('2025-11-25')
--    Run every morning by node-cron (and once when the server starts).
--    For every bill of an approved university:
--      tax unpaid, due in 7, 3 or 1 days -> DUE_SOON
--      tax unpaid, due today             -> DUE_TODAY
--      tax unpaid, past due              -> OVERDUE, EVERY day, with interest
--      tax paid but interest unpaid      -> INTEREST_DUE, EVERY day
--    Alerts stop by themselves once tax AND interest are fully paid.
--    UNIQUE(Tax_ID, Alert_Date) + ON DUPLICATE KEY = safe to run twice a day.
--    The date is a parameter, so you can test "what happens on 5 Dec?"
-- ---------------------------------------------------------------------
CREATE PROCEDURE Generate_Daily_Alerts(IN p_today DATE)
BEGIN
    INSERT INTO alert (Univ_ID, Tax_ID, Alert_Type, Alert_Date, Outstanding, Interest, Message)
    SELECT
        b.Univ_ID,
        b.Tax_ID,
        b.Alert_Type,
        p_today,
        b.Outstanding,
        b.Interest,
        CASE b.Alert_Type
            WHEN 'DUE_SOON'  THEN CONCAT('GST of Rs ', b.Outstanding, ' for ', b.Period,
                                         ' is due on ', DATE_FORMAT(b.Due_Date, '%d %b %Y'),
                                         ' (in ', b.Days_Left, ' day', IF(b.Days_Left = 1, '', 's'), ').')
            WHEN 'DUE_TODAY' THEN CONCAT('GST of Rs ', b.Outstanding, ' for ', b.Period,
                                         ' is due TODAY. Pay now to avoid 18% interest.')
            WHEN 'OVERDUE'   THEN CONCAT('GST of Rs ', b.Outstanding, ' for ', b.Period,
                                         ' is overdue by ', -b.Days_Left, ' day',
                                         IF(b.Days_Left = -1, '', 's'),
                                         '. Interest so far: Rs ', b.Interest, '.')
            ELSE                  CONCAT('GST for ', b.Period, ' is paid, but interest of Rs ',
                                         b.Interest, ' for late payment is still unpaid.')
        END
    FROM (
        SELECT
            tr.Univ_ID,
            tr.Tax_ID,
            tr.Due_Date,
            DATE_FORMAT(tr.Period_Start, '%b %Y')            AS Period,
            GREATEST(tr.Tax_Due - tr.Tax_Paid, 0)            AS Outstanding,
            DATEDIFF(tr.Due_Date, p_today)                   AS Days_Left,
            Get_Interest_Outstanding(tr.Tax_ID, p_today)     AS Interest,
            CASE
                WHEN tr.Tax_Paid < tr.Tax_Due AND DATEDIFF(tr.Due_Date, p_today) IN (7, 3, 1)
                    THEN 'DUE_SOON'
                WHEN tr.Tax_Paid < tr.Tax_Due AND DATEDIFF(tr.Due_Date, p_today) = 0
                    THEN 'DUE_TODAY'
                WHEN tr.Tax_Paid < tr.Tax_Due AND DATEDIFF(tr.Due_Date, p_today) < 0
                    THEN 'OVERDUE'
                WHEN tr.Tax_Paid >= tr.Tax_Due
                     AND Get_Interest_Outstanding(tr.Tax_ID, p_today) > 0
                    THEN 'INTEREST_DUE'
            END                                              AS Alert_Type
        FROM tax_record tr
        JOIN university u ON u.Univ_ID = tr.Univ_ID
        WHERE u.Status = 'APPROVED'
    ) AS b
    WHERE b.Alert_Type IS NOT NULL                   -- e.g. 5 days left -> no alert today
    ON DUPLICATE KEY UPDATE Alert_ID = Alert_ID;     -- already alerted today -> skip

    -- tell the caller how many alerts exist for this day
    SELECT COUNT(*) AS Alerts_For_Day FROM alert WHERE Alert_Date = p_today;
END //

DELIMITER ;