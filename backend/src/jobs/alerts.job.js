// The daily alert job.
//   1. CALL Generate_Daily_Alerts(today)  -> the SQL decides who gets which alert
//   2. email each university ONE summary of its new alerts, then mark them as emailed
// Runs every morning (node-cron) and once when the server starts.
import cron from 'node-cron';
import { query, callProcedure } from '../config/db.js';
import { env } from '../config/env.js';
import { todayIST } from '../utils/dates.js';
import { sendMail } from '../services/mailer.js';

export async function runDailyAlerts(date = todayIST()) {
  const [result] = await callProcedure('Generate_Daily_Alerts', [date]);

  const pending = await query(
    `SELECT a.Alert_ID, a.Message, u.Univ_ID, u.Name, u.Email, u.Contact_Person
     FROM alert a JOIN university u ON u.Univ_ID = a.Univ_ID
     WHERE a.Alert_Date = ? AND a.Email_Sent = FALSE
     ORDER BY u.Univ_ID, a.Alert_ID`,
    [date]
  );

  // group the alerts by university -> one email each
  const byUniversity = new Map();
  for (const row of pending) {
    if (!byUniversity.has(row.Univ_ID)) byUniversity.set(row.Univ_ID, { ...row, messages: [], ids: [] });
    byUniversity.get(row.Univ_ID).messages.push(row.Message);
    byUniversity.get(row.Univ_ID).ids.push(row.Alert_ID);
  }

  let emailed = 0;
  for (const u of byUniversity.values()) {
    const sent = await sendMail({
      to: u.Email,
      subject: `GST alerts for ${u.Name} - ${date}`,
      text: `Dear ${u.Contact_Person},\n\n${u.messages.map((m) => `- ${m}`).join('\n')}\n\nLog in to the portal to pay or view details.`,
    });
    if (sent) {
      await query('UPDATE alert SET Email_Sent = TRUE WHERE Alert_ID IN (?)', [u.ids]);
      emailed += 1;
    }
  }

  return { date, alertsForDay: result?.Alerts_For_Day ?? 0, universitiesEmailed: emailed };
}

export function startAlertScheduler() {
  cron.schedule(
    env.ALERT_CRON,
    () => {
      runDailyAlerts()
        .then((r) => console.log('Daily alerts:', r))
        .catch((err) => console.error('Daily alert job failed:', err));
    },
    { timezone: 'Asia/Kolkata' }
  );
  console.log(`Alert job scheduled: "${env.ALERT_CRON}" (Asia/Kolkata)`);

  // catch up at start-up, in case the server was off at 9 AM
  runDailyAlerts()
    .then((r) => console.log('Start-up alert run:', r))
    .catch((err) => console.error('Start-up alert run failed:', err));
}
