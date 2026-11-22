// /api/auth : register, login, logout, who-am-I, change / reset password
import { Router } from 'express';
import bcrypt from 'bcryptjs';
import crypto from 'node:crypto';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';
import { env } from '../config/env.js';
import { query, withTransaction } from '../config/db.js';
import { validate } from '../middleware/validate.js';
import { requireAuth, issueToken, cookieOptions, COOKIE_NAME } from '../middleware/auth.js';
import { HttpError } from '../utils/httpError.js';
import { gstin, password } from '../utils/schemas.js';
import { sendMail } from '../services/mailer.js';

const router = Router();
const BCRYPT_COST = 10;   // 2^10 rounds: slow on purpose, so guessing passwords is expensive

// Rate limits per IP address, per 15 minutes (stops password guessing and spam):
//   login: 10 FAILED attempts (successful logins don't count)
//   register / forgot / reset password: 20 requests
const limiter = (limit, skipSuccessfulRequests = false) => rateLimit({
  windowMs: 15 * 60 * 1000,
  limit,
  skipSuccessfulRequests,
  standardHeaders: 'draft-8',
  legacyHeaders: false,
  message: { error: 'Too many attempts. Try again in 15 minutes' },
});
const loginLimiter = limiter(10, true);
const authLimiter = limiter(20);

// ---------------------------------------------------------------------
// POST /api/auth/register  - a university signs up (status PENDING)
// ---------------------------------------------------------------------
const registerSchema = z.object({
  universityName: z.string().trim().min(3).max(150),
  gstin,
  institutionType: z.enum(['Central', 'State', 'Deemed', 'Private']),
  itExemption: z
    .enum(['10(23C)(iiiab) - Govt funded', '10(23C)(iiiad) - Receipts up to 5 crore',
           '10(23C)(vi) - Approved institution', '12AB - Registered trust', 'None'])
    .default('None'),
  address: z.string().trim().max(255).optional(),
  city: z.string().trim().max(80).optional(),
  state: z.string().trim().min(2).max(60),
  contactPerson: z.string().trim().min(2).max(100),
  phone: z.string().regex(/^[6-9]\d{9}$/, 'Enter a 10-digit Indian mobile number').optional(),
  email: z.email().max(120).toLowerCase(),
  password,
});

router.post('/register', authLimiter, validate(registerSchema), async (req, res) => {
  const d = req.valid.body;
  const hash = await bcrypt.hash(d.password, BCRYPT_COST);

  // two rows, one transaction: never a university without a login or vice versa
  await withTransaction(async (conn) => {
    const [uni] = await conn.query(
      `INSERT INTO university (Name, GSTIN, Institution_Type, IT_Exemption, Address, City, State,
                               Contact_Person, Phone, Email)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [d.universityName, d.gstin, d.institutionType, d.itExemption, d.address ?? null,
       d.city ?? null, d.state, d.contactPerson, d.phone ?? null, d.email]
    );
    await conn.query(
      `INSERT INTO users (Name, Email, Password_Hash, Role, Univ_ID) VALUES (?, ?, ?, 'UNIVERSITY', ?)`,
      [d.contactPerson, d.email, hash, uni.insertId]
    );
  });

  sendMail({
    to: d.email,
    subject: 'Registration received - University Tax Compliance Portal',
    text: `Dear ${d.contactPerson},\n\nWe have received the registration of ${d.universityName} (GSTIN ${d.gstin}).\nThe tax office will verify your details. You can log in once it is approved.\n`,
  });

  res.status(201).json({
    message: 'Registration received. You can log in after the tax office approves it.',
  });
});

// ---------------------------------------------------------------------
// POST /api/auth/login
// ---------------------------------------------------------------------
const loginSchema = z.object({
  email: z.email().toLowerCase(),
  password: z.string().min(1).max(72),
});

// a real bcrypt hash used when the email doesn't exist, so the response time is
// the same either way (an attacker can't tell which emails are registered)
const DUMMY_HASH = '$2b$10$qTalJ5/zu8ZREep7M2gh2eYhVMqeXiy84iIm3gbjUr2udzRFjUn..';

router.post('/login', loginLimiter, validate(loginSchema), async (req, res) => {
  const { email, password: plain } = req.valid.body;

  const [user] = await query(
    `SELECT u.*, un.Name AS University, un.Status AS University_Status, un.Status_Reason
     FROM users u LEFT JOIN university un ON un.Univ_ID = u.Univ_ID
     WHERE u.Email = ?`,
    [email]
  );

  const ok = await bcrypt.compare(plain, user?.Password_Hash ?? DUMMY_HASH);
  if (!user || !ok) throw new HttpError(401, 'Invalid email or password');   // same message for both

  if (user.Role === 'UNIVERSITY') {
    const status = user.University_Status;
    if (status === 'PENDING') throw new HttpError(403, 'Your registration is waiting for approval by the tax office');
    if (status === 'REJECTED') throw new HttpError(403, `Your registration was rejected: ${user.Status_Reason}`);
    if (status === 'SUSPENDED') throw new HttpError(403, `Your account is suspended: ${user.Status_Reason}`);
  }

  issueToken(res, user);
  await query('UPDATE users SET Last_Login = NOW() WHERE User_ID = ?', [user.User_ID]);

  res.json({
    user: {
      id: user.User_ID, name: user.Name, email: user.Email, role: user.Role,
      univId: user.Univ_ID, university: user.University,
    },
  });
});

// ---------------------------------------------------------------------
// POST /api/auth/logout   GET /api/auth/me
// ---------------------------------------------------------------------
router.post('/logout', (req, res) => {
  const { maxAge, ...opts } = cookieOptions();   // same options, minus maxAge
  res.clearCookie(COOKIE_NAME, opts);
  res.json({ message: 'Logged out' });
});

router.get('/me', requireAuth, (req, res) => {
  res.json({ user: req.user });
});

// Like /me, but "not logged in" is a normal answer (200, user: null), not an error.
// The React app calls this once on page load to find out if a session exists.
router.get('/session', (req, res, next) => {
  if (!req.cookies?.[COOKIE_NAME]) return res.json({ user: null });
  requireAuth(req, res, (err) => (err ? res.json({ user: null }) : res.json({ user: req.user })));
});

// ---------------------------------------------------------------------
// POST /api/auth/change-password  - also logs out every OTHER device
// ---------------------------------------------------------------------
const changeSchema = z.object({
  currentPassword: z.string().min(1).max(72),
  newPassword: password,
});

router.post('/change-password', requireAuth, validate(changeSchema), async (req, res) => {
  const { currentPassword, newPassword } = req.valid.body;
  const [user] = await query('SELECT * FROM users WHERE User_ID = ?', [req.user.id]);

  if (!(await bcrypt.compare(currentPassword, user.Password_Hash))) {
    throw new HttpError(400, 'Current password is wrong');
  }

  const hash = await bcrypt.hash(newPassword, BCRYPT_COST);
  await query(
    'UPDATE users SET Password_Hash = ?, Token_Version = Token_Version + 1 WHERE User_ID = ?',
    [hash, user.User_ID]
  );

  // new token for THIS device; every older token now has the wrong version
  issueToken(res, { ...user, Token_Version: user.Token_Version + 1 });
  res.json({ message: 'Password changed. You have been logged out on other devices.' });
});

// ---------------------------------------------------------------------
// POST /api/auth/forgot-password  - emails a one-time link (valid 30 min)
// ---------------------------------------------------------------------
router.post('/forgot-password', authLimiter, validate(z.object({ email: z.email().toLowerCase() })),
  async (req, res) => {
    const [user] = await query('SELECT User_ID, Name, Email FROM users WHERE Email = ?', [req.valid.body.email]);

    if (user) {
      const token = crypto.randomBytes(32).toString('hex');                 // sent to the user
      const tokenHash = crypto.createHash('sha256').update(token).digest('hex'); // stored
      await query('DELETE FROM password_reset WHERE User_ID = ?', [user.User_ID]);
      await query(
        `INSERT INTO password_reset (User_ID, Token_Hash, Expires_At)
         VALUES (?, ?, NOW() + INTERVAL 30 MINUTE)`,
        [user.User_ID, tokenHash]
      );
      sendMail({
        to: user.Email,
        subject: 'Reset your password',
        text: `Hi ${user.Name},\n\nOpen this link within 30 minutes to set a new password:\n${env.CLIENT_URL}/reset-password?token=${token}\n\nIf you did not ask for this, ignore this email.`,
      });
    }

    // the same answer whether or not the email exists
    res.json({ message: 'If this email is registered, a reset link has been sent.' });
  });

// ---------------------------------------------------------------------
// POST /api/auth/reset-password
// ---------------------------------------------------------------------
const resetSchema = z.object({
  token: z.string().regex(/^[a-f0-9]{64}$/, 'Invalid reset link'),
  newPassword: password,
});

router.post('/reset-password', authLimiter, validate(resetSchema), async (req, res) => {
  const tokenHash = crypto.createHash('sha256').update(req.valid.body.token).digest('hex');

  const [row] = await query(
    `SELECT Reset_ID, User_ID FROM password_reset
     WHERE Token_Hash = ? AND Used_At IS NULL AND Expires_At > NOW()`,
    [tokenHash]
  );
  if (!row) throw new HttpError(400, 'This reset link is invalid or has expired');

  const hash = await bcrypt.hash(req.valid.body.newPassword, BCRYPT_COST);
  await withTransaction(async (conn) => {
    await conn.query(
      'UPDATE users SET Password_Hash = ?, Token_Version = Token_Version + 1 WHERE User_ID = ?',
      [hash, row.User_ID]
    );
    await conn.query('UPDATE password_reset SET Used_At = NOW() WHERE Reset_ID = ?', [row.Reset_ID]);
  });

  res.json({ message: 'Password updated. Please log in.' });
});

export default router;
