// The ONE place that turns any error into an HTTP response.
// Express 5 sends errors thrown in async routes here automatically.
import { ZodError } from 'zod';
import { HttpError } from '../utils/httpError.js';

export function notFound(req, res) {
  res.status(404).json({ error: `No route for ${req.method} ${req.originalUrl}` });
}

// eslint-disable-next-line no-unused-vars
export function errorHandler(err, req, res, next) {
  // 1. bad input caught by a Zod schema -> say which fields are wrong
  if (err instanceof ZodError) {
    return res.status(400).json({
      error: 'Please correct the highlighted fields',
      fields: err.issues.map((i) => ({ field: i.path.join('.'), message: i.message })),
    });
  }

  // 2. errors we threw on purpose
  if (err instanceof HttpError) {
    return res.status(err.status).json({ error: err.message });
  }

  // 3. invalid JSON in the request body
  if (err.type === 'entity.parse.failed') {
    return res.status(400).json({ error: 'Request body is not valid JSON' });
  }

  // 4. MySQL errors
  if (err.sqlState === '45000') {
    // our own SIGNAL from a procedure / trigger: the message is meant for the user
    return res.status(400).json({ error: err.sqlMessage });
  }
  if (err.code === 'ER_DUP_ENTRY') {
    return res.status(409).json({ error: duplicateMessage(err.sqlMessage) });
  }
  if (err.code === 'ER_CHECK_CONSTRAINT_VIOLATED') {
    const name = err.sqlMessage.match(/'([^']+)'/)?.[1];
    return res.status(400).json({ error: CHECK_MESSAGES[name] ?? 'A value breaks a database rule' });
  }
  if (err.code === 'ER_NO_REFERENCED_ROW_2') {
    return res.status(400).json({ error: 'A referenced record does not exist' });
  }

  // 5. anything else is a bug: log it, but never send internal details to the client
  console.error(err);
  res.status(500).json({ error: 'Something went wrong on the server' });
}

// readable messages for the named CHECK constraints in 01_schema.sql
const CHECK_MESSAGES = {
  chk_gstin_format: 'GSTIN format is invalid',
  chk_tax_rate_range: 'GST rate must be between 0 and 100',
  chk_tds_rate_range: 'TDS rate must be between 0 and 100',
  chk_exempt_no_gst: 'Exempt or non-supply income cannot have a GST rate above 0',
  chk_user_role_univ: 'A university user must belong to a university; an admin must not',
  chk_trans_amount: 'Amount must be more than 0',
  chk_payment_amount: 'Payment amount must be more than 0',
  chk_beneficiaries: 'Number of students must be more than 0',
  chk_stay_days: 'Days covered must be more than 0',
  chk_tds_not_negative: 'TDS cannot be negative',
  chk_credit_note_link: 'A credit note must point to the invoice it corrects',
  chk_payer_gstin: 'Payer GSTIN format is invalid',
  chk_period_first_day: 'A tax period must start on the 1st of a month',
};

function duplicateMessage(sqlMessage = '') {
  if (sqlMessage.includes('GSTIN')) return 'This GSTIN is already registered';
  if (sqlMessage.includes('Email')) return 'This email is already registered';
  if (sqlMessage.includes('university.Name')) return 'A university with this name is already registered';
  if (sqlMessage.includes('Reference_No')) return 'This payment reference (CIN) was already used';
  if (sqlMessage.includes('department')) return 'This department already exists';
  return 'This record already exists';
}
