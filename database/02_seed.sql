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
-- GST state codes (first two digits of a GSTIN)
-- ---------------------------------------------------------------------
INSERT INTO indian_state (State_Code, State_Name) VALUES
('01','Jammu and Kashmir'), ('02','Himachal Pradesh'), ('03','Punjab'), ('04','Chandigarh'),
('05','Uttarakhand'), ('06','Haryana'), ('07','Delhi'), ('08','Rajasthan'),
('09','Uttar Pradesh'), ('10','Bihar'), ('11','Sikkim'), ('12','Arunachal Pradesh'),
('13','Nagaland'), ('14','Manipur'), ('15','Mizoram'), ('16','Tripura'),
('17','Meghalaya'), ('18','Assam'), ('19','West Bengal'), ('20','Jharkhand'),
('21','Odisha'), ('22','Chhattisgarh'), ('23','Madhya Pradesh'), ('24','Gujarat'),
('26','Dadra and Nagar Haveli and Daman and Diu'), ('27','Maharashtra'), ('29','Karnataka'),
('30','Goa'), ('31','Lakshadweep'), ('32','Kerala'), ('33','Tamil Nadu'),
('34','Puducherry'), ('35','Andaman and Nicobar Islands'), ('36','Telangana'),
('37','Andhra Pradesh'), ('38','Ladakh'), ('97','Other Territory');

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
    (Income_Type, GST_Category, SAC_Code, Tax_Rate, TDS_Rate, TDS_Threshold, TDS_Threshold_Basis,
     Special_Rule, Legal_Basis, Conditions)
VALUES
('Tuition & Admission Fees', 'EXEMPT', '9992', 0, 0, 0, 'NONE', 'NONE',
 'GST Notif. 12/2017-CT(Rate), Sl. 66: education by an educational institution to its students',
 'Only for courses that lead to a qualification recognised by law'),

('Examination Fees', 'EXEMPT', '9992', 0, 0, 0, 'NONE', 'NONE',
 'GST Notif. 12/2017-CT(Rate), Sl. 66: services relating to exams conducted by the institution',
 'Exams for its own students'),

('Hostel Fees', 'EXEMPT', '9963', 0, 0, 0, 'NONE', 'ACCOMMODATION',
 'Exempt: Notif. 12/2017-CT(Rate) entry 12AA (from 15 Jul 2024). Otherwise Notif. 15/2025-CT(Rate): 5% / 18%',
 'Exempt up to Rs 20,000 per person per month for 90+ days; else 5% up to Rs 7,500 per person per day, 18% above'),

('Government Grants & Subsidies', 'NOT_A_SUPPLY', NULL, 0, 0, 0, 'NONE', 'NONE',
 'Sec 7 CGST Act: no supply in return; Sec 15(2)(e): govt subsidies excluded from value',
 'UGC / DST / state grant-in-aid with nothing given back to the government'),

('Donations', 'NOT_A_SUPPLY', NULL, 0, 0, 0, 'NONE', 'NONE',
 'Sec 7 CGST Act: a gift with no service in return is not a supply',
 'Donor gets no advertising or other benefit in return'),

('Consultancy', 'TAXABLE', '9983', 18, 10, 50000, 'YEARLY_PER_PAYER', 'NONE',
 'GST 18% (standard rate); TDS 10% professional fees, Sec 393(1) IT Act 2025 (old 194J)',
 'TDS only once one client pays more than Rs 50,000 in a financial year'),

('Sponsored Research', 'TAXABLE', '9981', 18, 2, 50000, 'YEARLY_PER_PAYER', 'NONE',
 'GST 18%; TDS 2% technical fees, Sec 393(1) IT Act 2025 (old 194J)',
 'TDS only once one client pays more than Rs 50,000 in a financial year'),

('Executive Training', 'TAXABLE', '9992', 18, 0, 0, 'NONE', 'NONE',
 'GST 18%: not covered by the education exemption',
 'Short courses / certificates that do not lead to a recognised degree'),

('Facility Rental', 'TAXABLE', '9972', 18, 10, 50000, 'MONTHLY_PER_PAYER', 'NONE',
 'GST 18%; TDS 10% on rent of land/building, Sec 393(1) IT Act 2025 (old 194-I)',
 'TDS only once one tenant pays more than Rs 50,000 in a month'),

('Affiliation Fees', 'TAXABLE', '9992', 18, 0, 0, 'NONE', 'NONE',
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
SELECT 'states' AS item, COUNT(*) AS total FROM indian_state
UNION ALL SELECT 'admin users', COUNT(*) FROM users
UNION ALL SELECT 'tax rules',      COUNT(*) FROM tax_rule
UNION ALL SELECT 'income sources', COUNT(*) FROM income_source;