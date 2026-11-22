// Entry point: start the HTTP server and the daily alert job.
import { app } from './app.js';
import { env } from './config/env.js';
import { pool } from './config/db.js';
import { startAlertScheduler } from './jobs/alerts.job.js';

try {
  await pool.query('SELECT 1');           // fail fast if MySQL is unreachable
} catch (err) {
  console.error(`Cannot connect to MySQL as ${env.DB_USER}@${env.DB_HOST}: ${err.message}`);
  process.exit(1);
}

const server = app.listen(env.PORT, () => {
  console.log(`API running on http://localhost:${env.PORT}`);
  startAlertScheduler();
});

// Ctrl+C: stop taking requests, close DB connections, then exit cleanly
process.on('SIGINT', () => {
  server.close(async () => {
    await pool.end();
    process.exit(0);
  });
});
