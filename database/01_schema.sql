-- =====================================================================
-- University Tax Compliance Portal
-- File: database/01_schema.sql
-- Purpose: creates the database and all 11 tables (structure only, no data)
--
-- Tax model (India):
--   * Income tax: universities are usually exempt (Sec 10(23C) / 12AB of the
--     IT Act 1961, renumbered in the IT Act 2025), so the portal mainly tracks GST.
--   * GST: core education to students = exempt; grants/subsidies/donations = not
--     a supply; other services = 18%. Tax is split CGST+SGST (same state) or IGST.
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
    State             VARCHAR(50) NOT NULL,          -- decides CGST+SGST vs IGST
    Contact_Person    VARCHAR(100) NOT NULL,
    Phone             VARCHAR(15),
    Email             VARCHAR(120) NOT NULL,
    Status            ENUM('PENDING', 'APPROVED', 'REJECTED', 'SUSPENDED')
                      NOT NULL DEFAULT 'PENDING',
    Rejection_Reason  VARCHAR(255),
    Reviewed_By       INT NULL,                      -- admin who approved/rejected (FK added at the end)
    Reviewed_At       TIMESTAMP NULL,
    Registered_At     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    -- GSTIN format: 2-digit state code + 10-char PAN + entity no. + 'Z' + check char
    -- e.g. 29AABTG4521K1Z3  (29 = Karnataka)
    CHECK (GSTIN REGEXP '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$'),
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
    Legal_Basis   VARCHAR(255) NOT NULL,           -- which law/notification says so
    Conditions    VARCHAR(255),                    -- when the treatment applies
    CHECK (Tax_Rate BETWEEN 0 AND 100),
    CHECK (TDS_Rate BETWEEN 0 AND 100),
    -- an exempt / non-supply income can never carry GST
    CHECK (GST_Category = 'TAXABLE' OR Tax_Rate = 0)
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
    Last_Login     TIMESTAMP NULL,
    Created_At     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (Univ_ID) REFERENCES university(Univ_ID),
    -- a university user must belong to a university; an admin must not
    CHECK ( (Role = 'UNIVERSITY' AND Univ_ID IS NOT NULL)
         OR (Role = 'ADMIN'      AND Univ_ID IS NULL) )
);

-- ---------------------------------------------------------------------
-- 6. revenue_transaction : every income entry (an invoice / receipt)
--    (renamed from `transaction`, because TRANSACTION is a SQL keyword)
-- ---------------------------------------------------------------------
CREATE TABLE revenue_transaction (
    Trans_ID          INT AUTO_INCREMENT PRIMARY KEY,
    Trans_Date        DATE NOT NULL,
    Amount            DECIMAL(15,2) NOT NULL,        -- value BEFORE GST
    Mode              ENUM('Cash', 'Bank Transfer', 'Cheque', 'UPI') NOT NULL,
    Dept_ID           INT NOT NULL,
    Source_ID         INT NOT NULL,
    Payer_Name        VARCHAR(150),                  -- student batch, company, ministry...
    Payer_GSTIN       CHAR(15) NULL,                 -- only for business clients (B2B)
    Place_Of_Supply   VARCHAR(50) NULL,              -- client's state; NULL = same state
    GST_Amount        DECIMAL(15,2) NOT NULL DEFAULT 0,  -- filled by trigger
    TDS_Deducted      DECIMAL(15,2) NOT NULL DEFAULT 0,  -- filled by trigger from TDS_Rate
    Description       VARCHAR(255),
    Created_By        INT NULL,
    Created_At        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CHECK (Amount > 0),
    CHECK (Payer_GSTIN IS NULL OR
           Payer_GSTIN REGEXP '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$'),
    FOREIGN KEY (Dept_ID)    REFERENCES department(Dept_ID),
    FOREIGN KEY (Source_ID)  REFERENCES income_source(Source_ID),
    FOREIGN KEY (Created_By) REFERENCES users(User_ID),
    INDEX idx_trans_date (Trans_Date)              -- dashboards group by month
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
    Due_Date        DATE,                              -- 20th of next month (set by trigger)
    UNIQUE (Univ_ID, Period_Start),                    -- stops duplicate bills
    CHECK (DAY(Period_Start) = 1),
    FOREIGN KEY (Univ_ID) REFERENCES university(Univ_ID)
);

-- ---------------------------------------------------------------------
-- 8. payment : a university pays a monthly bill; admin verifies it
-- ---------------------------------------------------------------------
CREATE TABLE payment (
    Payment_ID    INT AUTO_INCREMENT PRIMARY KEY,
    Tax_ID        INT NOT NULL,
    Amount        DECIMAL(15,2) NOT NULL,
    Payment_Date  DATE NOT NULL,
    Mode          ENUM('Net Banking', 'NEFT/RTGS', 'UPI', 'Card', 'Over the Counter') NOT NULL,
    Reference_No  VARCHAR(50) NOT NULL UNIQUE,         -- CIN of the GST challan; can't be reused
    Status        ENUM('Pending', 'Verified', 'Rejected') NOT NULL DEFAULT 'Pending',
    Verified_By   INT NULL,
    Verified_At   TIMESTAMP NULL,
    Remarks       VARCHAR(255),
    CHECK (Amount > 0),
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
    Rule_Code    ENUM('CASH_LIMIT', 'SPIKE', 'DUPLICATE', 'OVERPAYMENT') NOT NULL,
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
--     every day after, until fully paid  -> OVERDUE (with interest so far)
-- ---------------------------------------------------------------------
CREATE TABLE alert (
    Alert_ID      INT AUTO_INCREMENT PRIMARY KEY,
    Univ_ID       INT NOT NULL,
    Tax_ID        INT NOT NULL,
    Alert_Type    ENUM('DUE_SOON', 'DUE_TODAY', 'OVERDUE') NOT NULL,
    Alert_Date    DATE NOT NULL,                   -- the day this alert is for
    Outstanding   DECIMAL(15,2) NOT NULL,          -- Tax_Due - Tax_Paid on that day
    Interest      DECIMAL(15,2) NOT NULL DEFAULT 0,  -- 18% p.a. interest so far
    Message       VARCHAR(255) NOT NULL,
    Is_Read       BOOLEAN NOT NULL DEFAULT FALSE,
    Email_Sent    BOOLEAN NOT NULL DEFAULT FALSE,
    Created_At    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (Tax_ID, Alert_Date),                   -- at most ONE alert per bill per day
    FOREIGN KEY (Univ_ID) REFERENCES university(Univ_ID),
    FOREIGN KEY (Tax_ID)  REFERENCES tax_record(Tax_ID)
);

-- These foreign keys point "backwards" to tables created later, so they are added last
ALTER TABLE university ADD FOREIGN KEY (Reviewed_By) REFERENCES users(User_ID);
ALTER TABLE notice     ADD FOREIGN KEY (Anomaly_ID)  REFERENCES anomaly(Anomaly_ID);