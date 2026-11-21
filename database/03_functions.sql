-- =====================================================================
-- University Tax Compliance Portal
-- File: database/03_functions.sql
-- Purpose: small reusable SQL functions. Each returns ONE value.
--          Procedures (file 04) and triggers (file 05) call these,
--          so every tax calculation lives in exactly one place.
-- Run (inside mysql):  SOURCE database/03_functions.sql;
--
-- Every function is declared one of:
--   DETERMINISTIC   -> pure maths: same inputs always give the same answer
--   READS SQL DATA  -> reads tables, so the answer can change if data changes
-- (MySQL refuses to create a function with no such label when binary
--  logging is on, which is the default in MySQL 8 - error 1418.)
-- =====================================================================

USE university_tax;

DROP FUNCTION IF EXISTS Is_Valid_GSTIN;
DROP FUNCTION IF EXISTS Get_Tax_Rate;
DROP FUNCTION IF EXISTS Get_Source_Tax_Rate;
DROP FUNCTION IF EXISTS Calculate_Tax_Amount;
DROP FUNCTION IF EXISTS Is_Income_Exempt;
DROP FUNCTION IF EXISTS Is_Inter_State;
DROP FUNCTION IF EXISTS Calculate_TDS;
DROP FUNCTION IF EXISTS Get_Effective_GST_Rate;
DROP FUNCTION IF EXISTS Get_Interest_Outstanding;
DROP FUNCTION IF EXISTS Get_Due_Date;
DROP FUNCTION IF EXISTS Get_Financial_Year;
DROP FUNCTION IF EXISTS Calculate_Interest;
DROP FUNCTION IF EXISTS Calculate_Bill_Interest;
DROP FUNCTION IF EXISTS Get_Outstanding;
DROP FUNCTION IF EXISTS Total_GST_Due;
DROP FUNCTION IF EXISTS Compliance_Status;

DELIMITER //

-- ---------------------------------------------------------------------
-- 0. Is_Valid_GSTIN('29AABTG4521K1ZX') -> 1 or 0
--    The 15th character of a GSTIN is a CHECK DIGIT calculated from the
--    first 14 (like the last digit of a credit card). A typo makes it wrong.
--    Algorithm (base 36, characters 0-9 then A-Z):
--      for each of the first 14 chars: value x factor (factor 1,2,1,2,...)
--      add (product DIV 36) + (product MOD 36)
--      check = (36 - total MOD 36) MOD 36  -> back to a character
-- ---------------------------------------------------------------------
CREATE FUNCTION Is_Valid_GSTIN(p_gstin CHAR(15))
RETURNS TINYINT
DETERMINISTIC
BEGIN
    DECLARE v_chars   CHAR(36) DEFAULT '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    DECLARE v_i       INT DEFAULT 1;
    DECLARE v_total   INT DEFAULT 0;
    DECLARE v_product INT;

    IF p_gstin IS NULL
       OR p_gstin NOT REGEXP '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$' THEN
        RETURN 0;
    END IF;

    WHILE v_i <= 14 DO
        SET v_product = (LOCATE(SUBSTRING(p_gstin, v_i, 1), v_chars) - 1)
                        * IF(v_i % 2 = 1, 1, 2);
        SET v_total = v_total + (v_product DIV 36) + (v_product MOD 36);
        SET v_i = v_i + 1;
    END WHILE;

    RETURN IF(SUBSTRING(v_chars, ((36 - (v_total MOD 36)) MOD 36) + 1, 1)
              = SUBSTRING(p_gstin, 15, 1), 1, 0);
END //

-- ---------------------------------------------------------------------
-- 1. Get_Tax_Rate('Consultancy') -> 18.00
--    Returns NULL for an unknown income type (so a typo is noticed,
--    instead of silently being treated as 0% / exempt).
-- ---------------------------------------------------------------------
CREATE FUNCTION Get_Tax_Rate(p_income_type VARCHAR(60))
RETURNS DECIMAL(5,2)
READS SQL DATA
BEGIN
    DECLARE v_rate DECIMAL(5,2) DEFAULT NULL;

    SELECT Tax_Rate INTO v_rate
    FROM tax_rule
    WHERE Income_Type = p_income_type;     -- p_ prefix: no clash with column names

    RETURN v_rate;
END //

-- ---------------------------------------------------------------------
-- 2. Get_Source_Tax_Rate(10) -> 18.00   (10 = 'Industry Consultancy')
--    The trigger uses this: a transaction stores Source_ID, not the type.
-- ---------------------------------------------------------------------
CREATE FUNCTION Get_Source_Tax_Rate(p_source_id INT)
RETURNS DECIMAL(5,2)
READS SQL DATA
BEGIN
    DECLARE v_rate DECIMAL(5,2) DEFAULT NULL;

    SELECT r.Tax_Rate INTO v_rate
    FROM income_source s
    JOIN tax_rule r ON r.TaxRule_ID = s.TaxRule_ID
    WHERE s.Source_ID = p_source_id;

    RETURN v_rate;
END //

-- ---------------------------------------------------------------------
-- 3. Calculate_Tax_Amount(500000, 'Consultancy') -> 90000.00
-- ---------------------------------------------------------------------
CREATE FUNCTION Calculate_Tax_Amount(p_amount DECIMAL(15,2), p_income_type VARCHAR(60))
RETURNS DECIMAL(15,2)
READS SQL DATA
BEGIN
    RETURN ROUND(p_amount * Get_Tax_Rate(p_income_type) / 100, 2);
    -- unknown type -> Get_Tax_Rate is NULL -> the whole result is NULL
END //

-- ---------------------------------------------------------------------
-- 4. Is_Income_Exempt('Tuition & Admission Fees') -> 1
--    1 = no GST (EXEMPT or NOT_A_SUPPLY), 0 = taxable, NULL = unknown type
-- ---------------------------------------------------------------------
CREATE FUNCTION Is_Income_Exempt(p_income_type VARCHAR(60))
RETURNS TINYINT
READS SQL DATA
BEGIN
    DECLARE v_category VARCHAR(20) DEFAULT NULL;

    SELECT GST_Category INTO v_category
    FROM tax_rule
    WHERE Income_Type = p_income_type;

    RETURN CASE
        WHEN v_category IS NULL      THEN NULL
        WHEN v_category = 'TAXABLE'  THEN 0
        ELSE 1
    END;
END //

-- ---------------------------------------------------------------------
-- 5. Is_Inter_State(1, 'Maharashtra') -> 1 if university 1 is NOT in Maharashtra
--    Same state  -> CGST + SGST (9% + 9%)
--    Other state -> IGST (18%)
--    NULL place of supply means "same state as the university".
-- ---------------------------------------------------------------------
CREATE FUNCTION Is_Inter_State(p_univ_id INT, p_place_of_supply VARCHAR(50))
RETURNS TINYINT
READS SQL DATA
BEGIN
    DECLARE v_state VARCHAR(50);

    IF p_place_of_supply IS NULL THEN
        RETURN 0;
    END IF;

    SELECT State INTO v_state FROM university WHERE Univ_ID = p_univ_id;

    RETURN IF(v_state = p_place_of_supply, 0, 1);
END //

-- ---------------------------------------------------------------------
-- 6. Get_Effective_GST_Rate(source_id, amount, students, days) -> GST % for ONE entry
--    Normal income: the rule's rate.
--    Hostel (ACCOMMODATION rule):
--      per person per month <= 20,000 AND stay >= 90 days -> 0%  (exempt)
--      otherwise per person per day <= 7,500              -> 5%
--      otherwise                                          -> 18%
-- ---------------------------------------------------------------------
CREATE FUNCTION Get_Effective_GST_Rate(p_source_id INT, p_amount DECIMAL(15,2),
                                       p_persons INT, p_days INT)
RETURNS DECIMAL(5,2)
READS SQL DATA
BEGIN
    DECLARE v_rate    DECIMAL(5,2);
    DECLARE v_special VARCHAR(20);
    DECLARE v_per_person_month DECIMAL(15,2);
    DECLARE v_per_person_day   DECIMAL(15,2);

    SELECT r.Tax_Rate, r.Special_Rule INTO v_rate, v_special
    FROM income_source s
    JOIN tax_rule r ON r.TaxRule_ID = s.TaxRule_ID
    WHERE s.Source_ID = p_source_id;

    IF v_special = 'ACCOMMODATION' THEN
        IF p_persons IS NULL OR p_days IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Hostel fees need the number of students and the days covered';
        END IF;

        SET v_per_person_day   = p_amount / p_persons / p_days;
        SET v_per_person_month = v_per_person_day * 30;

        IF p_days >= 90 AND v_per_person_month <= 20000 THEN
            RETURN 0;
        ELSEIF v_per_person_day <= 7500 THEN
            RETURN 5;
        ELSE
            RETURN 18;
        END IF;
    END IF;

    RETURN v_rate;
END //

-- ---------------------------------------------------------------------
-- 6b. Calculate_TDS(amount, source_id, univ_id, payer, date) -> TDS on ONE entry
--    TDS = tax the PAYING company deducts and deposits with the government
--    for the university; an exempt university claims it back as a refund.
--    Thresholds (Sec 393 IT Act 2025):
--      YEARLY_PER_PAYER  : professional/technical fees, Rs 50,000 per client per year
--      MONTHLY_PER_PAYER : rent, Rs 50,000 per tenant per month
--    Below the threshold -> 0. The entry that CROSSES it -> TDS on the whole
--    total so far (the client deducts the earlier part too). After -> full TDS.
--    Unknown payer -> TDS on everything (can't prove the threshold isn't crossed).
-- ---------------------------------------------------------------------
CREATE FUNCTION Calculate_TDS(p_amount    DECIMAL(15,2), p_source_id INT,
                              p_univ_id   INT,           p_payer     VARCHAR(150),
                              p_date      DATE)
RETURNS DECIMAL(15,2)
READS SQL DATA
BEGIN
    DECLARE v_rule_id   INT;
    DECLARE v_tds_rate  DECIMAL(5,2) DEFAULT 0;
    DECLARE v_threshold DECIMAL(15,2) DEFAULT 0;
    DECLARE v_basis     VARCHAR(20);
    DECLARE v_from      DATE;
    DECLARE v_to        DATE;
    DECLARE v_previous  DECIMAL(15,2) DEFAULT 0;

    SELECT r.TaxRule_ID, r.TDS_Rate, r.TDS_Threshold, r.TDS_Threshold_Basis
      INTO v_rule_id, v_tds_rate, v_threshold, v_basis
    FROM income_source s
    JOIN tax_rule r ON r.TaxRule_ID = s.TaxRule_ID
    WHERE s.Source_ID = p_source_id;

    IF IFNULL(v_tds_rate, 0) = 0 THEN
        RETURN 0;
    END IF;
    IF v_basis = 'NONE' OR v_threshold = 0 OR p_payer IS NULL THEN
        RETURN ROUND(p_amount * v_tds_rate / 100, 2);
    END IF;

    -- the counting window: this financial year, or this month
    IF v_basis = 'YEARLY_PER_PAYER' THEN
        SET v_from = STR_TO_DATE(CONCAT(LEFT(Get_Financial_Year(p_date), 4), '-04-01'), '%Y-%m-%d');
        SET v_to   = DATE_SUB(DATE_ADD(v_from, INTERVAL 1 YEAR), INTERVAL 1 DAY);
    ELSE
        SET v_from = DATE_FORMAT(p_date, '%Y-%m-01');
        SET v_to   = LAST_DAY(p_date);
    END IF;

    -- what this payer already paid under the same rule in that window
    -- (invoices add, credit notes subtract)
    SELECT IFNULL(SUM(IF(t.Entry_Type = 'CREDIT_NOTE', -t.Amount, t.Amount)), 0) INTO v_previous
    FROM revenue_transaction t
    JOIN department d    ON d.Dept_ID   = t.Dept_ID
    JOIN income_source s ON s.Source_ID = t.Source_ID
    WHERE d.Univ_ID = p_univ_id
      AND s.TaxRule_ID = v_rule_id
      AND t.Payer_Name = p_payer
      AND t.Trans_Date BETWEEN v_from AND v_to;

    IF v_previous > v_threshold THEN
        RETURN ROUND(p_amount * v_tds_rate / 100, 2);                  -- already above
    ELSEIF v_previous + p_amount > v_threshold THEN
        RETURN ROUND((v_previous + p_amount) * v_tds_rate / 100, 2);   -- crossing now
    ELSE
        RETURN 0;                                                       -- still below
    END IF;
END //

-- ---------------------------------------------------------------------
-- 7. Get_Due_Date('2025-10-01') -> '2025-11-20'
--    GST for a month is due on the 20th of the NEXT month (GSTR-3B).
-- ---------------------------------------------------------------------
CREATE FUNCTION Get_Due_Date(p_period_start DATE)
RETURNS DATE
DETERMINISTIC
BEGIN
    RETURN DATE_ADD(DATE_ADD(p_period_start, INTERVAL 1 MONTH), INTERVAL 19 DAY);
END //

-- ---------------------------------------------------------------------
-- 8. Get_Financial_Year('2026-02-15') -> '2025-26'
--    Indian financial year: 1 April to 31 March.
-- ---------------------------------------------------------------------
CREATE FUNCTION Get_Financial_Year(p_date DATE)
RETURNS CHAR(7)
DETERMINISTIC
BEGIN
    DECLARE v_start_year INT;
    SET v_start_year = YEAR(p_date) - IF(MONTH(p_date) < 4, 1, 0);
    RETURN CONCAT(v_start_year, '-', LPAD((v_start_year + 1) % 100, 2, '0'));
END //

-- ---------------------------------------------------------------------
-- 9. Calculate_Interest(100000, '2025-11-20', '2025-12-20') -> 1479.45
--    Sec 50 CGST Act: 18% per year, counted per day after the due date.
--    Simple formula for ONE amount over ONE period (used for quick estimates;
--    bills use Calculate_Bill_Interest below, which follows payment dates).
--    interest = outstanding x 18/100 x days_late / 365
-- ---------------------------------------------------------------------
CREATE FUNCTION Calculate_Interest(p_outstanding DECIMAL(15,2),
                                   p_due_date    DATE,
                                   p_as_of       DATE)
RETURNS DECIMAL(15,2)
DETERMINISTIC
BEGIN
    DECLARE v_days INT;
    SET v_days = GREATEST(DATEDIFF(p_as_of, p_due_date), 0);   -- not late -> 0 days
    IF p_outstanding <= 0 THEN
        RETURN 0;
    END IF;
    RETURN ROUND(p_outstanding * 18 / 100 * v_days / 365, 2);
END //

-- ---------------------------------------------------------------------
-- 9b. Calculate_Bill_Interest(tax_id, as_of) -> exact interest on ONE bill
--     Follows the real payment dates, because a part-payment stops
--     interest on that part from the day it is paid.
--     Example: Rs 27,000 due 20 Nov, Rs 13,500 paid 25 Nov, checked 30 Nov
--        20->25 Nov: 27,000 x 18% x 5/365 = 66.58
--        25->30 Nov: 13,500 x 18% x 5/365 = 33.29   -> total 99.86
--     Only VERIFIED payments count. Payments made before the due date
--     just reduce the amount; interest starts only after the due date.
--     Uses a CURSOR: a pointer that walks through query rows one by one.
-- ---------------------------------------------------------------------
CREATE FUNCTION Calculate_Bill_Interest(p_tax_id INT, p_as_of DATE)
RETURNS DECIMAL(15,2)
READS SQL DATA
BEGIN
    DECLARE v_tax_due     DECIMAL(15,2);
    DECLARE v_due_date    DATE;
    DECLARE v_paid        DECIMAL(15,2) DEFAULT 0;   -- paid so far
    DECLARE v_from        DATE;                      -- start of current interest period
    DECLARE v_interest    DECIMAL(20,6) DEFAULT 0;   -- extra decimals, rounded at the end
    DECLARE v_pay_date    DATE;
    DECLARE v_pay_amount  DECIMAL(15,2);
    DECLARE v_done        BOOLEAN DEFAULT FALSE;

    -- the cursor: verified payments of this bill, oldest first
    DECLARE pay_cursor CURSOR FOR
        SELECT Payment_Date, Amount
        FROM payment
        WHERE Tax_ID = p_tax_id
          AND Status = 'Verified'
          AND Payment_For = 'Tax'                    -- interest payments don't reduce the tax
          AND Payment_Date <= p_as_of
        ORDER BY Payment_Date, Payment_ID;

    -- when the cursor runs out of rows, set v_done instead of raising an error
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = TRUE;

    SELECT Tax_Due, Due_Date INTO v_tax_due, v_due_date
    FROM tax_record WHERE Tax_ID = p_tax_id;

    IF v_due_date IS NULL OR p_as_of <= v_due_date THEN
        RETURN 0;                                    -- not late yet
    END IF;

    SET v_from = v_due_date;

    OPEN pay_cursor;
    read_loop: LOOP
        FETCH pay_cursor INTO v_pay_date, v_pay_amount;
        IF v_done THEN
            LEAVE read_loop;
        END IF;

        -- interest on what was unpaid from v_from up to this payment
        IF v_pay_date > v_from THEN
            SET v_interest = v_interest
                + GREATEST(v_tax_due - v_paid, 0) * 18 / 100
                  * DATEDIFF(v_pay_date, v_from) / 365;
            SET v_from = v_pay_date;
        END IF;

        SET v_paid = v_paid + v_pay_amount;
    END LOOP;
    CLOSE pay_cursor;

    -- interest on whatever is still unpaid, up to today
    SET v_interest = v_interest
        + GREATEST(v_tax_due - v_paid, 0) * 18 / 100
          * DATEDIFF(p_as_of, v_from) / 365;

    RETURN ROUND(v_interest, 2);
END //

-- ---------------------------------------------------------------------
-- 9c. Get_Interest_Outstanding(tax_id, as_of) -> interest owed minus interest paid
-- ---------------------------------------------------------------------
CREATE FUNCTION Get_Interest_Outstanding(p_tax_id INT, p_as_of DATE)
RETURNS DECIMAL(15,2)
READS SQL DATA
BEGIN
    DECLARE v_paid DECIMAL(15,2) DEFAULT 0;
    SELECT Interest_Paid INTO v_paid FROM tax_record WHERE Tax_ID = p_tax_id;
    RETURN GREATEST(Calculate_Bill_Interest(p_tax_id, p_as_of) - IFNULL(v_paid, 0), 0);
END //

-- ---------------------------------------------------------------------
-- 10. Get_Outstanding(5) -> GST still unpaid on bill 5
-- ---------------------------------------------------------------------
CREATE FUNCTION Get_Outstanding(p_tax_id INT)
RETURNS DECIMAL(15,2)
READS SQL DATA
BEGIN
    DECLARE v_outstanding DECIMAL(15,2) DEFAULT 0;

    SELECT GREATEST(Tax_Due - Tax_Paid, 0) INTO v_outstanding
    FROM tax_record
    WHERE Tax_ID = p_tax_id;

    RETURN v_outstanding;
END //

-- ---------------------------------------------------------------------
-- 11. Total_GST_Due(1, '2025-26') -> total GST university 1 owes for that year
--     (your old Total_Income_Tax, now reading the monthly bills)
-- ---------------------------------------------------------------------
CREATE FUNCTION Total_GST_Due(p_univ_id INT, p_financial_year CHAR(7))
RETURNS DECIMAL(15,2)
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(15,2);

    SELECT IFNULL(SUM(Tax_Due), 0) INTO v_total
    FROM tax_record
    WHERE Univ_ID = p_univ_id
      AND Financial_Year = p_financial_year;

    RETURN v_total;
END //

-- ---------------------------------------------------------------------
-- 12. Compliance_Status(1, CURDATE()) -> 'OVERDUE' | 'DUE_SOON' | 'COMPLIANT'
--     OVERDUE  : any bill past its due date with tax OR interest unpaid
--     DUE_SOON : any unpaid bill due within the next 7 days
--     COMPLIANT: nothing pending
-- ---------------------------------------------------------------------
CREATE FUNCTION Compliance_Status(p_univ_id INT, p_as_of DATE)
RETURNS VARCHAR(10)
READS SQL DATA
BEGIN
    IF EXISTS (SELECT 1 FROM tax_record
               WHERE Univ_ID = p_univ_id
                 AND Due_Date < p_as_of
                 AND (Tax_Paid < Tax_Due
                      OR Get_Interest_Outstanding(Tax_ID, p_as_of) > 0)) THEN
        RETURN 'OVERDUE';
    END IF;

    IF EXISTS (SELECT 1 FROM tax_record
               WHERE Univ_ID = p_univ_id
                 AND Tax_Paid < Tax_Due
                 AND Due_Date BETWEEN p_as_of AND DATE_ADD(p_as_of, INTERVAL 7 DAY)) THEN
        RETURN 'DUE_SOON';
    END IF;

    RETURN 'COMPLIANT';
END //

DELIMITER ;

-- Quick check (expected values in comments)
SELECT
    Get_Tax_Rate('Consultancy')                          AS rate_18,
    Get_Tax_Rate('Wrong Name')                           AS unknown_null,
    Calculate_Tax_Amount(500000, 'Consultancy')          AS tax_90000,
    Is_Income_Exempt('Tuition & Admission Fees')         AS exempt_1,
    Is_Income_Exempt('Consultancy')                      AS exempt_0,
    Calculate_TDS(200000, 10, NULL, NULL, '2025-10-01')  AS tds_20000,
    Get_Effective_GST_Rate(5, 540000, 10, 180)           AS hostel_exempt_0,
    Get_Effective_GST_Rate(5, 750000, 10, 90)            AS hostel_5,
    Get_Due_Date('2025-10-01')                           AS due_2025_11_20,
    Get_Financial_Year('2026-02-15')                     AS fy_2025_26,
    Calculate_Interest(100000, '2025-11-20', '2025-12-20') AS interest_1479_45;