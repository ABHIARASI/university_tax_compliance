-- =====================================================================
-- University Tax Compliance Portal
-- File: database/05_triggers.sql
-- Purpose: triggers = SQL that runs AUTOMATICALLY when a row is inserted,
--          updated or deleted. Nobody can forget to call them, and they
--          work the same whether data comes from the app, a script or a DBA.
--
--   BEFORE triggers : check / fill in values of the row being saved (NEW.x)
--   AFTER  triggers : update OTHER tables once the row is saved
--
-- Run (inside mysql):  SOURCE database/05_triggers.sql;
-- =====================================================================

USE university_tax;

DROP TRIGGER IF EXISTS trg_university_before_insert;
DROP TRIGGER IF EXISTS trg_university_before_update;
DROP TRIGGER IF EXISTS trg_tax_record_before_insert;
DROP TRIGGER IF EXISTS trg_revenue_before_insert;
DROP TRIGGER IF EXISTS trg_revenue_after_insert;
DROP TRIGGER IF EXISTS trg_revenue_before_update;
DROP TRIGGER IF EXISTS trg_revenue_before_delete;
DROP TRIGGER IF EXISTS trg_payment_before_insert;
DROP TRIGGER IF EXISTS trg_tax_rule_after_update;

DELIMITER //

-- =====================================================================
-- UNIVERSITY : GSTIN must be genuine and match the state
-- =====================================================================
CREATE TRIGGER trg_university_before_insert
BEFORE INSERT ON university
FOR EACH ROW
BEGIN
    IF Is_Valid_GSTIN(NEW.GSTIN) = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid GSTIN: check digit does not match';
    END IF;
    IF LEFT(NEW.GSTIN, 2) <> (SELECT State_Code FROM indian_state WHERE State_Name = NEW.State) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'GSTIN state code does not match the selected state';
    END IF;
END //

CREATE TRIGGER trg_university_before_update
BEFORE UPDATE ON university
FOR EACH ROW
BEGIN
    -- GSTIN and state decide every tax calculation; once approved they are locked
    IF OLD.Status = 'APPROVED' AND (NEW.GSTIN <> OLD.GSTIN OR NEW.State <> OLD.State) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'GSTIN and state cannot change after approval; register a new GSTIN';
    END IF;
END //

-- =====================================================================
-- TAX_RECORD : due date = 20th of next month (your old trigger, fixed:
-- it used to give 1 July of the SAME year)
-- =====================================================================
CREATE TRIGGER trg_tax_record_before_insert
BEFORE INSERT ON tax_record
FOR EACH ROW
BEGIN
    IF NEW.Due_Date IS NULL THEN
        SET NEW.Due_Date = Get_Due_Date(NEW.Period_Start);
    END IF;
END //

-- =====================================================================
-- REVENUE_TRANSACTION : BEFORE INSERT
--   1. checks: approved university, date not in the future, payer details
--   2. credit note: must reverse a real invoice of the same university,
--      for no more than what is left of it; copies its GST rate
--   3. invoice: works out the GST rate (incl. the hostel test)
--   4. fills GST_Amount, TDS_Expected, TDS_Deducted
-- =====================================================================
CREATE TRIGGER trg_revenue_before_insert
BEFORE INSERT ON revenue_transaction
FOR EACH ROW
BEGIN
    DECLARE v_univ_id       INT;
    DECLARE v_univ_status   VARCHAR(20);
    DECLARE v_tds_rate      DECIMAL(5,2);
    DECLARE v_orig_univ     INT;
    DECLARE v_orig_type     VARCHAR(15);
    DECLARE v_orig_amount   DECIMAL(15,2);
    DECLARE v_orig_rate     DECIMAL(5,2);
    DECLARE v_orig_tds      DECIMAL(15,2);
    DECLARE v_already       DECIMAL(15,2);

    -- 1. which university is this, and may it file?
    SELECT u.Univ_ID, u.Status INTO v_univ_id, v_univ_status
    FROM department d JOIN university u ON u.Univ_ID = d.Univ_ID
    WHERE d.Dept_ID = NEW.Dept_ID;

    IF v_univ_status IS NULL OR v_univ_status <> 'APPROVED' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only an APPROVED university can add income';
    END IF;
    IF NEW.Trans_Date > CURDATE() THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Income date cannot be in the future';
    END IF;
    IF NEW.Payer_GSTIN IS NOT NULL AND Is_Valid_GSTIN(NEW.Payer_GSTIN) = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid payer GSTIN';
    END IF;

    SELECT r.TDS_Rate INTO v_tds_rate
    FROM income_source s JOIN tax_rule r ON r.TaxRule_ID = s.TaxRule_ID
    WHERE s.Source_ID = NEW.Source_ID;

    -- the cash rule and the TDS threshold both work per payer
    IF (NEW.Mode = 'Cash' OR v_tds_rate > 0) AND
       (NEW.Payer_Name IS NULL OR TRIM(NEW.Payer_Name) = '') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Payer name is required for cash receipts and for income with TDS';
    END IF;

    IF NEW.Entry_Type = 'CREDIT_NOTE' THEN
        -- 2. credit note
        SELECT d.Univ_ID, t.Entry_Type, t.Amount, t.GST_Rate, t.TDS_Deducted
          INTO v_orig_univ, v_orig_type, v_orig_amount, v_orig_rate, v_orig_tds
        FROM revenue_transaction t JOIN department d ON d.Dept_ID = t.Dept_ID
        WHERE t.Trans_ID = NEW.Original_Trans_ID;

        IF v_orig_univ IS NULL OR v_orig_univ <> v_univ_id OR v_orig_type <> 'INVOICE' THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'A credit note must reverse an invoice of the same university';
        END IF;

        SELECT IFNULL(SUM(Amount), 0) INTO v_already
        FROM revenue_transaction
        WHERE Original_Trans_ID = NEW.Original_Trans_ID;

        IF NEW.Amount > v_orig_amount - v_already THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Credit note is more than what is left of the original invoice';
        END IF;

        -- same rate, same place, same source as the invoice it reverses
        SET NEW.Source_ID       = (SELECT Source_ID FROM revenue_transaction
                                   WHERE Trans_ID = NEW.Original_Trans_ID);
        SET NEW.Place_Of_Supply = (SELECT Place_Of_Supply FROM revenue_transaction
                                   WHERE Trans_ID = NEW.Original_Trans_ID);
        SET NEW.GST_Rate     = v_orig_rate;
        SET NEW.TDS_Expected = ROUND(IFNULL(v_orig_tds, 0) * NEW.Amount / v_orig_amount, 2);
    ELSE
        -- 3. invoice: rate as on today (stored, so later rate changes don't touch it)
        SET NEW.GST_Rate = Get_Effective_GST_Rate(NEW.Source_ID, NEW.Amount,
                                                  NEW.Beneficiaries, NEW.Stay_Days);
        SET NEW.TDS_Expected = Calculate_TDS(NEW.Amount, NEW.Source_ID, v_univ_id,
                                             NEW.Payer_Name, NEW.Trans_Date);
    END IF;

    -- 4. GST and TDS
    SET NEW.GST_Amount = ROUND(NEW.Amount * NEW.GST_Rate / 100, 2);

    IF NEW.TDS_Deducted IS NULL THEN
        SET NEW.TDS_Deducted = NEW.TDS_Expected;
        SET NEW.TDS_Source   = 'CALCULATED';
    ELSE
        SET NEW.TDS_Source   = 'ENTERED';      -- real figure from the client's TDS certificate
    END IF;
END //

-- =====================================================================
-- REVENUE_TRANSACTION : AFTER INSERT
--   A. adds the entry to that month's GST bill (creates the bill if needed)
--   B. runs the anomaly rules
-- =====================================================================
CREATE TRIGGER trg_revenue_after_insert
AFTER INSERT ON revenue_transaction
FOR EACH ROW
BEGIN
    DECLARE v_univ_id     INT;
    DECLARE v_sign        INT;
    DECLARE v_period      DATE;
    DECLARE v_inter       TINYINT;
    DECLARE v_cgst        DECIMAL(15,2);
    DECLARE v_sgst        DECIMAL(15,2);
    DECLARE v_igst        DECIMAL(15,2);
    DECLARE v_taxable     DECIMAL(15,2);
    DECLARE v_cash_day    DECIMAL(15,2);
    DECLARE v_cash_ref    DECIMAL(15,2);
    DECLARE v_avg         DECIMAL(15,2);
    DECLARE v_count       INT;

    SELECT Univ_ID INTO v_univ_id FROM department WHERE Dept_ID = NEW.Dept_ID;

    -- ---------- A. update the monthly GST bill ----------
    -- invoice adds, credit note subtracts. A credit note corrects the bill of the
    -- ORIGINAL invoice's month (an amendment), so no bill can go negative.
    SET v_sign = IF(NEW.Entry_Type = 'CREDIT_NOTE', -1, 1);

    IF NEW.Entry_Type = 'CREDIT_NOTE' THEN
        SELECT DATE_FORMAT(Trans_Date, '%Y-%m-01') INTO v_period
        FROM revenue_transaction WHERE Trans_ID = NEW.Original_Trans_ID;
    ELSE
        SET v_period = DATE_FORMAT(NEW.Trans_Date, '%Y-%m-01');
    END IF;

    SET v_inter   = Is_Inter_State(v_univ_id, NEW.Place_Of_Supply);
    SET v_igst    = IF(v_inter = 1, NEW.GST_Amount, 0);
    SET v_cgst    = IF(v_inter = 1, 0, ROUND(NEW.GST_Amount / 2, 2));
    SET v_sgst    = IF(v_inter = 1, 0, NEW.GST_Amount - ROUND(NEW.GST_Amount / 2, 2));  -- no paisa lost
    SET v_taxable = IF(NEW.GST_Rate > 0, NEW.Amount, 0);

    INSERT INTO tax_record (Univ_ID, Period_Start, Total_Income, Taxable_Income,
                            CGST, SGST, IGST, Tax_Due)
    VALUES (v_univ_id, v_period, v_sign * NEW.Amount, v_sign * v_taxable,
            v_sign * v_cgst, v_sign * v_sgst, v_sign * v_igst, v_sign * NEW.GST_Amount)
    ON DUPLICATE KEY UPDATE                       -- bill exists -> add to it (no duplicates)
        Total_Income   = Total_Income   + v_sign * NEW.Amount,
        Taxable_Income = Taxable_Income + v_sign * v_taxable,
        CGST           = CGST           + v_sign * v_cgst,
        SGST           = SGST           + v_sign * v_sgst,
        IGST           = IGST           + v_sign * v_igst,
        Tax_Due        = Tax_Due        + v_sign * NEW.GST_Amount;

    -- ---------- B. anomaly rules (invoices only) ----------
    IF NEW.Entry_Type = 'INVOICE' THEN

        -- B1. CASH_LIMIT : Rs 2 lakh or more in cash (Sec 186 IT Act 2025, old 269ST)
        --     three tests: one receipt / one payer in one day / one invoice or event
        IF NEW.Mode = 'Cash' THEN
            SELECT IFNULL(SUM(t.Amount), 0) INTO v_cash_day
            FROM revenue_transaction t JOIN department d ON d.Dept_ID = t.Dept_ID
            WHERE d.Univ_ID = v_univ_id AND t.Mode = 'Cash' AND t.Entry_Type = 'INVOICE'
              AND t.Payer_Name = NEW.Payer_Name AND t.Trans_Date = NEW.Trans_Date;

            SET v_cash_ref = 0;
            IF NEW.Reference_No IS NOT NULL THEN
                SELECT IFNULL(SUM(t.Amount), 0) INTO v_cash_ref
                FROM revenue_transaction t JOIN department d ON d.Dept_ID = t.Dept_ID
                WHERE d.Univ_ID = v_univ_id AND t.Mode = 'Cash' AND t.Entry_Type = 'INVOICE'
                  AND t.Reference_No = NEW.Reference_No;
            END IF;

            IF NEW.Amount >= 200000 THEN
                INSERT INTO anomaly (Univ_ID, Trans_ID, Rule_Code, Severity, Details)
                VALUES (v_univ_id, NEW.Trans_ID, 'CASH_LIMIT', 'High',
                        CONCAT('Single cash receipt of Rs ', NEW.Amount,
                               ' (limit: below Rs 2,00,000). Penalty can equal the amount.'));
            ELSEIF v_cash_day >= 200000 THEN
                INSERT INTO anomaly (Univ_ID, Trans_ID, Rule_Code, Severity, Details)
                VALUES (v_univ_id, NEW.Trans_ID, 'CASH_LIMIT', 'High',
                        CONCAT('Cash from ', NEW.Payer_Name, ' on ', NEW.Trans_Date,
                               ' totals Rs ', v_cash_day, ' (limit: below Rs 2,00,000 per day).'));
            ELSEIF v_cash_ref >= 200000 THEN
                INSERT INTO anomaly (Univ_ID, Trans_ID, Rule_Code, Severity, Details)
                VALUES (v_univ_id, NEW.Trans_ID, 'CASH_LIMIT', 'High',
                        CONCAT('Cash against reference ', NEW.Reference_No, ' totals Rs ',
                               v_cash_ref, ' (limit: below Rs 2,00,000 per transaction/event).'));
            END IF;
        END IF;

        -- B2. SPIKE : more than 3x the usual amount for this department + source
        --     (needs at least 3 earlier entries in the last 12 months to know "usual")
        SELECT AVG(Amount), COUNT(*) INTO v_avg, v_count
        FROM revenue_transaction
        WHERE Dept_ID = NEW.Dept_ID AND Source_ID = NEW.Source_ID
          AND Entry_Type = 'INVOICE' AND Trans_ID <> NEW.Trans_ID
          AND Trans_Date BETWEEN DATE_SUB(NEW.Trans_Date, INTERVAL 12 MONTH) AND NEW.Trans_Date;

        IF v_count >= 3 AND NEW.Amount > 3 * v_avg THEN
            INSERT INTO anomaly (Univ_ID, Trans_ID, Rule_Code, Severity, Details)
            VALUES (v_univ_id, NEW.Trans_ID, 'SPIKE', 'Medium',
                    CONCAT('Rs ', NEW.Amount, ' is ', ROUND(NEW.Amount / v_avg, 1),
                           'x the usual Rs ', ROUND(v_avg, 2), ' for this department and source.'));
        END IF;

        -- B3. DUPLICATE : same department, source, amount and payer within 1 day
        IF EXISTS (SELECT 1 FROM revenue_transaction
                   WHERE Trans_ID <> NEW.Trans_ID AND Entry_Type = 'INVOICE'
                     AND Dept_ID = NEW.Dept_ID AND Source_ID = NEW.Source_ID
                     AND Amount = NEW.Amount
                     AND Payer_Name <=> NEW.Payer_Name          -- <=> : NULL-safe equals
                     AND ABS(DATEDIFF(Trans_Date, NEW.Trans_Date)) <= 1) THEN
            INSERT INTO anomaly (Univ_ID, Trans_ID, Rule_Code, Severity, Details)
            VALUES (v_univ_id, NEW.Trans_ID, 'DUPLICATE', 'Medium',
                    CONCAT('Looks like a repeat: same amount Rs ', NEW.Amount,
                           ', source and payer within 1 day.'));
        END IF;

        -- B4. TDS_MISMATCH : client's actual TDS differs from what the law expects
        IF NEW.TDS_Source = 'ENTERED' AND ABS(NEW.TDS_Deducted - NEW.TDS_Expected) > 1 THEN
            INSERT INTO anomaly (Univ_ID, Trans_ID, Rule_Code, Severity, Details)
            VALUES (v_univ_id, NEW.Trans_ID, 'TDS_MISMATCH', 'Low',
                    CONCAT('Client deducted TDS of Rs ', NEW.TDS_Deducted,
                           ' but Rs ', NEW.TDS_Expected, ' was expected. Check the TDS certificate.'));
        END IF;
    END IF;
END //

-- =====================================================================
-- REVENUE_TRANSACTION : no editing, no deleting (an audit trail must not
-- change). Only the description may be corrected. Use a CREDIT_NOTE.
-- =====================================================================
CREATE TRIGGER trg_revenue_before_update
BEFORE UPDATE ON revenue_transaction
FOR EACH ROW
BEGIN
    IF NOT (NEW.Amount <=> OLD.Amount AND NEW.Trans_Date <=> OLD.Trans_Date
            AND NEW.Source_ID <=> OLD.Source_ID AND NEW.Dept_ID <=> OLD.Dept_ID
            AND NEW.Mode <=> OLD.Mode AND NEW.Place_Of_Supply <=> OLD.Place_Of_Supply
            AND NEW.GST_Amount <=> OLD.GST_Amount AND NEW.TDS_Deducted <=> OLD.TDS_Deducted
            AND NEW.Payer_Name <=> OLD.Payer_Name AND NEW.Entry_Type <=> OLD.Entry_Type) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Income entries cannot be edited. Add a credit note to correct it.';
    END IF;
END //

CREATE TRIGGER trg_revenue_before_delete
BEFORE DELETE ON revenue_transaction
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Income entries cannot be deleted. Add a credit note to reverse it.';
END //

-- =====================================================================
-- PAYMENT : basic sanity before a payment is recorded
-- =====================================================================
CREATE TRIGGER trg_payment_before_insert
BEFORE INSERT ON payment
FOR EACH ROW
BEGIN
    DECLARE v_period DATE;

    SELECT Period_Start INTO v_period FROM tax_record WHERE Tax_ID = NEW.Tax_ID;

    IF NEW.Payment_Date > CURDATE() THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Payment date cannot be in the future';
    END IF;
    IF NEW.Payment_Date < v_period THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Payment date is before the tax period started';
    END IF;
    -- 'Over the Counter' (cash/cheque at the bank) is allowed only up to Rs 10,000 per challan
    IF NEW.Mode = 'Over the Counter' AND NEW.Amount > 10000 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Over-the-counter GST payment is allowed only up to Rs 10,000';
    END IF;
END //

-- =====================================================================
-- TAX_RULE : keep a history of every rate change
-- The backend runs  SET @app_user_id = <admin id>  before the UPDATE,
-- because a trigger can't see who is logged in to the web app.
-- =====================================================================
CREATE TRIGGER trg_tax_rule_after_update
AFTER UPDATE ON tax_rule
FOR EACH ROW
BEGIN
    IF NOT (NEW.Tax_Rate <=> OLD.Tax_Rate AND NEW.TDS_Rate <=> OLD.TDS_Rate) THEN
        INSERT INTO tax_rule_audit (TaxRule_ID, Old_Tax_Rate, New_Tax_Rate,
                                    Old_TDS_Rate, New_TDS_Rate, Changed_By)
        VALUES (NEW.TaxRule_ID, OLD.Tax_Rate, NEW.Tax_Rate,
                OLD.TDS_Rate, NEW.TDS_Rate, @app_user_id);
    END IF;
END //

DELIMITER ;

SHOW TRIGGERS;