// Reads settings from process.env (filled from .env by `node --env-file=.env`)
// and checks them ONCE at startup. A missing or wrong setting stops the server
// immediately with a clear message, instead of failing later in a request.
import { z } from 'zod';

const schema = z.object({
  PORT: z.coerce.number().int().positive().default(5000),
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  CLIENT_URL: z.url().default('http://localhost:5173'),

  DB_HOST: z.string().default('localhost'),
  DB_PORT: z.coerce.number().int().default(3306),
  DB_USER: z.string().min(1),
  DB_PASSWORD: z.string(),
  DB_NAME: z.string().default('university_tax'),

  JWT_SECRET: z.string().min(32, 'JWT_SECRET must be at least 32 characters'),
  JWT_EXPIRES_HOURS: z.coerce.number().positive().default(8),

  ALERT_CRON: z.string().default('0 9 * * *'),

  SMTP_HOST: z.string().optional().default(''),
  SMTP_PORT: z.coerce.number().int().default(587),
  SMTP_USER: z.string().optional().default(''),
  SMTP_PASS: z.string().optional().default(''),
  MAIL_FROM: z.string().default('Tax Portal <no-reply@taxportal.in>'),
});

const parsed = schema.safeParse(process.env);

if (!parsed.success) {
  console.error('Invalid settings in .env:');
  for (const issue of parsed.error.issues) {
    console.error(`  ${issue.path.join('.')}: ${issue.message}`);
  }
  process.exit(1);
}

export const env = parsed.data;
