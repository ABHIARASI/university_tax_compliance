-- =====================================================================
-- University Tax Compliance Portal
-- File: database/02_seed.sql
-- Purpose: the data the app needs on day one:
--          the admin login, the Indian tax rules and the income sources.
--          NO universities here: universities REGISTER themselves in the app
--          and the admin approves them.
-- Run (inside mysql):  SOURCE database/02_seed.sql;
-- =====================================================================

USE university_tax;

-- ---------------------------------------------------------------------
-- Admin (the tax authority). Password is a bcrypt hash (cost 10).
--   admin@taxportal.in / Admin@123   -> change it after the first login
-- ---------------------------------------------------------------------
INSERT INTO users (Name, Email, Password_Hash, Role, Univ_ID) VALUES
('Tax Officer', 'admin@taxportal.in',
 '$2b$10$EpI866QiMUM.mPEhcDZtR.JVX/lStqBcebDX/lKvtreKwWt0do8wi', 'ADMIN', NULL);

-- ---------------------------------------------------------------------
-- Tax rules (India). Each row = how one kind of university income is taxed.
--   GST_Category: EXEMPT       -> a supply, but the law exempts it (0%)
--                 NOT_A_SUPPLY -> nothing is sold in return, so GST doesn't apply
--                 TAXABLE      -> 18% GST
--   TDS_Rate: what the paying company deducts and pays to the government
--             on the university's behalf (the university can claim it back).
-- ---------------------------------------------------------------------
INSERT INTO tax_rule
    (Income_Type, GST_Category, SAC_Code, Tax_Rate, TDS_Rate, Legal_Basis, Conditions)
VALUES
('Tuition & Admission Fees', 'EXEMPT', '9992', 0, 0,
 'GST Notif. 12/2017-CT(Rate), Sl. 66: education by an educational institution to its students',
 'Only for courses that lead to a qualification recognised by law'),

('Examination Fees', 'EXEMPT', '9992', 0, 0,
 'GST Notif. 12/2017-CT(Rate), Sl. 66: services relating to exams conducted by the institution',
 'Exams for its own students'),

('Hostel Fees', 'EXEMPT', '9963', 0, 0,
 'GST Notif. 12/2017-CT(Rate), entry 12AA (from 15 Jul 2024): long-term accommodation',
 'Up to Rs 20,000 per person per month, stay of at least 90 continuous days'),

('Government Grants & Subsidies', 'NOT_A_SUPPLY', NULL, 0, 0,
 'Sec 7 CGST Act: no supply in return; Sec 15(2)(e): govt subsidies excluded from value',
 'UGC / DST / state grant-in-aid with nothing given back to the government'),

('Donations', 'NOT_A_SUPPLY', NULL, 0, 0,
 'Sec 7 CGST Act: a gift with no service in return is not a supply',
 'Donor gets no advertising or other benefit in return'),

('Consultancy', 'TAXABLE', '9983', 18, 10,
 'GST 18% (standard rate); TDS 10% professional fees, Sec 393(1) IT Act 2025 (old 194J)',
 'TDS applies when payments from one client cross Rs 50,000 in a year'),

('Sponsored Research', 'TAXABLE', '9981', 18, 2,
 'GST 18%; TDS 2% technical fees, Sec 393(1) IT Act 2025 (old 194J)',
 'Research done for a company in return for payment'),

('Executive Training', 'TAXABLE', '9992', 18, 0,
 'GST 18%: not covered by the education exemption',
 'Short courses / certificates that do not lead to a recognised degree'),

('Facility Rental', 'TAXABLE', '9972', 18, 10,
 'GST 18%; TDS 10% on rent of land/building, Sec 393(1) IT Act 2025 (old 194-I)',
 'Renting auditoriums, halls, labs to outsiders'),

('Affiliation Fees', 'TAXABLE', '9992', 18, 0,
 'CBIC Circular 234/28/2024-GST treats it as taxable at 18%',
 'Disputed: some High Courts held it is a statutory function, not a supply');

-- ---------------------------------------------------------------------
-- Income sources: the options a university picks when it adds income
-- ---------------------------------------------------------------------
INSERT INTO income_source (Source_Name, TaxRule_ID) VALUES
('Semester Tuition',                 1),
('Admission Fees',                   1),
('End-Semester Exam Fees',           2),
('Supplementary Exam Fees',          2),
('Hostel Fees',                      3),
('UGC Research Grant',               4),
('DST Research Grant',               4),
('State Government Subsidy',         4),
('Alumni Donation',                  5),
('Industry Consultancy',             6),
('Industry Sponsored Research',      7),
('Management Development Programme',8),
('Online Certificate Course',        8),
('Auditorium Rental',                9),
('Lab Equipment Rental',             9),
('College Affiliation Fees',        10);

-- Quick check
SELECT 'admin users' AS item, COUNT(*) AS total FROM users
UNION ALL SELECT 'tax rules',      COUNT(*) FROM tax_rule
UNION ALL SELECT 'income sources', COUNT(*) FROM income_source;