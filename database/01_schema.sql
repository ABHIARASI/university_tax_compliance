-- =====================================================================
-- University Tax Compliance Portal
-- File: database/01_schema.sql
-- Purpose: creates the database and all 14 tables (structure only, no data)
--
-- Tax model (India):
--   * Income tax: universities are usually exempt (Sec 10(23C) / 12AB of the
--     IT Act 1961, renumbered in the IT Act 2025), so the portal mainly tracks GST.
--   * GST: core education to students = exempt; grants/subsidies/donations = not
--     a supply; other services = 18%. Tax is split CGST+SGST (same state) or IGST.
--   * Hostel: exempt up to Rs 20,000 per person per month for 90+ days; otherwise
--     accommodation GST: 5% up to Rs 7,500 per person per day, 18% above.
--   * Corrections are made with CREDIT NOTES, never by editing an entry.
--   * GST is paid monthly; due on the 20th of the next month (GSTR-3B).
--   * Late payment: interest 18% per year, per day (Sec 50, CGST Act).
--   * TDS: companies paying for consultancy/research deduct TDS (Sec 393,
--     IT Act 2025; earlier 194J). An exempt university can claim it back.
--   * Cash receipt of Rs 2 lakh or more is not allowed
--     (Sec 186, IT Act 2025; earlier Sec 269ST).
-- Run (inside mysql):  SOURCE database/01_schema.sql;
-- =====================================================================

DROP DATABASE IF EXISTS university_tax;
CREATE DATABASE university_tax;
USE university_tax;

-- ---------------------------------------------------------------------
-- 0. indian_state : official GST state codes (first 2 digits of every GSTIN)
--    Used to check that a GSTIN's code matches its state, and as the list of
--    valid states for university address and place of supply.
-- ---------------------------------------------------------------------
CREATE TABLE indian_state (
    State_Code  CHAR(2) PRIMARY KEY,
    State_Name  VARCHAR(60) NOT NULL UNIQUE
);

-- ---------------------------------------------------------------------
-- 1. university : created when a university REGISTERS (status PENDING);
--    an admin must APPROVE it before its users can log in.
-- ---------------------------------------------------------------------
CREATE TABLE university (
    Univ_ID           INT AUTO_INCREMENT PRIMARY KEY,
    Name              VARCHAR(150) NOT NULL UNIQUE,
    GSTIN             CHAR(15) NOT NULL UNIQUE,      -- GST registration number
    PAN               CHAR(10) GENERATED ALWAYS AS (SUBSTRING(GSTIN, 3, 10)) STORED,
    Institution_Type  ENUM('Central', 'State', 'Deemed', 'Private') NOT NULL,
    IT_Exemption      ENUM('10(23C)(iiiab) - Govt funded',
                           '10(23C)(iiiad) - Receipts up to 5 crore',
                           '10(23C)(vi) - Approved institution',
                           '12AB - Registered trust',
                           'None') NOT NULL DEFAULT 'None',
    Address           VARCHAR(255),
    City              VARCHAR(80),
    State             VARCHAR(60) NOT NULL,          -- decides CGST+SGST vs IGST
    Contact_Person    VARCHAR(100) NOT NULL,
    Phone             VARCHAR(15),
    Email             VARCHAR(120) NOT NULL,
    Status            ENUM('PENDING', 'APPROVED', 'REJECTED', 'SUSPENDED')
                      NOT NULL DEFAULT 'PENDING',
    Status_Reason     VARCHAR(255),                  -- why it was rejected / suspended
    Reviewed_By       INT NULL,                      -- admin who approved/rejected (FK added at the end)
    Reviewed_At       TIMESTAMP NULL,
    Registered_At     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    -- GSTIN format: 2-digit state code + 10-char PAN + entity no. + 'Z' + check char
    -- e.g. 29AABTG4521K1Z3  (29 = Karnataka)
    CONSTRAINT chk_gstin_format CHECK (GSTIN REGEXP '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$'),
    -- the check digit and the state code are verified by a trigger (file 05)
    FOREIGN KEY (State) REFERENCES indian_state(State_Name),
    INDEX idx_univ_status (Status)
);

-- ---------------------------------------------------------------------
-- 2. department : departments inside a university (who earns the money)
-- ---------------------------------------------------------------------
CREATE TABLE department (
    Dept_ID  INT AUTO_INCREMENT PRIMARY KEY,
    Name     VARCHAR(100) NOT NULL,
    Univ_ID  INT NOT NULL,
    UNIQUE (Univ_ID, Name),                        -- no two "Finance" depts in one university
    FOREIGN KEY (Univ_ID) REFERENCES university(Univ_ID) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------
-- 3. tax_rule : the ONLY place an income type and its tax treatment live
-- ---------------------------------------------------------------------
CREATE TABLE tax_rule (
    TaxRule_ID    INT AUTO_INCREMENT PRIMARY KEY,
    Income_Type   VARCHAR(60) NOT NULL UNIQUE,
    GST_Category  ENUM('EXEMPT', 'NOT_A_SUPPLY', 'TAXABLE') NOT NULL,
    SAC_Code      VARCHAR(8),                      -- GST service code, e.g. 9992 = education
    Tax_Rate      DECIMAL(5,2) NOT NULL,           -- GST percent (0 or 18)
    TDS_Rate      DECIMAL(5,2) NOT NULL DEFAULT 0, -- % the paying client deducts as TDS
    TDS_Threshold DECIMAL(15,2) NOT NULL DEFAULT 0,-- no TDS until payments cross this
    TDS_Threshold_Basis ENUM('NONE', 'YEARLY_PER_PAYER', 'MONTHLY_PER_PAYER')
                  NOT NULL DEFAULT 'NONE',         -- how the threshold is counted
    Special_Rule  ENUM('NONE', 'ACCOMMODATION') NOT NULL DEFAULT 'NONE',
                                                   -- ACCOMMODATION = hostel test (see header)
    Legal_Basis   VARCHAR(255) NOT NULL,           -- which law/notification says so
    Conditions    VARCHAR(255),                    -- when the treatment applies
    Updated_At    TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT chk_tax_rate_range CHECK (Tax_Rate BETWEEN 0 AND 100),
    CONSTRAINT chk_tds_rate_range CHECK (TDS_Rate BETWEEN 0 AND 100),
    -- an exempt / non-supply income can never carry GST
    CONSTRAINT chk_exempt_no_gst CHECK (GST_Category = 'TAXABLE' OR Tax_Rate = 0)
);

-- ---------------------------------------------------------------------
-- 4. income_source : a specific source of money, mapped to one tax rule
--    e.g. 'Semester Tuition' and 'Admission Fees' both use 'Tuition & Admission Fees'
-- ---------------------------------------------------------------------
CREATE TABLE income_source (
    Source_ID    INT AUTO_INCREMENT PRIMARY KEY,
    Source_Name  VARCHAR(100) NOT NULL UNIQUE,
    TaxRule_ID   INT NOT NULL,
    FOREIGN KEY (TaxRule_ID) REFERENCES tax_rule(TaxRule_ID)
);

-- ---------------------------------------------------------------------
-- 5. users : login accounts. ADMIN = tax authority, UNIVERSITY = a university's staff
--    A UNIVERSITY user is created together with the university at registration.
-- ---------------------------------------------------------------------
CREATE TABLE users (
    User_ID        INT AUTO_INCREMENT PRIMARY KEY,
    Name           VARCHAR(100) NOT NULL,
    Email          VARCHAR(120) NOT NULL UNIQUE,
    Password_Hash  VARCHAR(255) NOT NULL,          -- bcrypt hash, never the real password
    Role           ENUM('ADMIN', 'UNIVERSITY') NOT NULL,
    Univ_ID        INT NULL,                       -- filled only for UNIVERSITY users
    Token_Version  INT NOT NULL DEFAULT 0,         -- +1 on password change = old logins stop working
    Last_Login     TIMESTAMP NULL,
    Created_At     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (Univ_ID) REFERENCES university(Univ_ID),
    -- a university user must belong to a university; an admin must not
    CONSTRAINT chk_user_role_univ CHECK ( (Role = 'UNIVERSITY' AND Univ_ID IS NOT NULL)
                                       OR (Role = 'ADMIN'      AND Univ_ID IS NULL) )
);

-- ---------------------------------------------------------------------
-- 6. revenue_transaction : every income entry (an invoice / receipt)
--    (renamed from `transaction`, because TRANSACTION is a SQL keyword)
--    Entries are never edited or deleted (triggers block it). A mistake is
--    corrected with a CREDIT_NOTE that points to the original entry.
-- ---------------------------------------------------------------------
CREATE TABLE revenue_transaction (
    Trans_ID          INT AUTO_INCREMENT PRIMARY KEY,
    Entry_Type        ENUM('INVOICE', 'CREDIT_NOTE') NOT NULL DEFAULT 'INVOICE',
    Original_Trans_ID INT NULL,                      -- for a CREDIT_NOTE: the entry it reverses
    Trans_Date        DATE NOT NULL,
    Amount            DECIMAL(15,2) NOT NULL,        -- value BEFORE GST (always positive)
    Mode              ENUM('Cash', 'Bank Transfer', 'Cheque', 'UPI') NOT NULL,
    Dept_ID           INT NOT NULL,
    Source_ID         INT NOT NULL,
    Reference_No      VARCHAR(50),                   -- invoice / event number (cash rule uses it)
    Payer_Name        VARCHAR(150),                  -- student batch, company, ministry...
    Payer_GSTIN       CHAR(15) NULL,                 -- only for business clients (B2B)
    Place_Of_Supply   VARCHAR(60) NULL,              -- client's state; NULL = same state
    Beneficiaries     INT NULL,                      -- hostel: number of students
    Stay_Days         INT NULL,                      -- hostel: days covered by this fee
    GST_Rate          DECIMAL(5,2) NOT NULL DEFAULT 0,   -- rate on the day of the entry (snapshot)
    GST_Amount        DECIMAL(15,2) NOT NULL DEFAULT 0,  -- filled by trigger
    TDS_Expected      DECIMAL(15,2) NOT NULL DEFAULT 0,  -- what the law says (filled by trigger)
    TDS_Deducted      DECIMAL(15,2) NULL,                -- type the real figure, or leave empty
    TDS_Source        ENUM('ENTERED', 'CALCULATED') NOT NULL DEFAULT 'CALCULATED',
    Description       VARCHAR(255),
    Created_By        INT NULL,
    Created_At        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_trans_amount CHECK (Amount > 0),
    CONSTRAINT chk_beneficiaries CHECK (Beneficiaries IS NULL OR Beneficiaries > 0),
    CONSTRAINT chk_stay_days CHECK (Stay_Days IS NULL OR Stay_Days > 0),
    CONSTRAINT chk_tds_not_negative CHECK (TDS_Deducted IS NULL OR TDS_Deducted >= 0),
    CONSTRAINT chk_credit_note_link CHECK ((Entry_Type = 'INVOICE' AND Original_Trans_ID IS NULL)
        OR (Entry_Type = 'CREDIT_NOTE' AND Original_Trans_ID IS NOT NULL)),
    CONSTRAINT chk_payer_gstin CHECK (Payer_GSTIN IS NULL OR
           Payer_GSTIN REGEXP '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$'),
    FOREIGN KEY (Original_Trans_ID) REFERENCES revenue_transaction(Trans_ID),
    FOREIGN KEY (Place_Of_Supply) REFERENCES indian_state(State_Name),
    FOREIGN KEY (Dept_ID)    REFERENCES department(Dept_ID),
    FOREIGN KEY (Source_ID)  REFERENCES income_source(Source_ID),
    FOREIGN KEY (Created_By) REFERENCES users(User_ID),
    INDEX idx_trans_date (Trans_Date),                  -- dashboards group by month
    INDEX idx_payer_date (Payer_Name, Trans_Date)       -- cash-limit and TDS look-ups
);

-- ---------------------------------------------------------------------
-- 7. tax_record : ONE GST bill per university per MONTH (a "tax period")
--    Filled automatically by a trigger whenever a transaction is inserted.
-- ---------------------------------------------------------------------
CREATE TABLE tax_record (
    Tax_ID          INT AUTO_INCREMENT PRIMARY KEY,
    Univ_ID         INT NOT NULL,
    Period_Start    DATE NOT NULL,                     -- always the 1st, e.g. 2025-10-01 = Oct 2025
    -- Indian financial year runs April to March: Oct 2025 -> '2025-26', Feb 2026 -> '2025-26'
    Financial_Year  CHAR(7) GENERATED ALWAYS AS (
                        CONCAT(YEAR(Period_Start) - IF(MONTH(Period_Start) < 4, 1, 0), '-',
                               LPAD((YEAR(Period_Start) - IF(MONTH(Period_Start) < 4, 1, 0) + 1) % 100, 2, '0'))
                    ) STORED,
    Total_Income    DECIMAL(15,2) NOT NULL DEFAULT 0,  -- all income in the month
    Taxable_Income  DECIMAL(15,2) NOT NULL DEFAULT 0,  -- only income with GST > 0%
    CGST            DECIMAL(15,2) NOT NULL DEFAULT 0,  -- central half (same-state sales)
    SGST            DECIMAL(15,2) NOT NULL DEFAULT 0,  -- state half   (same-state sales)
    IGST            DECIMAL(15,2) NOT NULL DEFAULT 0,  -- integrated   (other-state sales)
    Tax_Due         DECIMAL(15,2) NOT NULL DEFAULT 0,  -- CGST + SGST + IGST
    Tax_Paid        DECIMAL(15,2) NOT NULL DEFAULT 0,  -- GST actually paid (admin-verified)
    Interest_Paid   DECIMAL(15,2) NOT NULL DEFAULT 0,  -- late-payment interest paid (verified)
    Due_Date        DATE,                              -- 20th of next month (set by trigger);
                                                       -- admin can extend it (govt extensions)
    UNIQUE (Univ_ID, Period_Start),                    -- stops duplicate bills
    CONSTRAINT chk_period_first_day CHECK (DAY(Period_Start) = 1),
    FOREIGN KEY (Univ_ID) REFERENCES university(Univ_ID)
);

-- ---------------------------------------------------------------------
-- 8. payment : a university pays a monthly bill (tax or interest); admin verifies it
-- ---------------------------------------------------------------------
CREATE TABLE payment (
    Payment_ID    INT AUTO_INCREMENT PRIMARY KEY,
    Tax_ID        INT NOT NULL,
    Payment_For   ENUM('Tax', 'Interest') NOT NULL DEFAULT 'Tax',  -- separate heads, like a GST challan
    Amount        DECIMAL(15,2) NOT NULL,
    Payment_Date  DATE NOT NULL,
    Mode          ENUM('Net Banking', 'NEFT/RTGS', 'UPI', 'Card', 'Over the Counter') NOT NULL,
    Reference_No  VARCHAR(50) NOT NULL UNIQUE,         -- CIN of the GST challan; can't be reused
    Status        ENUM('Pending', 'Verified', 'Rejected') NOT NULL DEFAULT 'Pending',
    Verified_By   INT NULL,
    Verified_At   TIMESTAMP NULL,
    Remarks       VARCHAR(255),
    CONSTRAINT chk_payment_amount CHECK (Amount > 0),
    FOREIGN KEY (Tax_ID)      REFERENCES tax_record(Tax_ID),
    FOREIGN KEY (Verified_By) REFERENCES users(User_ID)
);

-- ---------------------------------------------------------------------
-- 9. notice : admin sends a notice to a university; university replies
-- ---------------------------------------------------------------------
CREATE TABLE notice (
    Notice_ID     INT AUTO_INCREMENT PRIMARY KEY,
    Univ_ID       INT NOT NULL,
    Tax_ID        INT NULL,                        -- optional: which month's bill it is about
    Anomaly_ID    INT NULL,                        -- optional: which anomaly it is about
    Type          ENUM('Reminder', 'Demand', 'Anomaly Query', 'General') NOT NULL,
    Subject       VARCHAR(150) NOT NULL,
    Message       TEXT NOT NULL,
    Issued_By     INT NOT NULL,
    Issued_At     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    Response_Due  DATE,
    Status        ENUM('Open', 'Responded', 'Closed') NOT NULL DEFAULT 'Open',
    Response      TEXT NULL,
    Responded_At  TIMESTAMP NULL,
    FOREIGN KEY (Univ_ID)   REFERENCES university(Univ_ID),
    FOREIGN KEY (Tax_ID)    REFERENCES tax_record(Tax_ID),
    FOREIGN KEY (Issued_By) REFERENCES users(User_ID)
);

-- ---------------------------------------------------------------------
-- 10. anomaly : suspicious things the system flags for the admin to review
-- ---------------------------------------------------------------------
CREATE TABLE anomaly (
    Anomaly_ID   INT AUTO_INCREMENT PRIMARY KEY,
    Univ_ID      INT NOT NULL,
    Trans_ID     INT NULL,                         -- set for transaction-based rules
    Payment_ID   INT NULL,                         -- set for payment-based rules
    Rule_Code    ENUM('CASH_LIMIT', 'SPIKE', 'DUPLICATE', 'OVERPAYMENT', 'TDS_MISMATCH') NOT NULL,
    Severity     ENUM('Low', 'Medium', 'High') NOT NULL,
    Details      VARCHAR(255) NOT NULL,
    Status       ENUM('Open', 'Reviewed', 'Dismissed') NOT NULL DEFAULT 'Open',
    Detected_At  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    Reviewed_By  INT NULL,
    FOREIGN KEY (Univ_ID)     REFERENCES university(Univ_ID),
    FOREIGN KEY (Trans_ID)    REFERENCES revenue_transaction(Trans_ID),
    FOREIGN KEY (Payment_ID)  REFERENCES payment(Payment_ID),
    FOREIGN KEY (Reviewed_By) REFERENCES users(User_ID)
);

-- ---------------------------------------------------------------------
-- 11. alert : AUTOMATIC reminders created every day by a scheduled job
--     7, 3 and 1 day before the due date -> DUE_SOON
--     on the due date                    -> DUE_TODAY
--     every day after, until tax is paid -> OVERDUE (with interest so far)
--     tax paid but interest still unpaid -> INTEREST_DUE, every day until paid
-- ---------------------------------------------------------------------
CREATE TABLE alert (
    Alert_ID      INT AUTO_INCREMENT PRIMARY KEY,
    Univ_ID       INT NOT NULL,
    Tax_ID        INT NOT NULL,
    Alert_Type    ENUM('DUE_SOON', 'DUE_TODAY', 'OVERDUE', 'INTEREST_DUE') NOT NULL,
    Alert_Date    DATE NOT NULL,                   -- the day this alert is for
    Outstanding   DECIMAL(15,2) NOT NULL,          -- GST still unpaid on that day
    Interest      DECIMAL(15,2) NOT NULL DEFAULT 0,  -- interest still unpaid on that day
    Message       VARCHAR(255) NOT NULL,
    Is_Read       BOOLEAN NOT NULL DEFAULT FALSE,
    Email_Sent    BOOLEAN NOT NULL DEFAULT FALSE,
    Created_At    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (Tax_ID, Alert_Date),                   -- at most ONE alert per bill per day
    FOREIGN KEY (Univ_ID) REFERENCES university(Univ_ID),
    FOREIGN KEY (Tax_ID)  REFERENCES tax_record(Tax_ID)
);

-- ---------------------------------------------------------------------
-- 12. tax_rule_audit : history of every change to a tax rate (filled by trigger)
--     Who changed what, when. Old entries keep their own GST_Rate snapshot,
--     so a rate change only affects NEW income - exactly like real GST.
-- ---------------------------------------------------------------------
CREATE TABLE tax_rule_audit (
    Audit_ID      INT AUTO_INCREMENT PRIMARY KEY,
    TaxRule_ID    INT NOT NULL,
    Old_Tax_Rate  DECIMAL(5,2),
    New_Tax_Rate  DECIMAL(5,2),
    Old_TDS_Rate  DECIMAL(5,2),
    New_TDS_Rate  DECIMAL(5,2),
    Changed_By    INT NULL,                        -- taken from @app_user_id set by the backend
    Changed_At    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (TaxRule_ID) REFERENCES tax_rule(TaxRule_ID),
    FOREIGN KEY (Changed_By) REFERENCES users(User_ID)
);

-- ---------------------------------------------------------------------
-- 13. password_reset : one-time "forgot password" tokens
--     Only a HASH of the token is stored (like a password), so a database
--     leak can't be used to reset anyone's password. Valid 30 minutes, once.
-- ---------------------------------------------------------------------
CREATE TABLE password_reset (
    Reset_ID     INT AUTO_INCREMENT PRIMARY KEY,
    User_ID      INT NOT NULL,
    Token_Hash   CHAR(64) NOT NULL UNIQUE,         -- SHA-256 of the token, in hex
    Expires_At   DATETIME NOT NULL,
    Used_At      DATETIME NULL,
    Created_At   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (User_ID) REFERENCES users(User_ID) ON DELETE CASCADE
);

-- These foreign keys point "backwards" to tables created later, so they are added last
ALTER TABLE university ADD FOREIGN KEY (Reviewed_By) REFERENCES users(User_ID);
ALTER TABLE notice     ADD FOREIGN KEY (Anomaly_ID)  REFERENCES anomaly(Anomaly_ID);
