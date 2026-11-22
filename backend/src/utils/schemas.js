// Small reusable Zod building blocks used by several routes.
import { z } from 'zod';
import { isValidGSTIN } from './gstin.js';
import { financialYearOf, todayIST } from './dates.js';

// 'YYYY-MM-DD' that is a real calendar date
export const dateString = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, 'Use the format YYYY-MM-DD')
  .refine((s) => !Number.isNaN(Date.parse(s)) && new Date(s).toISOString().startsWith(s),
    'Not a real date');

// money: positive, at most 2 decimals, below 10 lakh crore
export const money = z.coerce
  .number()
  .positive('Must be more than 0')
  .max(1e13, 'Amount is too large')
  .refine((n) => Math.abs(n * 100 - Math.round(n * 100)) < 1e-6, 'At most 2 decimal places')
  .transform((n) => Math.round(n * 100) / 100);

export const gstin = z
  .string()
  .trim()
  .toUpperCase()
  .refine(isValidGSTIN, 'Invalid GSTIN (format or check digit)');

export const idParam = z.object({ id: z.coerce.number().int().positive() });

// ?fy=2025-26  (defaults to the current financial year)
export const fyQuery = z.object({
  fy: z
    .string()
    .regex(/^\d{4}-\d{2}$/, 'Use the format 2025-26')
    .default(() => financialYearOf(todayIST())),
});

export const password = z
  .string()
  .min(8, 'At least 8 characters')
  .max(72, 'At most 72 characters')            // bcrypt only uses the first 72 bytes
  .regex(/[a-z]/, 'Needs a lowercase letter')
  .regex(/[A-Z]/, 'Needs an uppercase letter')
  .regex(/[0-9]/, 'Needs a number')
  .regex(/[^A-Za-z0-9]/, 'Needs a special character');
