-- =====================================================================
-- University Tax Compliance Portal
-- File: database/06_demo_data.sql
-- Purpose: realistic DEMO data so dashboards and charts have something to show.
--          Run it AFTER files 01-05 (the triggers must exist, so every income
--          entry creates its GST bill and anomalies automatically).
--
--   Greenfield University (Karnataka)  - mostly pays on time; one late month
--                                        (interest paid); latest month overdue
--   Riverside University  (Maharashtra)- stopped paying from Jul 2026 -> OVERDUE
--   Hillcrest University  (Tamil Nadu) - always on time -> COMPLIANT
--   Northstar, Lakeview                - registered, waiting for admin approval
--
--   OPTIONAL. Sample universities for a local demo only - skip this file
--   for a real setup (real universities register in the app themselves).
--   Demo logins:
--     admin@taxportal.in        / Admin@123   (from 02_seed.sql)
--     finance@greenfield.edu.in / Univ@123
--     finance@riverside.edu.in  / Univ@123
--     finance@hillcrest.edu.in  / Univ@123
--   Real universities register through the app with their own passwords.
--
-- Run (inside mysql):  SOURCE database/06_demo_data.sql;
-- =====================================================================

USE university_tax;

-- the admin from 02_seed.sql does the approvals and verifications below
SET @admin = (SELECT User_ID FROM users WHERE Email = 'admin@taxportal.in');

-- ---------------------------------------------------------------------
-- 1. Universities register (status PENDING)
-- ---------------------------------------------------------------------
INSERT INTO university (Name, GSTIN, Institution_Type, IT_Exemption, Address, City, State,
                        Contact_Person, Phone, Email, Registered_At) VALUES
('Greenfield University', '29AABTG4521K1ZL', 'Private', '10(23C)(vi) - Approved institution',
 'Kanakapura Road', 'Bengaluru', 'Karnataka', 'Anita Rao', '9845012345',
 'accounts@greenfield.edu.in', '2025-03-10 10:00:00'),
('Riverside University', '27AACTR7812M1Z1', 'Deemed', '12AB - Registered trust',
 'Karve Road', 'Pune', 'Maharashtra', 'Suresh Patil', '9822012345',
 'accounts@riverside.edu.in', '2025-03-12 11:30:00'),
('Hillcrest University', '33AADTH3390P1ZA', 'State', '10(23C)(iiiab) - Govt funded',
 'Anna Salai', 'Chennai', 'Tamil Nadu', 'Lakshmi Narayanan', '9840012345',
 'accounts@hillcrest.edu.in', '2025-03-15 09:15:00'),
('Northstar Institute of Technology', '36AAFTN5520C1ZV', 'Private', '12AB - Registered trust',
 'Gachibowli', 'Hyderabad', 'Telangana', 'Ravi Teja', '9849012345',
 'accounts@northstar.edu.in', NOW() - INTERVAL 2 DAY),
('Lakeview University', '32AABTL8871D1ZN', 'Private', 'None',
 'MG Road', 'Kochi', 'Kerala', 'Mary Thomas', '9847012345',
 'accounts@lakeview.edu.in', NOW() - INTERVAL 1 DAY);

-- each registration also creates that university's login (same bcrypt hash = Univ@123)
INSERT INTO users (Name, Email, Password_Hash, Role, Univ_ID)
SELECT CONCAT(Contact_Person, ' (', Name, ')'),
       CONCAT('finance@', SUBSTRING_INDEX(Email, '@', -1)),
       '$2b$10$qTalJ5/zu8ZREep7M2gh2eYhVMqeXiy84iIm3gbjUr2udzRFjUn..',
       'UNIVERSITY', Univ_ID
FROM university;

-- ---------------------------------------------------------------------
-- 2. Admin approves the first three (creates Administration + Accounts)
-- ---------------------------------------------------------------------
CALL Approve_University(1, @admin);
CALL Approve_University(2, @admin);
CALL Approve_University(3, @admin);
UPDATE university SET Reviewed_At = '2025-03-20 12:00:00' WHERE Univ_ID IN (1, 2, 3);

-- ---------------------------------------------------------------------
-- 3. Each approved university adds its other departments
-- ---------------------------------------------------------------------
INSERT INTO department (Name, Univ_ID)
SELECT d.Name, u.Univ_ID
FROM university u
CROSS JOIN (SELECT 'Engineering' AS Name UNION ALL SELECT 'Management'
            UNION ALL SELECT 'Research Centre' UNION ALL SELECT 'Hostel Office') AS d
WHERE u.Status = 'APPROVED';

-- handy variables: @g_eng = Greenfield's Engineering department id, etc.
SET @g_user = (SELECT User_ID FROM users WHERE Univ_ID = 1);
SET @r_user = (SELECT User_ID FROM users WHERE Univ_ID = 2);
SET @h_user = (SELECT User_ID FROM users WHERE Univ_ID = 3);
SET @g_admin  = (SELECT Dept_ID FROM department WHERE Univ_ID = 1 AND Name = 'Administration');
SET @g_acc    = (SELECT Dept_ID FROM department WHERE Univ_ID = 1 AND Name = 'Accounts');
SET @g_eng    = (SELECT Dept_ID FROM department WHERE Univ_ID = 1 AND Name = 'Engineering');
SET @g_mgmt   = (SELECT Dept_ID FROM department WHERE Univ_ID = 1 AND Name = 'Management');
SET @g_res    = (SELECT Dept_ID FROM department WHERE Univ_ID = 1 AND Name = 'Research Centre');
SET @g_hostel = (SELECT Dept_ID FROM department WHERE Univ_ID = 1 AND Name = 'Hostel Office');
SET @r_admin  = (SELECT Dept_ID FROM department WHERE Univ_ID = 2 AND Name = 'Administration');
SET @r_acc    = (SELECT Dept_ID FROM department WHERE Univ_ID = 2 AND Name = 'Accounts');
SET @r_eng    = (SELECT Dept_ID FROM department WHERE Univ_ID = 2 AND Name = 'Engineering');
SET @r_mgmt   = (SELECT Dept_ID FROM department WHERE Univ_ID = 2 AND Name = 'Management');
SET @r_res    = (SELECT Dept_ID FROM department WHERE Univ_ID = 2 AND Name = 'Research Centre');
SET @r_hostel = (SELECT Dept_ID FROM department WHERE Univ_ID = 2 AND Name = 'Hostel Office');
SET @h_admin  = (SELECT Dept_ID FROM department WHERE Univ_ID = 3 AND Name = 'Administration');
SET @h_acc    = (SELECT Dept_ID FROM department WHERE Univ_ID = 3 AND Name = 'Accounts');
SET @h_eng    = (SELECT Dept_ID FROM department WHERE Univ_ID = 3 AND Name = 'Engineering');
SET @h_mgmt   = (SELECT Dept_ID FROM department WHERE Univ_ID = 3 AND Name = 'Management');
SET @h_res    = (SELECT Dept_ID FROM department WHERE Univ_ID = 3 AND Name = 'Research Centre');
SET @h_hostel = (SELECT Dept_ID FROM department WHERE Univ_ID = 3 AND Name = 'Hostel Office');

-- ---------------------------------------------------------------------
-- 4. Income, April 2025 to November 2026 (the triggers calculate GST, TDS,
--    monthly bills and anomalies for every row)
--    Source IDs: 1 Semester Tuition, 2 Admission, 3 Exam, 5 Hostel,
--    6 UGC grant, 7 DST grant, 8 Subsidy, 9 Donation, 10 Consultancy,
--    11 Sponsored Research, 12 MDP, 13 Online Course, 14 Auditorium,
--    15 Lab Rental, 16 Affiliation
-- ---------------------------------------------------------------------
INSERT INTO revenue_transaction
    (Trans_Date, Amount, Mode, Dept_ID, Source_ID, Payer_Name, Payer_GSTIN, Place_Of_Supply,
     Reference_No, Beneficiaries, Stay_Days, TDS_Deducted, Description, Created_By)
VALUES
('2025-04-03', 37000, 'UPI', @h_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-04-04', 55000, 'Bank Transfer', @h_eng, 10, 'Coromandel Systems Ltd', '33AAJCS2290M1Z1', NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-04-04', 44000, 'UPI', @r_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-04-06', 150000, 'UPI', @h_mgmt, 12, 'MDP participants (corporate)', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-04-09', 55000, 'Bank Transfer', @g_eng, 10, 'Coromandel Systems Ltd', '33AAJCS2290M1Z1', 'Tamil Nadu', NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-04-09', 55000, 'Bank Transfer', @h_eng, 10, 'Coromandel Systems Ltd', '33AAJCS2290M1Z1', NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-04-09', 215000, 'UPI', @r_mgmt, 12, 'MDP participants (corporate)', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-04-10', 75000, 'Bank Transfer', @r_eng, 10, 'Orbit Motors Ltd', '27AAGCO7731P1ZR', NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-04-12', 3835000, 'Bank Transfer', @h_res, 6, 'UGC - research grant', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-04-13', 2500000, 'Bank Transfer', @g_res, 6, 'UGC - research grant', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-04-19', 32000, 'UPI', @g_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-04-23', 205000, 'UPI', @g_mgmt, 12, 'MDP participants (corporate)', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-04-24', 2160000, 'Bank Transfer', @r_res, 6, 'UGC - research grant', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-04-25', 45000, 'Bank Transfer', @g_eng, 10, 'Orbit Motors Ltd', '27AAGCO7731P1ZR', 'Maharashtra', NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-05-04', 55000, 'Bank Transfer', @g_eng, 10, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-05-04', 55000, 'Bank Transfer', @r_eng, 10, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', 'Karnataka', NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-05-09', 50000, 'Bank Transfer', @h_eng, 15, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-05-12', 1287000, 'UPI', @h_acc, 3, 'Exam fees - all students', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-05-13', 664000, 'UPI', @r_acc, 3, 'Exam fees - all students', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-05-14', 930000, 'UPI', @g_acc, 3, 'Exam fees - all students', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-05-14', 40000, 'Bank Transfer', @r_eng, 15, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-05-15', 90000, 'Bank Transfer', @h_eng, 10, 'Dhruva Pharma Ltd', '24AAHCD6614R1Z7', 'Gujarat', NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-05-15', 350000, 'Bank Transfer', @r_res, 11, 'Orbit Motors Ltd', '27AAGCO7731P1ZR', NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-05-17', 42000, 'UPI', @h_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-05-17', 36000, 'UPI', @r_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-05-18', 200000, 'Bank Transfer', @g_res, 11, 'Orbit Motors Ltd', '27AAGCO7731P1ZR', 'Maharashtra', NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-05-19', 36000, 'UPI', @g_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-05-24', 80000, 'Bank Transfer', @g_eng, 15, 'Coromandel Systems Ltd', '33AAJCS2290M1Z1', NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-05-24', 320000, 'Bank Transfer', @h_res, 11, 'Orbit Motors Ltd', '27AAGCO7731P1ZR', 'Maharashtra', NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-06-03', 80000, 'Bank Transfer', @h_eng, 10, 'Dhruva Pharma Ltd', '24AAHCD6614R1Z7', 'Gujarat', NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-06-05', 1530000, 'Bank Transfer', @g_hostel, 5, 'Summer school stay', NULL, NULL, NULL, '60', '30', NULL, NULL, @g_user),
('2025-06-05', 65000, 'Bank Transfer', @g_admin, 14, 'Spark Productions', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-06-05', 44000, 'UPI', @h_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-06-06', 165000, 'UPI', @g_mgmt, 12, 'MDP participants (corporate)', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-06-06', 120000, 'Bank Transfer', @h_admin, 14, 'Spark Productions', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-06-07', 1530000, 'Bank Transfer', @h_hostel, 5, 'Summer school stay', NULL, NULL, NULL, '60', '30', NULL, NULL, @h_user),
('2025-06-07', 1620000, 'Bank Transfer', @r_hostel, 5, 'Summer school stay', NULL, NULL, NULL, '60', '30', NULL, NULL, @r_user),
('2025-06-08', 80000, 'Bank Transfer', @r_admin, 14, 'Kala Events', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-06-09', 220000, 'UPI', @h_mgmt, 12, 'MDP participants (corporate)', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-06-12', 60000, 'Bank Transfer', @g_eng, 10, 'Dhruva Pharma Ltd', '24AAHCD6614R1Z7', 'Gujarat', NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-06-13', 2587000, 'UPI', @h_acc, 2, 'Admission fees - new batch', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-06-15', 80000, 'Bank Transfer', @r_eng, 10, 'Coromandel Systems Ltd', '33AAJCS2290M1Z1', 'Tamil Nadu', NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-06-17', 1780000, 'UPI', @g_acc, 2, 'Admission fees - new batch', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-06-17', 34000, 'UPI', @r_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-06-22', 1200000, 'UPI', @r_acc, 2, 'Admission fees - new batch', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-06-23', 205000, 'UPI', @r_mgmt, 12, 'MDP participants (corporate)', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-06-26', 40000, 'UPI', @g_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-07-03', 8384000, 'Bank Transfer', @r_acc, 1, 'Semester fees - all students', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-07-04', 9910000, 'Bank Transfer', @g_acc, 1, 'Semester fees - all students', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-07-04', 80000, 'Bank Transfer', @g_eng, 10, 'Dhruva Pharma Ltd', '24AAHCD6614R1Z7', 'Gujarat', NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-07-05', 17760000, 'Bank Transfer', @g_hostel, 5, 'Hostel fees - semester', NULL, NULL, NULL, '400', '150', NULL, NULL, @g_user),
('2025-07-05', 14400000, 'Bank Transfer', @r_hostel, 5, 'Hostel fees - semester', NULL, NULL, NULL, '320', '150', NULL, NULL, @r_user),
('2025-07-07', 31000, 'UPI', @r_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-07-11', 56000, 'UPI', @g_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-07-11', 13559000, 'Bank Transfer', @h_acc, 1, 'Semester fees - all students', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-07-11', 1576000, 'UPI', @r_acc, 2, 'Admission fees - new batch', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-07-14', 24024000, 'Bank Transfer', @h_hostel, 5, 'Hostel fees - semester', NULL, NULL, NULL, '520', '150', NULL, NULL, @h_user),
('2025-07-16', 38000, 'UPI', @h_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-07-18', 80000, 'Bank Transfer', @r_eng, 10, 'Dhruva Pharma Ltd', '24AAHCD6614R1Z7', 'Gujarat', NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-07-19', 45000, 'Bank Transfer', @g_eng, 10, 'Dhruva Pharma Ltd', '24AAHCD6614R1Z7', 'Gujarat', NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-07-19', 75000, 'Bank Transfer', @h_eng, 10, 'Dhruva Pharma Ltd', '24AAHCD6614R1Z7', 'Gujarat', NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-07-20', 2574000, 'UPI', @h_acc, 2, 'Admission fees - new batch', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-07-21', 1880000, 'UPI', @g_acc, 2, 'Admission fees - new batch', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-07-25', 75000, 'Bank Transfer', @h_eng, 10, 'Orbit Motors Ltd', '27AAGCO7731P1ZR', 'Maharashtra', NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-08-03', 90000, 'Bank Transfer', @g_eng, 10, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-08-03', 49000, 'UPI', @r_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-08-04', 215000, 'UPI', @g_mgmt, 12, 'MDP participants (corporate)', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-08-04', 1030000, 'Bank Transfer', @r_admin, 16, 'Affiliated colleges', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-08-05', 270000, 'Bank Transfer', @r_res, 11, 'Dhruva Pharma Ltd', '24AAHCD6614R1Z7', 'Gujarat', NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-08-07', 880000, 'Bank Transfer', @r_res, 7, 'DST - project grant', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-08-09', 57000, 'UPI', @g_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-08-09', 38000, 'UPI', @h_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-08-12', 1950000, 'Bank Transfer', @h_res, 7, 'DST - project grant', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-08-16', 1450000, 'Bank Transfer', @g_res, 7, 'DST - project grant', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-08-16', 220000, 'Bank Transfer', @h_res, 11, 'Coromandel Systems Ltd', '33AAJCS2290M1Z1', NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-08-20', 195000, 'UPI', @r_mgmt, 12, 'MDP participants (corporate)', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-08-22', 55000, 'Bank Transfer', @h_eng, 10, 'Dhruva Pharma Ltd', '24AAHCD6614R1Z7', 'Gujarat', NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-08-23', 55000, 'Bank Transfer', @r_eng, 10, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', 'Karnataka', NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-08-24', 170000, 'UPI', @h_mgmt, 12, 'MDP participants (corporate)', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-08-26', 290000, 'Bank Transfer', @g_res, 11, 'Orbit Motors Ltd', '27AAGCO7731P1ZR', 'Maharashtra', NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-09-02', 1040000, 'Bank Transfer', @r_admin, 16, 'Affiliated colleges', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-09-04', 90000, 'Bank Transfer', @h_admin, 14, 'Spark Productions', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-09-06', 50000, 'Bank Transfer', @h_eng, 10, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', 'Karnataka', NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-09-07', 41000, 'UPI', @g_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-09-08', 650000, 'Bank Transfer', @g_admin, 8, 'State government subsidy', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-09-09', 60000, 'Bank Transfer', @r_eng, 10, 'Coromandel Systems Ltd', '33AAJCS2290M1Z1', 'Tamil Nadu', NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-09-10', 45000, 'Bank Transfer', @g_eng, 15, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-09-12', 80000, 'Bank Transfer', @h_eng, 15, 'Coromandel Systems Ltd', '33AAJCS2290M1Z1', NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-09-13', 75000, 'Bank Transfer', @g_admin, 14, 'City Music Society', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-09-14', 50000, 'Bank Transfer', @h_eng, 10, 'Orbit Motors Ltd', '27AAGCO7731P1ZR', 'Maharashtra', NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-09-14', 34000, 'UPI', @r_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-09-15', 780000, 'Bank Transfer', @h_admin, 8, 'State government subsidy', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-09-15', 480000, 'Bank Transfer', @r_admin, 8, 'State government subsidy', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-09-16', 65000, 'Bank Transfer', @r_eng, 15, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-09-22', 65000, 'Bank Transfer', @g_eng, 10, 'Dhruva Pharma Ltd', '24AAHCD6614R1Z7', 'Gujarat', NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-09-23', 110000, 'Bank Transfer', @r_admin, 14, 'Spark Productions', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-09-24', 36000, 'UPI', @h_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-10-09', 51000, 'UPI', @g_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-10-09', 175000, 'UPI', @r_mgmt, 12, 'MDP participants (corporate)', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-10-10', 90000, 'Bank Transfer', @g_eng, 10, 'Dhruva Pharma Ltd', '24AAHCD6614R1Z7', 'Gujarat', NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-10-11', 35000, 'UPI', @r_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-10-13', 2080000, 'Bank Transfer', @r_res, 6, 'UGC - research grant', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-10-13', 45000, 'Bank Transfer', @r_eng, 10, 'Orbit Motors Ltd', '27AAGCO7731P1ZR', NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-10-14', 85000, 'Bank Transfer', @h_eng, 10, 'Dhruva Pharma Ltd', '24AAHCD6614R1Z7', 'Gujarat', NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-10-17', 2750000, 'Bank Transfer', @g_res, 6, 'UGC - research grant', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-10-18', 60000, 'Bank Transfer', @r_eng, 10, 'Orbit Motors Ltd', '27AAGCO7731P1ZR', NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-10-23', 3315000, 'Bank Transfer', @h_res, 6, 'UGC - research grant', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-10-24', 190000, 'UPI', @g_mgmt, 12, 'MDP participants (corporate)', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-10-24', 150000, 'UPI', @h_mgmt, 12, 'MDP participants (corporate)', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-10-26', 48000, 'UPI', @h_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-11-04', 260000, 'Bank Transfer', @g_res, 11, 'Coromandel Systems Ltd', '33AAJCS2290M1Z1', 'Tamil Nadu', NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-11-06', 38000, 'UPI', @r_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-11-10', 810000, 'UPI', @g_acc, 3, 'Exam fees - all students', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-11-11', 1235000, 'UPI', @h_acc, 3, 'Exam fees - all students', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-11-11', 70000, 'Bank Transfer', @h_eng, 10, 'Coromandel Systems Ltd', '33AAJCS2290M1Z1', NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-11-12', 70000, 'Bank Transfer', @g_eng, 10, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-11-12', 776000, 'UPI', @r_acc, 3, 'Exam fees - all students', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-11-17', 37000, 'UPI', @h_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-11-19', 270000, 'Bank Transfer', @h_res, 11, 'Dhruva Pharma Ltd', '24AAHCD6614R1Z7', 'Gujarat', NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-11-20', 58000, 'UPI', @g_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-11-21', 90000, 'Bank Transfer', @r_eng, 10, 'Coromandel Systems Ltd', '33AAJCS2290M1Z1', 'Tamil Nadu', NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-11-23', 80000, 'Bank Transfer', @r_eng, 10, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', 'Karnataka', NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-11-23', 230000, 'Bank Transfer', @r_res, 11, 'Coromandel Systems Ltd', '33AAJCS2290M1Z1', 'Tamil Nadu', NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-12-06', 60000, 'Bank Transfer', @g_eng, 10, 'Dhruva Pharma Ltd', '24AAHCD6614R1Z7', 'Gujarat', NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-12-06', 165000, 'UPI', @g_mgmt, 12, 'MDP participants (corporate)', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-12-07', 95000, 'Bank Transfer', @h_admin, 14, 'Kala Events', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-12-08', 130000, 'Cheque', @r_admin, 9, 'Alumni association', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-12-08', 200000, 'UPI', @r_mgmt, 12, 'MDP participants (corporate)', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-12-10', 60000, 'Bank Transfer', @r_eng, 10, 'Orbit Motors Ltd', '27AAGCO7731P1ZR', NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-12-10', 100000, 'Bank Transfer', @r_admin, 14, 'Spark Productions', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-12-12', 250000, 'Cash', @g_admin, 14, 'Starlight Wedding Planners', NULL, NULL, 'EVT-1201', NULL, NULL, NULL, 'Convocation hall rental - cash', @g_user),
('2025-12-13', 230000, 'Cheque', @h_admin, 9, 'Alumni association', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-12-14', 90000, 'Bank Transfer', @g_eng, 10, 'Dhruva Pharma Ltd', '24AAHCD6614R1Z7', 'Gujarat', NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-12-14', 65000, 'Bank Transfer', @h_eng, 10, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', 'Karnataka', NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-12-14', 53000, 'UPI', @h_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-12-15', 160000, 'Cheque', @g_admin, 9, 'Alumni association', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-12-19', 80000, 'Bank Transfer', @g_admin, 14, 'City Music Society', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2025-12-22', 57000, 'UPI', @r_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-12-23', 200000, 'UPI', @h_mgmt, 12, 'MDP participants (corporate)', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2025-12-24', 65000, 'Bank Transfer', @r_eng, 10, 'Orbit Motors Ltd', '27AAGCO7731P1ZR', NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2025-12-25', 47000, 'UPI', @g_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-01-03', 40000, 'Bank Transfer', @r_eng, 10, 'Coromandel Systems Ltd', '33AAJCS2290M1Z1', 'Tamil Nadu', NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-01-04', 90000, 'Bank Transfer', @h_eng, 10, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', 'Karnataka', NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-01-06', 80000, 'Bank Transfer', @g_eng, 10, 'Orbit Motors Ltd', '27AAGCO7731P1ZR', 'Maharashtra', NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-01-06', 75000, 'Bank Transfer', @h_eng, 10, 'Dhruva Pharma Ltd', '24AAHCD6614R1Z7', 'Gujarat', NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-01-06', 60000, 'Bank Transfer', @r_eng, 15, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-01-07', 31000, 'UPI', @h_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-01-07', 7304000, 'Bank Transfer', @r_acc, 1, 'Semester fees - all students', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-01-10', 70000, 'Bank Transfer', @h_eng, 15, 'Coromandel Systems Ltd', '33AAJCS2290M1Z1', NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-01-11', 19020000, 'Bank Transfer', @g_hostel, 5, 'Hostel fees - semester', NULL, NULL, NULL, '400', '150', NULL, NULL, @g_user),
('2026-01-11', 21918000, 'Bank Transfer', @h_hostel, 5, 'Hostel fees - semester', NULL, NULL, NULL, '520', '150', NULL, NULL, @h_user),
('2026-01-12', 10090000, 'Bank Transfer', @g_acc, 1, 'Semester fees - all students', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-01-12', 13468000, 'Bank Transfer', @h_acc, 1, 'Semester fees - all students', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-01-12', 54000, 'UPI', @r_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-01-15', 13680000, 'Bank Transfer', @r_hostel, 5, 'Hostel fees - semester', NULL, NULL, NULL, '320', '150', NULL, NULL, @r_user),
('2026-01-17', 32000, 'UPI', @g_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-01-26', 40000, 'Bank Transfer', @g_eng, 15, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-02-04', 45000, 'UPI', @h_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-02-05', 45000, 'Bank Transfer', @r_eng, 10, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', 'Karnataka', NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-02-10', 330000, 'Bank Transfer', @h_res, 11, 'Dhruva Pharma Ltd', '24AAHCD6614R1Z7', 'Gujarat', NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-02-10', 215000, 'UPI', @h_mgmt, 12, 'MDP participants (corporate)', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-02-12', 65000, 'Bank Transfer', @h_eng, 10, 'Dhruva Pharma Ltd', '24AAHCD6614R1Z7', 'Gujarat', NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-02-13', 195000, 'UPI', @r_mgmt, 12, 'MDP participants (corporate)', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-02-14', 320000, 'Bank Transfer', @g_res, 11, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-02-18', 38000, 'UPI', @g_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-02-19', 70000, 'Bank Transfer', @r_eng, 10, 'Dhruva Pharma Ltd', '24AAHCD6614R1Z7', 'Gujarat', NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-02-19', 210000, 'Bank Transfer', @r_res, 11, 'Orbit Motors Ltd', '27AAGCO7731P1ZR', NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-02-19', 34000, 'UPI', @r_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-02-21', 185000, 'UPI', @g_mgmt, 12, 'MDP participants (corporate)', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-02-23', 70000, 'Bank Transfer', @g_eng, 10, 'Orbit Motors Ltd', '27AAGCO7731P1ZR', 'Maharashtra', NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-03-04', 54000, 'UPI', @h_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-03-05', 130000, 'Cheque', @g_admin, 9, 'Alumni association', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-03-05', 60000, 'Bank Transfer', @g_eng, 10, 'Coromandel Systems Ltd', '33AAJCS2290M1Z1', 'Tamil Nadu', NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-03-05', 270000, 'Cheque', @h_admin, 9, 'Alumni association', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-03-09', 90000, 'Bank Transfer', @h_eng, 10, 'Coromandel Systems Ltd', '33AAJCS2290M1Z1', NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-03-09', 150000, 'Cash', @r_admin, 14, 'Vedika Events', NULL, NULL, 'EVT-0309', NULL, NULL, NULL, NULL, @r_user),
('2026-03-09', 70000, 'Cash', @r_admin, 14, 'Vedika Events', NULL, NULL, 'EVT-0309', NULL, NULL, NULL, 'Second cash part, same day', @r_user),
('2026-03-13', 40000, 'Bank Transfer', @r_eng, 10, 'Coromandel Systems Ltd', '33AAJCS2290M1Z1', 'Tamil Nadu', NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-03-13', 36000, 'UPI', @r_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-03-15', 35000, 'UPI', @g_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-03-16', 60000, 'Bank Transfer', @g_admin, 14, 'City Music Society', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-03-18', 140000, 'Cheque', @r_admin, 9, 'Alumni association', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-03-22', 60000, 'Bank Transfer', @h_admin, 14, 'Kala Events', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-03-23', 75000, 'Bank Transfer', @r_admin, 14, 'City Music Society', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-03-26', 90000, 'Bank Transfer', @g_eng, 10, 'Coromandel Systems Ltd', '33AAJCS2290M1Z1', 'Tamil Nadu', NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-04-05', 48000, 'UPI', @h_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-04-07', 50000, 'Bank Transfer', @r_eng, 10, 'Orbit Motors Ltd', '27AAGCO7731P1ZR', NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-04-07', 53000, 'UPI', @r_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-04-09', 50000, 'Bank Transfer', @h_eng, 10, 'Orbit Motors Ltd', '27AAGCO7731P1ZR', 'Maharashtra', NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-04-13', 2440000, 'Bank Transfer', @r_res, 6, 'UGC - research grant', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-04-14', 980000, 'Bank Transfer', @h_mgmt, 12, 'Large corporate MDP batch', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-04-15', 150000, 'UPI', @r_mgmt, 12, 'MDP participants (corporate)', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-04-17', 3640000, 'Bank Transfer', @h_res, 6, 'UGC - research grant', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-04-17', 200000, 'UPI', @h_mgmt, 12, 'MDP participants (corporate)', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-04-18', 3300000, 'Bank Transfer', @g_res, 6, 'UGC - research grant', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-04-21', 36000, 'UPI', @g_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-04-21', 50000, 'Bank Transfer', @r_eng, 10, 'Dhruva Pharma Ltd', '24AAHCD6614R1Z7', 'Gujarat', NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-04-22', 60000, 'Bank Transfer', @g_eng, 10, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-04-22', 190000, 'UPI', @g_mgmt, 12, 'MDP participants (corporate)', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-05-02', 230000, 'Bank Transfer', @g_res, 11, 'Dhruva Pharma Ltd', '24AAHCD6614R1Z7', 'Gujarat', NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-05-06', 75000, 'Bank Transfer', @r_eng, 10, 'Orbit Motors Ltd', '27AAGCO7731P1ZR', NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-05-06', 75000, 'Bank Transfer', @r_eng, 10, 'Orbit Motors Ltd', '27AAGCO7731P1ZR', NULL, NULL, NULL, NULL, NULL, 'Entered twice by mistake?', @r_user),
('2026-05-07', 910000, 'UPI', @g_acc, 3, 'Exam fees - all students', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-05-08', 1222000, 'UPI', @h_acc, 3, 'Exam fees - all students', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-05-09', 260000, 'Bank Transfer', @r_res, 11, 'Dhruva Pharma Ltd', '24AAHCD6614R1Z7', 'Gujarat', NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-05-10', 744000, 'UPI', @r_acc, 3, 'Exam fees - all students', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-05-10', 50000, 'Bank Transfer', @r_eng, 10, 'Orbit Motors Ltd', '27AAGCO7731P1ZR', NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-05-11', 55000, 'Bank Transfer', @g_eng, 15, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-05-11', 33000, 'UPI', @h_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-05-11', 55000, 'Bank Transfer', @r_eng, 15, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-05-13', 58000, 'UPI', @g_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-05-14', 40000, 'Bank Transfer', @r_eng, 10, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', 'Karnataka', NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-05-16', 41000, 'UPI', @r_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-05-20', 40000, 'Bank Transfer', @h_eng, 15, 'Coromandel Systems Ltd', '33AAJCS2290M1Z1', NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-05-21', 65000, 'Bank Transfer', @g_eng, 10, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-05-21', 85000, 'Bank Transfer', @h_eng, 10, 'Orbit Motors Ltd', '27AAGCO7731P1ZR', 'Maharashtra', NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-05-26', 65000, 'Bank Transfer', @h_eng, 10, 'Coromandel Systems Ltd', '33AAJCS2290M1Z1', NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-05-26', 250000, 'Bank Transfer', @h_res, 11, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', 'Karnataka', NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-06-02', 1530000, 'Bank Transfer', @g_hostel, 5, 'Summer school stay', NULL, NULL, NULL, '60', '30', NULL, NULL, @g_user),
('2026-06-04', 80000, 'Bank Transfer', @g_eng, 10, 'Dhruva Pharma Ltd', '24AAHCD6614R1Z7', 'Gujarat', NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-06-04', 1530000, 'Bank Transfer', @h_hostel, 5, 'Summer school stay', NULL, NULL, NULL, '60', '30', NULL, NULL, @h_user),
('2026-06-04', 1620000, 'Bank Transfer', @r_hostel, 5, 'Summer school stay', NULL, NULL, NULL, '60', '30', NULL, NULL, @r_user),
('2026-06-04', 60000, 'Bank Transfer', @r_eng, 10, 'Coromandel Systems Ltd', '33AAJCS2290M1Z1', 'Tamil Nadu', NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-06-05', 60000, 'Bank Transfer', @h_eng, 10, 'Orbit Motors Ltd', '27AAGCO7731P1ZR', 'Maharashtra', NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-06-06', 90000, 'Bank Transfer', @g_eng, 10, 'Orbit Motors Ltd', '27AAGCO7731P1ZR', 'Maharashtra', NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-06-07', 38000, 'UPI', @g_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-06-10', 1536000, 'UPI', @r_acc, 2, 'Admission fees - new batch', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-06-13', 190000, 'UPI', @h_mgmt, 12, 'MDP participants (corporate)', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-06-13', 65000, 'Bank Transfer', @h_admin, 14, 'City Music Society', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-06-13', 200000, 'UPI', @r_mgmt, 12, 'MDP participants (corporate)', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-06-15', 51000, 'UPI', @h_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-06-16', 300000, 'Bank Transfer', @g_res, 11, 'Dhruva Pharma Ltd', '24AAHCD6614R1Z7', 'Gujarat', NULL, NULL, NULL, '1500', 'Client deducted less TDS', @g_user),
('2026-06-17', 1860000, 'UPI', @g_acc, 2, 'Admission fees - new batch', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-06-17', 190000, 'UPI', @g_mgmt, 12, 'MDP participants (corporate)', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-06-18', 105000, 'Bank Transfer', @g_admin, 14, 'Spark Productions', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-06-18', 42000, 'UPI', @r_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-06-20', 40000, 'Bank Transfer', @h_eng, 10, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', 'Karnataka', NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-06-22', 2275000, 'UPI', @h_acc, 2, 'Admission fees - new batch', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-06-23', 100000, 'Bank Transfer', @r_admin, 14, 'Spark Productions', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-07-03', 7432000, 'Bank Transfer', @r_acc, 1, 'Semester fees - all students', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-07-05', 55000, 'Bank Transfer', @g_eng, 10, 'Dhruva Pharma Ltd', '24AAHCD6614R1Z7', 'Gujarat', NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-07-06', 10380000, 'Bank Transfer', @g_acc, 1, 'Semester fees - all students', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-07-08', 11739000, 'Bank Transfer', @h_acc, 1, 'Semester fees - all students', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-07-09', 32000, 'UPI', @g_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-07-09', 15216000, 'Bank Transfer', @r_hostel, 5, 'Hostel fees - semester', NULL, NULL, NULL, '320', '150', NULL, NULL, @r_user),
('2026-07-11', 17940000, 'Bank Transfer', @g_hostel, 5, 'Hostel fees - semester', NULL, NULL, NULL, '400', '150', NULL, NULL, @g_user),
('2026-07-11', 22308000, 'Bank Transfer', @h_hostel, 5, 'Hostel fees - semester', NULL, NULL, NULL, '520', '150', NULL, NULL, @h_user),
('2026-07-13', 53000, 'UPI', @r_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-07-15', 35000, 'UPI', @h_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-07-16', 1950000, 'UPI', @g_acc, 2, 'Admission fees - new batch', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-07-16', 80000, 'Bank Transfer', @g_eng, 10, 'Coromandel Systems Ltd', '33AAJCS2290M1Z1', 'Tamil Nadu', NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-07-18', 1288000, 'UPI', @r_acc, 2, 'Admission fees - new batch', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-07-21', 70000, 'Bank Transfer', @r_eng, 10, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', 'Karnataka', NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-07-23', 2353000, 'UPI', @h_acc, 2, 'Admission fees - new batch', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-07-24', 50000, 'Bank Transfer', @h_eng, 10, 'Dhruva Pharma Ltd', '24AAHCD6614R1Z7', 'Gujarat', NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-08-02', 260000, 'Bank Transfer', @r_res, 11, 'Dhruva Pharma Ltd', '24AAHCD6614R1Z7', 'Gujarat', NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-08-03', 215000, 'UPI', @g_mgmt, 12, 'MDP participants (corporate)', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-08-04', 90000, 'Bank Transfer', @g_eng, 10, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-08-04', 60000, 'UPI', @r_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-08-09', 220000, 'Bank Transfer', @g_res, 11, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-08-09', 210000, 'UPI', @h_mgmt, 12, 'MDP participants (corporate)', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-08-10', 340000, 'Bank Transfer', @h_res, 11, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', 'Karnataka', NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-08-10', 40000, 'Bank Transfer', @r_eng, 10, 'Orbit Motors Ltd', '27AAGCO7731P1ZR', NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-08-12', 32000, 'UPI', @g_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-08-12', 55000, 'Bank Transfer', @h_eng, 10, 'Coromandel Systems Ltd', '33AAJCS2290M1Z1', NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-08-13', 1885000, 'Bank Transfer', @h_res, 7, 'DST - project grant', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-08-13', 180000, 'UPI', @r_mgmt, 12, 'MDP participants (corporate)', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-08-14', 85000, 'Bank Transfer', @r_eng, 10, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', 'Karnataka', NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-08-15', 1000000, 'Bank Transfer', @g_res, 7, 'DST - project grant', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-08-15', 1040000, 'Bank Transfer', @r_res, 7, 'DST - project grant', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-08-16', 70000, 'Bank Transfer', @h_eng, 10, 'Dhruva Pharma Ltd', '24AAHCD6614R1Z7', 'Gujarat', NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-08-16', 48000, 'UPI', @h_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-08-20', 55000, 'Bank Transfer', @g_eng, 10, 'Orbit Motors Ltd', '27AAGCO7731P1ZR', 'Maharashtra', NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-08-23', 1190000, 'Bank Transfer', @r_admin, 16, 'Affiliated colleges', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-09-08', 80000, 'Bank Transfer', @g_eng, 10, 'Dhruva Pharma Ltd', '24AAHCD6614R1Z7', 'Gujarat', NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-09-08', 1030000, 'Bank Transfer', @r_admin, 16, 'Affiliated colleges', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-09-09', 120000, 'Bank Transfer', @g_admin, 14, 'Spark Productions', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-09-12', 600000, 'Bank Transfer', @g_admin, 8, 'State government subsidy', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-09-12', 50000, 'Bank Transfer', @h_eng, 10, 'Dhruva Pharma Ltd', '24AAHCD6614R1Z7', 'Gujarat', NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-09-12', 60000, 'Bank Transfer', @h_eng, 15, 'Coromandel Systems Ltd', '33AAJCS2290M1Z1', NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-09-13', 120000, 'Bank Transfer', @h_admin, 14, 'Spark Productions', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-09-14', 60000, 'Bank Transfer', @r_eng, 15, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-09-15', 55000, 'Bank Transfer', @g_eng, 15, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-09-15', 560000, 'Bank Transfer', @r_admin, 8, 'State government subsidy', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-09-17', 780000, 'Bank Transfer', @h_admin, 8, 'State government subsidy', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-09-17', 36000, 'UPI', @h_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-09-18', 39000, 'UPI', @r_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-09-20', 45000, 'UPI', @g_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-09-23', 90000, 'Bank Transfer', @r_admin, 14, 'Spark Productions', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-09-25', 85000, 'Bank Transfer', @g_eng, 10, 'Orbit Motors Ltd', '27AAGCO7731P1ZR', 'Maharashtra', NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-09-25', 60000, 'Bank Transfer', @r_eng, 10, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', 'Karnataka', NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-10-08', 180000, 'UPI', @r_mgmt, 12, 'MDP participants (corporate)', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-10-09', 70000, 'Bank Transfer', @h_eng, 10, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', 'Karnataka', NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-10-10', 4290000, 'Bank Transfer', @h_res, 6, 'UGC - research grant', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-10-11', 60000, 'Bank Transfer', @r_eng, 10, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', 'Karnataka', NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-10-13', 3150000, 'Bank Transfer', @g_res, 6, 'UGC - research grant', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-10-14', 80000, 'Bank Transfer', @r_eng, 10, 'Coromandel Systems Ltd', '33AAJCS2290M1Z1', 'Tamil Nadu', NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-10-15', 75000, 'Bank Transfer', @g_eng, 10, 'Dhruva Pharma Ltd', '24AAHCD6614R1Z7', 'Gujarat', NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-10-17', 190000, 'UPI', @h_mgmt, 12, 'MDP participants (corporate)', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-10-20', 49000, 'UPI', @r_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-10-22', 2200000, 'Bank Transfer', @r_res, 6, 'UGC - research grant', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-10-23', 50000, 'UPI', @g_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-10-25', 150000, 'UPI', @g_mgmt, 12, 'MDP participants (corporate)', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-10-26', 37000, 'UPI', @h_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-11-08', 47000, 'UPI', @g_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-11-09', 260000, 'Bank Transfer', @g_res, 11, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-11-11', 55000, 'Bank Transfer', @h_eng, 10, 'Nimbus Analytics Pvt Ltd', '29AAECN4410K1ZE', 'Karnataka', NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-11-11', 51000, 'UPI', @h_mgmt, 13, 'Online course learners', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-11-12', 1300000, 'UPI', @h_acc, 3, 'Exam fees - all students', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-11-15', 830000, 'UPI', @g_acc, 3, 'Exam fees - all students', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @g_user),
('2026-11-15', 720000, 'UPI', @r_acc, 3, 'Exam fees - all students', NULL, NULL, NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-11-16', 40000, 'Bank Transfer', @h_eng, 10, 'Dhruva Pharma Ltd', '24AAHCD6614R1Z7', 'Gujarat', NULL, NULL, NULL, NULL, NULL, @h_user),
('2026-11-16', 90000, 'Bank Transfer', @r_eng, 10, 'Dhruva Pharma Ltd', '24AAHCD6614R1Z7', 'Gujarat', NULL, NULL, NULL, NULL, NULL, @r_user),
('2026-11-18', 350000, 'Bank Transfer', @r_res, 11, 'Orbit Motors Ltd', '27AAGCO7731P1ZR', NULL, NULL, NULL, NULL, NULL, NULL, @r_user);

-- a mistake corrected the right way: credit note for half of Riverside's double entry
INSERT INTO revenue_transaction (Entry_Type, Original_Trans_ID, Trans_Date, Amount, Mode,
                                 Dept_ID, Source_ID, Payer_Name, Description, Created_By)
SELECT 'CREDIT_NOTE', MAX(t.Trans_ID), '2026-05-08', 75000, 'Bank Transfer',
       @r_eng, 10, 'Orbit Motors Ltd', 'Reverses duplicate entry of 6 May', @r_user
FROM revenue_transaction t
WHERE t.Dept_ID = @r_eng AND t.Trans_Date = '2026-05-06' AND t.Amount = 75000;

-- ---------------------------------------------------------------------
-- 5. GST payments (each university's pattern), then admin verification
-- ---------------------------------------------------------------------
-- on-time payments: 2 days before the due date
INSERT INTO payment (Tax_ID, Payment_For, Amount, Payment_Date, Mode, Reference_No)
SELECT Tax_ID, 'Tax', Tax_Due, Due_Date - INTERVAL 2 DAY, 'Net Banking',
       CONCAT('CIN', Univ_ID, DATE_FORMAT(Period_Start, '%y%m'), 'T')
FROM tax_record
WHERE Tax_Due > 0
  AND Due_Date - INTERVAL 2 DAY <= CURDATE()
  AND NOT (Univ_ID = 1 AND Period_Start IN ('2026-01-01', '2026-10-01'))  -- Greenfield: late / unpaid
  AND NOT (Univ_ID = 2 AND Period_Start >= '2026-07-01');                -- Riverside: stopped paying

-- Greenfield pays January 2026 twelve days late ...
INSERT INTO payment (Tax_ID, Payment_For, Amount, Payment_Date, Mode, Reference_No)
SELECT Tax_ID, 'Tax', Tax_Due, Due_Date + INTERVAL 12 DAY, 'NEFT/RTGS', 'CIN12601TL'
FROM tax_record WHERE Univ_ID = 1 AND Period_Start = '2026-01-01';

-- Riverside pays part of July 2026 - still waiting for the admin to verify
INSERT INTO payment (Tax_ID, Payment_For, Amount, Payment_Date, Mode, Reference_No)
SELECT Tax_ID, 'Tax', ROUND(Tax_Due / 2, 2), Due_Date + INTERVAL 20 DAY, 'UPI', 'CIN22607TP'
FROM tax_record WHERE Univ_ID = 2 AND Period_Start = '2026-07-01';

-- admin verifies every payment except Riverside's latest one
DROP PROCEDURE IF EXISTS Demo_Verify_All;
DELIMITER //
CREATE PROCEDURE Demo_Verify_All()
BEGIN
    DECLARE v_id INT;
    DECLARE v_done BOOLEAN DEFAULT FALSE;
    DECLARE c CURSOR FOR SELECT Payment_ID FROM payment
                         WHERE Status = 'Pending' AND Reference_No <> 'CIN22607TP'
                         ORDER BY Payment_ID;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = TRUE;
    OPEN c;
    l: LOOP
        FETCH c INTO v_id;
        IF v_done THEN LEAVE l; END IF;
        CALL Verify_Payment(v_id, @admin, 'Verified', 'Matched with bank statement');
    END LOOP;
    CLOSE c;
END //
DELIMITER ;
CALL Demo_Verify_All();
DROP PROCEDURE Demo_Verify_All;

-- ... and then pays the interest for those 12 days (separate challan head)
INSERT INTO payment (Tax_ID, Payment_For, Amount, Payment_Date, Mode, Reference_No)
SELECT Tax_ID, 'Interest', Calculate_Bill_Interest(Tax_ID, Due_Date + INTERVAL 15 DAY),
       Due_Date + INTERVAL 15 DAY, 'NEFT/RTGS', 'CIN12601I'
FROM tax_record WHERE Univ_ID = 1 AND Period_Start = '2026-01-01';
CALL Verify_Payment(LAST_INSERT_ID(), @admin, 'Verified', 'Interest for 12 days late');

-- ---------------------------------------------------------------------
-- 6. Alerts history: run the daily job for every day of the last 60 days
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS Demo_Alert_History;
DELIMITER //
CREATE PROCEDURE Demo_Alert_History()
BEGIN
    DECLARE v_day DATE DEFAULT CURDATE() - INTERVAL 60 DAY;
    WHILE v_day <= CURDATE() DO
        CALL Generate_Daily_Alerts(v_day);
        SET v_day = v_day + INTERVAL 1 DAY;
    END WHILE;
END //
DELIMITER ;
CALL Demo_Alert_History();
DROP PROCEDURE Demo_Alert_History;

-- ---------------------------------------------------------------------
-- 7. A notice from the admin to the overdue university
-- ---------------------------------------------------------------------
INSERT INTO notice (Univ_ID, Tax_ID, Type, Subject, Message, Issued_By, Response_Due)
SELECT 2, MIN(Tax_ID), 'Demand', 'GST unpaid since July 2026',
       'Our records show GST for July 2026 onwards is unpaid. Please pay the outstanding tax with interest under Section 50 of the CGST Act, or explain the delay.',
       @admin, CURDATE() + INTERVAL 7 DAY
FROM tax_record WHERE Univ_ID = 2 AND Period_Start >= '2026-07-01';

INSERT INTO notice (Univ_ID, Anomaly_ID, Type, Subject, Message, Issued_By, Response_Due,
                    Status, Response, Responded_At)
SELECT Univ_ID, Anomaly_ID, 'Anomaly Query', 'Cash receipt above Rs 2 lakh',
       'A cash receipt of Rs 2,50,000 was recorded on 12 Dec 2025. Receiving Rs 2 lakh or more in cash is not allowed. Please explain.',
       @admin, '2026-01-10', 'Responded',
       'The event company paid in cash at the venue. We have informed them that future payments must be by bank transfer.',
       '2026-01-05 15:20:00'
FROM anomaly WHERE Univ_ID = 1 AND Rule_Code = 'CASH_LIMIT' LIMIT 1;

-- ---------------------------------------------------------------------
-- Summary
-- ---------------------------------------------------------------------
SELECT u.Name, u.Status,
       (SELECT COUNT(*) FROM revenue_transaction t JOIN department d ON d.Dept_ID = t.Dept_ID
         WHERE d.Univ_ID = u.Univ_ID) AS Entries,
       (SELECT COUNT(*) FROM tax_record tr WHERE tr.Univ_ID = u.Univ_ID) AS Monthly_Bills,
       (SELECT COUNT(*) FROM anomaly a WHERE a.Univ_ID = u.Univ_ID) AS Anomalies,
       Compliance_Status(u.Univ_ID, CURDATE()) AS Compliance
FROM university u;
