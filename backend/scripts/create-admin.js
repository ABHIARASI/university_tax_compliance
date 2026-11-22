// Creates a tax-office ADMIN account from the terminal:
//     npm run create-admin
// It asks for the name, email and password (nothing is shown while the
// password is typed), checks the password is strong, and saves ONLY a bcrypt hash.
// No password is ever written in code, a file or the Git history.
import readline from 'node:readline';
import { stdin, stdout } from 'node:process';
import bcrypt from 'bcryptjs';
import { z } from 'zod';
import { pool } from '../src/config/db.js';
import { password as passwordRule } from '../src/utils/schemas.js';

const rl = readline.createInterface({ input: stdin, output: stdout, terminal: stdin.isTTY });
const lines = rl[Symbol.asyncIterator]();   // read answers one line at a time

// While a password is typed, readline's echo is switched off, so nothing
// appears on screen (like the Linux `sudo` prompt).
let hidden = false;
const echo = rl._writeToOutput.bind(rl);
rl._writeToOutput = (text) => { if (!hidden) echo(text); };

async function ask(question, isPassword = false) {
  stdout.write(question);
  hidden = isPassword;
  const { value = '' } = await lines.next();
  hidden = false;
  if (isPassword && stdin.isTTY) stdout.write('\n');
  return isPassword ? value : value.trim();
}

const schema = z.object({
  name: z.string().min(2, 'Name: at least 2 characters').max(100),
  email: z.email('Email: not a valid email').toLowerCase(),
  password: passwordRule,
});

try {
  console.log('\nCreate a tax-office ADMIN account\n');
  const name = await ask('Full name: ');
  const email = await ask('Email:     ');
  const password = await ask('Password:  ', true);
  const confirm = await ask('Confirm:   ', true);

  if (password !== confirm) throw new Error('The two passwords do not match');

  const parsed = schema.safeParse({ name, email, password });
  if (!parsed.success) {
    throw new Error(parsed.error.issues.map((i) => `${i.path[0]}: ${i.message}`).join('\n'));
  }

  const hash = await bcrypt.hash(parsed.data.password, 10);
  await pool.query(
    `INSERT INTO users (Name, Email, Password_Hash, Role) VALUES (?, ?, ?, 'ADMIN')`,
    [parsed.data.name, parsed.data.email, hash]
  );
  console.log(`\nAdmin ${parsed.data.email} created. You can log in now.\n`);
} catch (err) {
  const message = err.code === 'ER_DUP_ENTRY' ? 'This email already has an account' : err.message;
  console.error(`\nNot created:\n${message}\n`);
  process.exitCode = 1;
} finally {
  rl.close();
  await pool.end();
}
