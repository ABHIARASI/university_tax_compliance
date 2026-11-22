# University Tax Compliance Portal

A full-stack web app that helps Indian universities stay **GST-compliant**, and helps the **tax office** monitor them.

Universities register themselves (choosing their own password), record their income, and get a **monthly GST bill** calculated automatically. That covers exempt vs taxable income, CGST/SGST vs IGST, TDS and late-payment interest. They receive **automatic alerts** before and after every due date until the tax is paid. The tax office approves registrations, verifies payments, reviews **automatically flagged anomalies** and sends notices.

**Stack:** MySQL 8 · Node.js 20+ / Express 5 · React 19 / Vite · Tailwind CSS · Recharts

---

## Features

**University**
- Self-registration with GSTIN check-digit validation; login only after tax-office approval
- Add income: GST, TDS and the monthly bill are calculated by database triggers
- Hostel-fee rule (exempt / 5% / 18%), inter-state IGST, credit notes for corrections
- Monthly GST bills with status (Due, Partial, Overdue, Interest due, Paid), plus GST and interest payments
- Daily alerts: 7, 3 and 1 day before the due date, on the due date, then **every day** until paid (in-app and email)
- Dashboard with 4 charts, notices from the tax office (with replies), flagged entries, staff logins

**Tax office (admin)**
- Approve, reject, suspend or reactivate universities; compliance overview of every university
- Verify or reject payments (with row locking, so a payment can't be counted twice)
- Anomalies: cash ≥ ₹2 lakh, spikes, duplicates, overpayments, TDS mismatches
- Notices, editable tax rules with an audit history, due-date extensions, running the alert job for any date

## Indian tax rules used

| Income | GST | TDS (by the paying client) |
|---|---|---|
| Tuition & admission fees, exam fees | Exempt (Notif. 12/2017-CT(R), Sl. 66) | – |
| Hostel fees | Exempt if ≤ ₹20,000 per student per month for 90+ days; else 5% / 18% | – |
| Government grants & subsidies, donations | Not a supply (Sec 7 CGST Act) | – |
| Consultancy | 18% | 10% above ₹50,000 a year (Sec 393, IT Act 2025; old 194J) |
| Sponsored research | 18% | 2% above ₹50,000 a year |
| Facility rental | 18% | 10% above ₹50,000 a month |
| Executive training, affiliation fees | 18% | – |

- GST is due on the **20th of the next month** (GSTR-3B). Late payment attracts **18% a year interest, counted per day** (Sec 50 CGST Act), following the actual payment dates.
- Same-state client: CGST 9% + SGST 9%. Other-state client: IGST 18%.
- **Cash receipts of ₹2 lakh or more are flagged** (Sec 186 IT Act 2025; old 269ST): one receipt, one payer in a day, or one event.
- Universities are usually income-tax exempt (Sec 10(23C) / 12AB), so TDS deducted by clients is shown as a **refund to claim**.

---

## Architecture

```
 Browser (React SPA, port 5173)
   │  fetch('/api/...')  + httpOnly JWT cookie
   ▼
 Vite dev server ──proxy /api──►  Express API (port 5000)
                                    helmet · cors · json · cookies
                                    → validate (Zod) → requireAuth (JWT) → requireRole
                                    → route handler → mysql2 pool (parameterised SQL)
                                    → errorHandler (one JSON error format)
                                    node-cron: daily alert job 9:00 IST → Nodemailer
                                    │
                                    ▼
                                  MySQL 8  (user utc_app: no DELETE / DROP)
                                    14 tables · 16 functions · 9 procedures · 9 triggers
```

**Where the logic lives**
- **Database:** every tax calculation (functions), every multi-step change (procedures, inside transactions, with `SELECT … FOR UPDATE` locks), and automation (triggers: GST/TDS on insert, monthly bill upsert, anomaly rules, audit log, no edits or deletes of income).
- **Backend:** authentication and authorisation, input validation, joining it all into a REST API, emails and the scheduler.
- **Frontend:** screens only. It never stores the token; the cookie is sent automatically.

## Project structure

```
database/
  01_schema.sql        14 tables, constraints, indexes
  02_seed.sql          GST state codes, admin login, 10 tax rules, 16 income sources
  03_functions.sql     GST rate, TDS, interest, due date, financial year, GSTIN check...
  04_procedures.sql    reports, approve/reject, verify payment, daily alerts, due-date extension
  05_triggers.sql      automatic GST / bill / anomaly / audit logic
  06_demo_data.sql     OPTIONAL sample universities with 20 months of data
  07_app_user.sql      least-privilege MySQL user for the backend
  tools/               script that generated the demo income rows
backend/
  src/server.js        start-up, scheduler, graceful shutdown
  src/app.js           middleware + routes
  src/config/          env.js (validated settings), db.js (pool, query, procedures, transactions)
  src/middleware/      auth.js (JWT, roles), validate.js (Zod), errorHandler.js
  src/routes/          auth, meta, university, admin
  src/services/        reports.js (shared queries), mailer.js
  src/jobs/            alerts.job.js (node-cron)
  src/utils/           dates, gstin, schemas, httpError
  scripts/             create-admin.js (optional)
frontend/
  src/main.jsx, App.jsx        entry and routes
  src/api/client.js            the only place that calls the backend
  src/context/AuthContext.jsx  who is logged in
  src/components/              Layout, ProtectedRoute, ui kit, Charts, BillDetail
  src/pages/auth|university|admin
```

---

## Run it locally (Windows / macOS / Linux)

**Needs:** Node.js 20.6+, MySQL 8.0.14+, Git.

### 1. Database
Open a terminal in the project folder and log in as root:
```
mysql -u root -p
```
```sql
SOURCE database/01_schema.sql;
SOURCE database/02_seed.sql;
SOURCE database/03_functions.sql;
SOURCE database/04_procedures.sql;
SOURCE database/05_triggers.sql;
SOURCE database/06_demo_data.sql;   -- optional: sample universities and data
SOURCE database/07_app_user.sql;    -- change the password inside first if you like
exit
```

### 2. Backend
```
cd backend
npm install
copy .env.example .env        (macOS/Linux: cp .env.example .env)
```
In `.env`, set `DB_PASSWORD` (the same as in `07_app_user.sql`) and a long `JWT_SECRET`:
```
node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"
```
Then:
```
npm run dev
```
Check http://localhost:5000/api/health, which should show `"status":"ok"`.

### 3. Frontend (in a second terminal)
```
cd frontend
npm install
npm run dev
```
Open **http://localhost:5173**.

### Logins
| Who | Email | Password |
|---|---|---|
| Tax office (admin) | admin@taxportal.in | Admin@123 (change it in Settings) |
| New university | register at /register | **chosen by the university** |
| Demo universities (only if 06 was loaded) | finance@greenfield.edu.in, finance@riverside.edu.in, finance@hillcrest.edu.in | Univ@123 |

Emails are printed in the backend terminal unless SMTP settings are filled in `.env`.

---

## REST API (64 endpoints)

All under `/api`. JSON in and out. Errors are always `{ "error": "...", "fields"?: [...] }`.

| Group | Endpoints |
|---|---|
| Health | `GET /health` |
| Auth | `POST /auth/register` · `POST /auth/login` · `POST /auth/logout` · `GET /auth/me` · `GET /auth/session` · `POST /auth/change-password` · `POST /auth/forgot-password` · `POST /auth/reset-password` |
| Meta | `GET /meta/states` · `GET /meta/registration-options` · `GET /meta/income-sources` |
| University (role UNIVERSITY) | profile (GET, PATCH) · departments (GET, POST) · users (GET, POST) · transactions (GET with filters and pages, POST) · `POST /transactions/:id/credit-note` · `GET /breakdown` · tax-records (GET list, GET :id) · payments (GET, POST) · alerts (GET, unread-count, read-all, :id/read) · notices (GET, :id/respond) · anomalies (GET) · stats: overview, monthly-revenue, monthly-tax, tax-status, payments, income-by-type |
| Admin (role ADMIN) | stats: overview, monthly-collection · compliance · universities (list, :id, bill detail, breakdown, approve, reject, suspend, reactivate) · payments (list, :id/verify) · notices (list, create, close) · anomalies (list, update) · tax-rules (list, audit, update) · due-dates/extend · jobs/run-alerts · admins (list, create) |

## Security

- Passwords hashed with **bcrypt** (cost 10). Universities choose their own; there's a strong-password policy.
- **JWT in an httpOnly, SameSite=Lax cookie**: JavaScript can't read it (XSS) and it isn't sent on cross-site POSTs (CSRF).
- A token version in the JWT means a password change or reset logs out every other device. A suspended university is blocked on its next request.
- Role checks on every API route. Every university query is scoped to the university ID **from the token**, never from the request.
- Zod validation on every input; parameterised SQL everywhere (no SQL injection).
- Login rate limit (10 failed attempts / 15 min); same message for a wrong email or a wrong password.
- Forgot-password tokens: random, stored only as SHA-256, valid 30 minutes, single use.
- helmet security headers, CORS limited to the frontend, 100 kB body limit.
- The app's MySQL user can't DELETE (except reset tokens) or DROP; income entries can't be edited or deleted (credit notes instead).
