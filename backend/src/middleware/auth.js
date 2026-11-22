// Two middlewares that protect routes:
//   requireAuth          -> "are you logged in?"            (else 401)
//   requireRole('ADMIN') -> "are you allowed to do this?"   (else 403)
import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';
import { query } from '../config/db.js';
import { HttpError } from '../utils/httpError.js';

export const COOKIE_NAME = 'token';

export function cookieOptions() {
  return {
    httpOnly: true,                          // JavaScript in the page can't read it (stops XSS theft)
    sameSite: 'lax',                         // not sent on cross-site POSTs (stops CSRF)
    secure: env.NODE_ENV === 'production',   // HTTPS only in production
    maxAge: env.JWT_EXPIRES_HOURS * 60 * 60 * 1000,
    path: '/',
  };
}

// Create a signed JWT for a user and put it in the cookie
export function issueToken(res, user) {
  const token = jwt.sign(
    { sub: user.User_ID, role: user.Role, univId: user.Univ_ID, ver: user.Token_Version },
    env.JWT_SECRET,
    { expiresIn: `${env.JWT_EXPIRES_HOURS}h` }
  );
  res.cookie(COOKIE_NAME, token, cookieOptions());
}

export async function requireAuth(req, res, next) {
  const token = req.cookies?.[COOKIE_NAME];
  if (!token) return next(new HttpError(401, 'Please log in'));

  let payload;
  try {
    // checks the signature (not forged) and the expiry time
    payload = jwt.verify(token, env.JWT_SECRET);
  } catch {
    return next(new HttpError(401, 'Your session has expired. Please log in again'));
  }

  // One small lookup per request, so that:
  //   - a password change (Token_Version + 1) ends all old sessions at once
  //   - a SUSPENDED university is blocked immediately, not when the token expires
  const [user] = await query(
    `SELECT u.User_ID, u.Name, u.Email, u.Role, u.Univ_ID, u.Token_Version,
            un.Name AS University, un.Status AS University_Status
     FROM users u
     LEFT JOIN university un ON un.Univ_ID = u.Univ_ID
     WHERE u.User_ID = ?`,
    [payload.sub]
  );

  if (!user || user.Token_Version !== payload.ver) {
    return next(new HttpError(401, 'Your session has ended. Please log in again'));
  }
  if (user.Role === 'UNIVERSITY' && user.University_Status !== 'APPROVED') {
    return next(new HttpError(403, `Your university account is ${user.University_Status.toLowerCase()}`));
  }

  req.user = {
    id: user.User_ID,
    name: user.Name,
    email: user.Email,
    role: user.Role,
    univId: user.Univ_ID,
    university: user.University,
  };
  next();
}

export const requireRole = (...roles) => (req, res, next) => {
  if (!req.user || !roles.includes(req.user.role)) {
    return next(new HttpError(403, 'You do not have permission to do this'));
  }
  next();
};
