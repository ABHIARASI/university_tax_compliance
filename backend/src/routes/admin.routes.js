// /api/admin : everything the tax office (ADMIN) can do
import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { z } from 'zod';
import { pool, query, callProcedure } from '../config/db.js';
import { requireAuth, requireRole } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { HttpError } from '../utils/httpError.js';
import { todayIST } from '../utils/dates.js';
import { dateString, idParam, fyQuery, password } from '../utils/schemas.js';
import * as reports from '../services/reports.js';
import { sendMail } from '../services/mailer.js';
import { runDailyAlerts } from '../jobs/alerts.job.js';

const router = Router();
router.use(requireAuth, requireRole('ADMIN'));

// ---------------- dashboard ----------------

router.get('/stats/overview', async (req, res) => {
  const today = todayIST();
  const [counts] = await query(
    `SELECT
       (SELECT COUNT(*) FROM university WHERE Status = 'PENDING')   AS Pending_Registrations,
       (SELECT COUNT(*) FROM university WHERE Status = 'APPROVED')  AS Active_Universities,
       (SELECT COUNT(*) FROM university WHERE Status = 'SUSPENDED') AS Suspended_Universities,
       (SELECT COUNT(*) FROM payment WHERE Status = 'Pending')      AS Payments_To_Verify,
       (SELECT COUNT(*) FROM anomaly WHERE Status = 'Open')         AS Open_Anomalies,
       (SELECT COUNT(*) FROM notice  WHERE Status = 'Responded')    AS Notices_Awaiting_Review,
       (SELECT IFNULL(SUM(Tax_Due), 0)  FROM tax_record)            AS Total_GST_Due,
       (SELECT IFNULL(SUM(Tax_Paid), 0) FROM tax_record)            AS Total_GST_Collected`
  );
  const compliance = await callProcedure('Overdue_Report', [today]);
  const split = { COMPLIANT: 0, DUE_SOON: 0, OVERDUE: 0 };
  let taxOutstanding = 0;
  let interestOutstanding = 0;
  for (const u of compliance) {
    split[u.Compliance] += 1;
    taxOutstanding += u.Tax_Outstanding;
    interestOutstanding += u.Interest_Outstanding;
  }
  res.json({
    ...counts,
    Tax_Outstanding: Math.round(taxOutstanding * 100) / 100,
    Interest_Outstanding: Math.round(interestOutstanding * 100) / 100,
    Compliance_Split: split,
  });
});

// GST due vs collected per month, all universities together (bar chart)
router.get('/stats/monthly-collection', validate(fyQuery, 'query'), async (req, res) => {
  res.json(await query(
    `SELECT DATE_FORMAT(Period_Start, '%b %y') AS Month, Period_Start,
            SUM(Tax_Due) AS Tax_Due, SUM(Tax_Paid) AS Tax_Paid,
            SUM(CGST) AS CGST, SUM(SGST) AS SGST, SUM(IGST) AS IGST
     FROM tax_record WHERE Financial_Year = ?
     GROUP BY Period_Start ORDER BY Period_Start`,
    [req.valid.query.fy]
  ));
});

router.get('/compliance', async (req, res) => {
  res.json(await callProcedure('Overdue_Report', [todayIST()]));
});

// ---------------- universities ----------------

const statusQuery = z.object({
  status: z.enum(['PENDING', 'APPROVED', 'REJECTED', 'SUSPENDED']).optional(),
});

router.get('/universities', validate(statusQuery, 'query'), async (req, res) => {
  const { status } = req.valid.query;
  res.json(await query(
    `SELECT Univ_ID, Name, GSTIN, PAN, Institution_Type, IT_Exemption, City, State,
            Contact_Person, Phone, Email, Status, Status_Reason, Registered_At, Reviewed_At,
            IF(Status = 'APPROVED', Compliance_Status(Univ_ID, ?), NULL) AS Compliance
     FROM university ${status ? 'WHERE Status = ?' : ''}
     ORDER BY FIELD(Status, 'PENDING', 'APPROVED', 'SUSPENDED', 'REJECTED'), Registered_At DESC`,
    status ? [todayIST(), status] : [todayIST()]
  ));
});

router.get('/universities/:id', validate(idParam, 'params'), validate(fyQuery, 'query'),
  async (req, res) => {
    const id = req.valid.params.id;
    const [uni] = await query('SELECT * FROM university WHERE Univ_ID = ?', [id]);
    if (!uni) throw new HttpError(404, 'University not found');

    const today = todayIST();
    const fy = req.valid.query.fy;
    res.json({
      university: uni,
      overview: uni.Status === 'APPROVED' ? await reports.getOverview(id, fy, today) : null,
      bills: await reports.getBills(id, fy, today),
      monthlyRevenue: await reports.getMonthlyRevenue(id, fy),
      incomeByType: await reports.getIncomeByType(id, fy),
    });
  });

router.get('/universities/:id/tax-records/:taxId',
  validate(z.object({ id: z.coerce.number().int(), taxId: z.coerce.number().int() }), 'params'),
  async (req, res) => {
    const detail = await reports.getBillDetail(req.valid.params.id, req.valid.params.taxId, todayIST());
    if (!detail) throw new HttpError(404, 'Bill not found');
    res.json(detail);
  });

router.get('/universities/:id/breakdown', validate(idParam, 'params'),
  validate(z.object({ from: dateString, to: dateString }), 'query'),
  async (req, res) => {
    res.json(await callProcedure('University_Income_Breakdown',
      [req.valid.params.id, req.valid.query.from, req.valid.query.to]));
  });

async function universityContact(id) {
  const [u] = await query('SELECT Name, Email, Contact_Person FROM university WHERE Univ_ID = ?', [id]);
  return u;
}

router.patch('/universities/:id/approve', validate(idParam, 'params'), async (req, res) => {
  await callProcedure('Approve_University', [req.valid.params.id, req.user.id]);
  const u = await universityContact(req.valid.params.id);
  sendMail({
    to: u.Email,
    subject: 'Your registration is approved',
    text: `Dear ${u.Contact_Person},\n\n${u.Name} is now approved on the University Tax Compliance Portal. You can log in with the email and password you registered with.\n`,
  });
  res.json({ message: `${u.Name} approved` });
});

const reasonSchema = z.object({ reason: z.string().trim().min(5).max(255) });

router.patch('/universities/:id/reject', validate(idParam, 'params'), validate(reasonSchema),
  async (req, res) => {
    await callProcedure('Reject_University', [req.valid.params.id, req.user.id, req.valid.body.reason]);
    const u = await universityContact(req.valid.params.id);
    sendMail({
      to: u.Email,
      subject: 'Your registration was not approved',
      text: `Dear ${u.Contact_Person},\n\nThe registration of ${u.Name} was rejected.\nReason: ${req.valid.body.reason}\n`,
    });
    res.json({ message: `${u.Name} rejected` });
  });

router.patch('/universities/:id/suspend', validate(idParam, 'params'), validate(reasonSchema),
  async (req, res) => {
    const result = await query(
      `UPDATE university SET Status = 'SUSPENDED', Status_Reason = ?, Reviewed_By = ?, Reviewed_At = NOW()
       WHERE Univ_ID = ? AND Status = 'APPROVED'`,
      [req.valid.body.reason, req.user.id, req.valid.params.id]
    );
    if (result.affectedRows === 0) throw new HttpError(400, 'Only an APPROVED university can be suspended');
    res.json({ message: 'University suspended. Its users are logged out immediately.' });
  });

router.patch('/universities/:id/reactivate', validate(idParam, 'params'), async (req, res) => {
  const result = await query(
    `UPDATE university SET Status = 'APPROVED', Status_Reason = NULL, Reviewed_By = ?, Reviewed_At = NOW()
     WHERE Univ_ID = ? AND Status = 'SUSPENDED'`,
    [req.user.id, req.valid.params.id]
  );
  if (result.affectedRows === 0) throw new HttpError(400, 'Only a SUSPENDED university can be reactivated');
  res.json({ message: 'University reactivated' });
});

// ---------------- payments ----------------

router.get('/payments',
  validate(z.object({ status: z.enum(['Pending', 'Verified', 'Rejected']).optional() }), 'query'),
  async (req, res) => {
    const { status } = req.valid.query;
    res.json(await query(
      `SELECT p.*, u.Univ_ID, u.Name AS University, DATE_FORMAT(tr.Period_Start, '%b %Y') AS Period,
              tr.Tax_Due, tr.Tax_Paid, GREATEST(tr.Tax_Due - tr.Tax_Paid, 0) AS Tax_Outstanding,
              v.Name AS Verified_By_Name
       FROM payment p
       JOIN tax_record tr ON tr.Tax_ID = p.Tax_ID
       JOIN university u  ON u.Univ_ID = tr.Univ_ID
       LEFT JOIN users v  ON v.User_ID = p.Verified_By
       ${status ? 'WHERE p.Status = ?' : ''}
       ORDER BY FIELD(p.Status, 'Pending', 'Rejected', 'Verified'), p.Payment_Date DESC
       LIMIT 500`,
      status ? [status] : []
    ));
  });

const verifySchema = z.object({
  decision: z.enum(['Verified', 'Rejected']),
  remarks: z.string().trim().max(255).optional(),
});

router.patch('/payments/:id/verify', validate(idParam, 'params'), validate(verifySchema),
  async (req, res) => {
    const { decision, remarks } = req.valid.body;
    await callProcedure('Verify_Payment', [req.valid.params.id, req.user.id, decision, remarks ?? null]);
    const anomalies = await query(
      'SELECT Rule_Code, Details FROM anomaly WHERE Payment_ID = ?', [req.valid.params.id]);
    res.json({ message: `Payment ${decision.toLowerCase()}`, anomalies });
  });

// ---------------- notices ----------------

router.get('/notices',
  validate(z.object({ status: z.enum(['Open', 'Responded', 'Closed']).optional() }), 'query'),
  async (req, res) => {
    const { status } = req.valid.query;
    res.json(await query(
      `SELECT n.*, u.Name AS University, DATE_FORMAT(tr.Period_Start, '%b %Y') AS Period
       FROM notice n
       JOIN university u ON u.Univ_ID = n.Univ_ID
       LEFT JOIN tax_record tr ON tr.Tax_ID = n.Tax_ID
       ${status ? 'WHERE n.Status = ?' : ''}
       ORDER BY FIELD(n.Status, 'Responded', 'Open', 'Closed'), n.Issued_At DESC`,
      status ? [status] : []
    ));
  });

const noticeSchema = z.object({
  univId: z.coerce.number().int().positive(),
  taxId: z.coerce.number().int().positive().optional(),
  anomalyId: z.coerce.number().int().positive().optional(),
  type: z.enum(['Reminder', 'Demand', 'Anomaly Query', 'General']),
  subject: z.string().trim().min(5).max(150),
  message: z.string().trim().min(10).max(5000),
  responseDue: dateString.optional(),
});

router.post('/notices', validate(noticeSchema), async (req, res) => {
  const d = req.valid.body;

  // the bill / anomaly must belong to the same university as the notice
  if (d.taxId) {
    const [t] = await query('SELECT 1 FROM tax_record WHERE Tax_ID = ? AND Univ_ID = ?', [d.taxId, d.univId]);
    if (!t) throw new HttpError(400, 'That bill does not belong to this university');
  }
  if (d.anomalyId) {
    const [a] = await query('SELECT 1 FROM anomaly WHERE Anomaly_ID = ? AND Univ_ID = ?', [d.anomalyId, d.univId]);
    if (!a) throw new HttpError(400, 'That anomaly does not belong to this university');
  }

  const result = await query(
    `INSERT INTO notice (Univ_ID, Tax_ID, Anomaly_ID, Type, Subject, Message, Issued_By, Response_Due)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    [d.univId, d.taxId ?? null, d.anomalyId ?? null, d.type, d.subject, d.message,
     req.user.id, d.responseDue ?? null]
  );

  const u = await universityContact(d.univId);
  if (u) {
    sendMail({
      to: u.Email,
      subject: `Notice from the tax office: ${d.subject}`,
      text: `${d.message}\n\n${d.responseDue ? `Please respond by ${d.responseDue}.` : ''}\nLog in to the portal to reply.`,
    });
  }
  res.status(201).json({ Notice_ID: result.insertId, message: 'Notice sent' });
});

router.patch('/notices/:id/close', validate(idParam, 'params'), async (req, res) => {
  const result = await query(
    `UPDATE notice SET Status = 'Closed' WHERE Notice_ID = ? AND Status <> 'Closed'`,
    [req.valid.params.id]
  );
  if (result.affectedRows === 0) throw new HttpError(400, 'Notice not found or already closed');
  res.json({ message: 'Notice closed' });
});

// ---------------- anomalies ----------------

router.get('/anomalies',
  validate(z.object({
    status: z.enum(['Open', 'Reviewed', 'Dismissed']).optional(),
    rule: z.enum(['CASH_LIMIT', 'SPIKE', 'DUPLICATE', 'OVERPAYMENT', 'TDS_MISMATCH']).optional(),
  }), 'query'),
  async (req, res) => {
    const { status, rule } = req.valid.query;
    const where = [];
    const params = [];
    if (status) { where.push('a.Status = ?'); params.push(status); }
    if (rule)   { where.push('a.Rule_Code = ?'); params.push(rule); }
    res.json(await query(
      `SELECT a.*, u.Name AS University, t.Trans_Date, t.Amount AS Trans_Amount, t.Mode,
              t.Payer_Name, r.Name AS Reviewed_By_Name
       FROM anomaly a
       JOIN university u ON u.Univ_ID = a.Univ_ID
       LEFT JOIN revenue_transaction t ON t.Trans_ID = a.Trans_ID
       LEFT JOIN users r ON r.User_ID = a.Reviewed_By
       ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
       ORDER BY FIELD(a.Status, 'Open', 'Reviewed', 'Dismissed'),
                FIELD(a.Severity, 'High', 'Medium', 'Low'), a.Detected_At DESC`,
      params
    ));
  });

router.patch('/anomalies/:id', validate(idParam, 'params'),
  validate(z.object({ status: z.enum(['Reviewed', 'Dismissed']) })),
  async (req, res) => {
    const result = await query(
      'UPDATE anomaly SET Status = ?, Reviewed_By = ? WHERE Anomaly_ID = ?',
      [req.valid.body.status, req.user.id, req.valid.params.id]
    );
    if (result.affectedRows === 0) throw new HttpError(404, 'Anomaly not found');
    res.json({ message: `Marked as ${req.valid.body.status.toLowerCase()}` });
  });

// ---------------- tax rules ----------------

router.get('/tax-rules', async (req, res) => {
  res.json(await query(
    `SELECT r.*, (SELECT COUNT(*) FROM income_source s WHERE s.TaxRule_ID = r.TaxRule_ID) AS Sources
     FROM tax_rule r ORDER BY r.TaxRule_ID`
  ));
});

router.get('/tax-rules/audit', async (req, res) => {
  res.json(await query(
    `SELECT a.*, r.Income_Type, u.Name AS Changed_By_Name
     FROM tax_rule_audit a
     JOIN tax_rule r ON r.TaxRule_ID = a.TaxRule_ID
     LEFT JOIN users u ON u.User_ID = a.Changed_By
     ORDER BY a.Changed_At DESC`
  ));
});

const ruleSchema = z.object({
  taxRate: z.coerce.number().min(0).max(100).optional(),
  tdsRate: z.coerce.number().min(0).max(100).optional(),
  conditions: z.string().trim().max(255).optional(),
  legalBasis: z.string().trim().min(5).max(255).optional(),
});

// The audit trigger needs to know WHO changed the rate. A trigger can't see the
// web login, so we set a MySQL session variable first - on the SAME connection
// as the UPDATE (a pool could otherwise give the two queries different connections).
router.patch('/tax-rules/:id', validate(idParam, 'params'), validate(ruleSchema), async (req, res) => {
  const d = req.valid.body;
  const conn = await pool.getConnection();
  try {
    await conn.query('SET @app_user_id = ?', [req.user.id]);
    const [result] = await conn.query(
      `UPDATE tax_rule SET Tax_Rate = COALESCE(?, Tax_Rate), TDS_Rate = COALESCE(?, TDS_Rate),
              Conditions = COALESCE(?, Conditions), Legal_Basis = COALESCE(?, Legal_Basis)
       WHERE TaxRule_ID = ?`,
      [d.taxRate ?? null, d.tdsRate ?? null, d.conditions ?? null, d.legalBasis ?? null, req.valid.params.id]
    );
    if (result.affectedRows === 0) throw new HttpError(404, 'Tax rule not found');
  } finally {
    await conn.query('SET @app_user_id = NULL');   // don't leak it to the next user of this connection
    conn.release();
  }
  res.json({ message: 'Tax rule updated. It applies to new income only.' });
});

// ---------------- due dates and the alert job ----------------

router.post('/due-dates/extend',
  validate(z.object({ periodStart: dateString, newDueDate: dateString })),
  async (req, res) => {
    const [row] = await callProcedure('Extend_Due_Date',
      [req.valid.body.periodStart, req.valid.body.newDueDate]);
    res.json({ message: `Due date extended for ${row.Bills_Updated} bill(s)` });
  });

// run the daily alert job now (optionally "as if" on another date, for testing/demo)
router.post('/jobs/run-alerts', validate(z.object({ date: dateString.optional() })), async (req, res) => {
  res.json(await runDailyAlerts(req.valid.body.date));
});

// ---------------- admin accounts ----------------

router.get('/admins', async (req, res) => {
  res.json(await query(
    `SELECT User_ID, Name, Email, Last_Login, Created_At FROM users WHERE Role = 'ADMIN' ORDER BY User_ID`
  ));
});

router.post('/admins',
  validate(z.object({ name: z.string().trim().min(2).max(100), email: z.email().toLowerCase(), password })),
  async (req, res) => {
    const d = req.valid.body;
    const hash = await bcrypt.hash(d.password, 10);
    const result = await query(
      `INSERT INTO users (Name, Email, Password_Hash, Role) VALUES (?, ?, ?, 'ADMIN')`,
      [d.name, d.email, hash]
    );
    res.status(201).json({ User_ID: result.insertId, Name: d.name, Email: d.email });
  });

export default router;
