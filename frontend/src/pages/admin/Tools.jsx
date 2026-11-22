// Admin tools: run the daily alert job, extend a GST due date, manage admins.
import { useState } from 'react';
import { api } from '../../api/client.js';
import { useApi } from '../../hooks/useApi.js';
import { dateTime, todayISO } from '../../utils/format.js';
import { Alert, Button, Card, Field, Input, Loader, PageHeader, Table, fieldErrors } from '../../components/ui.jsx';
import { AddForm } from '../university/Settings.jsx';

export default function Tools() {
  const admins = useApi('/admin/admins');
  return (
    <>
      <PageHeader title="Tools" />
      <div className="grid gap-6 xl:grid-cols-2">
        <RunAlerts />
        <ExtendDueDate />
        <Card title="Admin accounts" className="xl:col-span-2">
          <Loader loading={admins.loading} error={admins.error}>
            <Table rowKey="User_ID" rows={admins.data} columns={[
              { key: 'Name', label: 'Name' }, { key: 'Email', label: 'Email' },
              { key: 'Last_Login', label: 'Last login', render: (r) => dateTime(r.Last_Login) },
            ]} />
            <AddForm
              fields={[
                { key: 'name', label: 'Name' },
                { key: 'email', label: 'Email', type: 'email' },
                { key: 'password', label: 'Password', type: 'password', hint: '8+ characters, upper, lower, number, symbol' },
              ]}
              submitLabel="Add admin"
              onSubmit={(body) => api.post('/admin/admins', body)}
              onDone={admins.reload}
            />
          </Loader>
        </Card>
      </div>
    </>
  );
}

function RunAlerts() {
  const [day, setDay] = useState(todayISO());
  const [result, setResult] = useState(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const run = async () => {
    setBusy(true);
    setError('');
    try { setResult(await api.post('/admin/jobs/run-alerts', { date: day })); }
    catch (err) { setError(err.message); }
    finally { setBusy(false); }
  };

  return (
    <Card title="Daily alert job">
      <p className="mb-4 text-sm text-slate-600">
        Runs automatically every day at 9:00 AM (India time) and when the server starts. Run it here for any date
        to see which alerts that day would create (safe to repeat: one alert per bill per day).
      </p>
      <div className="flex items-end gap-3">
        <Field label="Date"><Input type="date" value={day} onChange={(e) => setDay(e.target.value)} /></Field>
        <Button onClick={run} loading={busy}>Run now</Button>
      </div>
      <div className="mt-4 space-y-2">
        <Alert>{error}</Alert>
        {result && <Alert type="success">{result.alertsForDay} alert(s) for {result.date}; {result.universitiesEmailed} universities emailed.</Alert>}
      </div>
    </Card>
  );
}

function ExtendDueDate() {
  const [form, setForm] = useState({ periodStart: '', newDueDate: '' });
  const [errors, setErrors] = useState({});
  const [msg, setMsg] = useState({});
  const [busy, setBusy] = useState(false);

  const submit = async (e) => {
    e.preventDefault();
    setBusy(true);
    setErrors({});
    setMsg({});
    try {
      const res = await api.post('/admin/due-dates/extend', form);
      setMsg({ type: 'success', text: res.message });
    } catch (err) {
      setErrors(fieldErrors(err));
      setMsg({ type: 'error', text: err.message });
    } finally {
      setBusy(false);
    }
  };

  return (
    <Card title="Extend a GST due date">
      <p className="mb-4 text-sm text-slate-600">When the government extends the GSTR-3B date for a month, apply it to every university. Interest then counts from the new date.</p>
      <form onSubmit={submit} className="space-y-4">
        <Alert type={msg.type}>{msg.text}</Alert>
        <div className="grid grid-cols-2 gap-4">
          <Field label="Tax month" error={errors.periodStart}>
            <Input type="month" required value={form.periodStart.slice(0, 7)}
              onChange={(e) => setForm({ ...form, periodStart: e.target.value ? `${e.target.value}-01` : '' })} />
          </Field>
          <Field label="New due date" error={errors.newDueDate}>
            <Input type="date" required value={form.newDueDate} onChange={(e) => setForm({ ...form, newDueDate: e.target.value })} />
          </Field>
        </div>
        <Button type="submit" loading={busy}>Extend</Button>
      </form>
    </Card>
  );
}
