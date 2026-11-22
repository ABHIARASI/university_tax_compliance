-- =====================================================================
-- University Tax Compliance Portal
-- File: database/07_app_user.sql
-- Purpose: a separate MySQL login for the backend, with ONLY the rights it
--          needs ("least privilege"). The app never connects as root.
--          It can read/insert/update and CALL procedures, but it cannot
--          DELETE rows, DROP tables or change the schema - so even a bug or
--          an attack through the app can't wipe the data.
-- Run (inside mysql, as root):  SOURCE database/07_app_user.sql;
-- Change the password below, and put the same one in backend/.env
-- =====================================================================

DROP USER IF EXISTS 'utc_app'@'localhost';
CREATE USER 'utc_app'@'localhost' IDENTIFIED BY 'Change_This_Password_123';

GRANT SELECT, INSERT, UPDATE, EXECUTE ON university_tax.* TO 'utc_app'@'localhost';

-- the only DELETE the app needs: clearing used password-reset tokens
GRANT DELETE ON university_tax.password_reset TO 'utc_app'@'localhost';

FLUSH PRIVILEGES;

SHOW GRANTS FOR 'utc_app'@'localhost';
