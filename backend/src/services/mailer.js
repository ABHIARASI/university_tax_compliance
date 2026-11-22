// Sends emails with Nodemailer.
// No SMTP settings in .env (development) -> the email is printed in the terminal
// instead, so the app works without an email account.
// Email failures are logged but never break the request that triggered them.
import nodemailer from 'nodemailer';
import { env } from '../config/env.js';

const devMode = !env.SMTP_HOST;

const transporter = devMode
  ? nodemailer.createTransport({ jsonTransport: true })
  : nodemailer.createTransport({
      host: env.SMTP_HOST,
      port: env.SMTP_PORT,
      secure: env.SMTP_PORT === 465,
      auth: { user: env.SMTP_USER, pass: env.SMTP_PASS },
    });

export async function sendMail({ to, subject, text }) {
  try {
    await transporter.sendMail({ from: env.MAIL_FROM, to, subject, text });
    if (devMode) {
      console.log(`\n[email -> ${to}] ${subject}\n${text}\n`);
    }
    return true;
  } catch (err) {
    console.error(`Email to ${to} failed:`, err.message);
    return false;
  }
}
