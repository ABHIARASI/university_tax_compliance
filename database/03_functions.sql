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

DROP FUNCTION IF EXISTS Get_Tax_Rate;
DROP FUNCTION IF EXISTS Get_Source_Tax_Rate;
DROP FUNCTION IF EXISTS Calculate_Tax_Amount;
DROP FUNCTION IF EXISTS Is_Income_Exempt;
DROP FUNCTION IF EXISTS Is_Inter_State;
DROP FUNCTION IF EXISTS Calculate_TDS;
DROP FUNCTION IF EXISTS Get_Due_Date;
DROP FUNCTION IF EXISTS Get_Financial_Year;
DROP FUNCTION IF EXISTS Calculate_Interest;
DROP FUNCTION IF EXISTS Calculate_Bill_Interest;
DROP FUNCTION IF EXISTS Get_Outstanding;
DROP FUNCTION IF EXISTS Total_GST_Due;
DROP FUNCTION IF EXISTS Compliance_Status;

DELIMITER //

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
-- 6. Calculate_TDS(200000, 10) -> 20000.00   (10% on consultancy)
--    TDS = tax the PAYING company deducts and deposits with the
--    government for the university; an exempt university claims it back.
--    (Simplified: the Rs 50,000-per-client yearly threshold is not checked.)
-- ---------------------------------------------------------------------
CREATE FUNCTION Calculate_TDS(p_amount DECIMAL(15,2), p_source_id INT)
RETURNS DECIMAL(15,2)
READS SQL DATA
BEGIN
    DECLARE v_tds_rate DECIMAL(5,2) DEFAULT 0;

    SELECT r.TDS_Rate INTO v_tds_rate
    FROM income_source s
    JOIN tax_rule r ON r.TaxRule_ID = s.TaxRule_ID
    WHERE s.Source_ID = p_source_id;

    RETURN ROUND(p_amount * IFNULL(v_tds_rate, 0) / 100, 2);
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
--     OVERDUE  : any bill past its due date and not fully paid
--     DUE_SOON : any unpaid bill due within the next 7 days
--     COMPLIANT: nothing pending
-- ---------------------------------------------------------------------
CREATE FUNCTION Compliance_Status(p_univ_id INT, p_as_of DATE)
RETURNS VARCHAR(10)
READS SQL DATA
BEGIN
    IF EXISTS (SELECT 1 FROM tax_record
               WHERE Univ_ID = p_univ_id
                 AND Tax_Paid < Tax_Due
                 AND Due_Date < p_as_of) THEN
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
    Calculate_TDS(200000, 10)                            AS tds_20000,
    Get_Due_Date('2025-10-01')                           AS due_2025_11_20,
    Get_Financial_Year('2026-02-15')                     AS fy_2025_26,
    Calculate_Interest(100000, '2025-11-20', '2025-12-20') AS interest_1479_45;