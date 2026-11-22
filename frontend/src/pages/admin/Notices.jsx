// Send notices to universities, read their replies, close them.
import { useEffect, useState } from 'react';
import { useSearchParams } from 'react-router';
import { api } from '../../api/client.js';
import { useApi } from '../../hooks/useApi.js';
import { date, dateTime, todayISO } from '../../utils/format.js';
import {
  Alert, Badge, Button, Card, Empty, Field, Input, Loader, PageHeader, Select, Textarea, fieldErrors,
} from '../../components/ui.jsx';

export default function AdminNotices() {
  const [params] = useSearchParams();
  const [status, setStatus] = useState('');
  const list = useApi(`/admin/notices${status ? `?status=${status}` : ''}`);

  const close = async (id) => { await api.patch(`/admin/notices/${id}/close`); list.reload(); };

  return (
    <>
      <PageHeader title="Notices" subtitle="Reminders, demands and anomaly queries sent to universities (they also get an email)." />
      <div className="grid gap-6 xl:grid-cols-5">
        <div className="xl:col-span-2">
          <NewNotice presetUniv={params.get('univId')} presetAnomaly={params.get('anomalyId')} onSent={list.reload} />
        </div>
        <div className="space-y-4 xl:col-span-3">
          <div className="flex justify-end">
            <select value={status} onChange={(e) => setStatus(e.target.value)} className="rounded-lg border border-slate-300 px-3 py-2 text-sm">
              <option value="">All notices</option><option value="Responded">Replied</option>
              <option value="Open">Waiting for reply</option><option value="Closed">Closed</option>
            </select>
          </div>
          <Loader loading={list.loading} error={list.error}>
            {!list.data?.length ? <Card><Empty>No notices.</Empty></Card> : list.data.map((n) => (
              <Card key={n.Notice_ID}>
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div className="flex items-center gap-2"><Badge color="blue">{n.Type}</Badge><Badge>{n.Status}</Badge></div>
                  <span className="text-xs text-slate-500">{dateTime(n.Issued_At)}</span>
                </div>
                <h3 className="mt-2 font-semibold">{n.Subject}</h3>
                <p className="text-sm text-slate-600">{n.University}{n.Period ? ` · ${n.Period} bill` : ''}{n.Response_Due ? ` · reply by ${date(n.Response_Due)}` : ''}</p>
                <p className="mt-2 whitespace-pre-line text-sm">{n.Message}</p>
                {n.Response && (
                  <div className="mt-3 rounded-lg bg-emerald-50 p-3 text-sm">
                    <p className="text-xs font-medium text-emerald-700">Reply · {dateTime(n.Responded_At)}</p>
                    <p className="mt-1 whitespace-pre-line">{n.Response}</p>
                  </div>
                )}
                {n.Status !== 'Closed' && (
                  <div className="mt-3"><Button size="sm" variant="secondary" onClick={() => close(n.Notice_ID)}>Close notice</Button></div>
                )}
              </Card>
            ))}
          </Loader>
        </div>
      </div>
    </>
  );
}

function NewNotice({ presetUniv, presetAnomaly, onSent }) {
  const unis = useApi('/admin/universities?status=APPROVED');
  const [form, setForm] = useState({
    univId: presetUniv ?? '', taxId: '', anomalyId: presetAnomaly ?? '',
    type: presetAnomaly ? 'Anomaly Query' : 'Reminder', subject: '', message: '', responseDue: '',
  });
  const bills = useApi(form.univId ? `/admin/universities/${form.univId}` : null);
  const [errors, setErrors] = useState({});
  const [msg, setMsg] = useState({});
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (presetUniv) setForm((f) => ({ ...f, univId: presetUniv, anomalyId: presetAnomaly ?? '' }));
  }, [presetUniv, presetAnomaly]);

  const set = (k) => (e) => setForm({ ...form, [k]: e.target.value });

  const submit = async (e) => {
    e.preventDefault();
    setBusy(true);
    setErrors({});
    setMsg({});
    try {
      const body = Object.fromEntries(Object.entries(form).filter(([, v]) => v !== ''));
      const res = await api.post('/admin/notices', body);
      setMsg({ type: 'success', text: res.message });
      setForm({ ...form, taxId: '', anomalyId: '', subject: '', message: '', responseDue: '' });
      onSent();
    } catch (err) {
      setErrors(fieldErrors(err));
      setMsg({ type: 'error', text: err.message });
    } finally {
      setBusy(false);
    }
  };

  return (
    <Card title="New notice">
      <form onSubmit={submit} className="space-y-4">
        <Alert type={msg.type}>{msg.text}</Alert>
        <Field label="University" error={errors.univId}>
          <Select required value={form.univId} onChange={(e) => setForm({ ...form, univId: e.target.value, taxId: '' })}
            placeholder="Choose…" options={(unis.data ?? []).map((u) => ({ value: u.Univ_ID, label: u.Name }))} />
        </Field>
        <Field label="Type" error={errors.type}>
          <Select value={form.type} onChange={set('type')} options={['Reminder', 'Demand', 'Anomaly Query', 'General']} />
        </Field>
        <Field label="About a bill (optional)" error={errors.taxId}>
          <Select value={form.taxId} onChange={set('taxId')} placeholder="None"
            options={(bills.data?.bills ?? []).map((b) => ({ value: b.Tax_ID, label: `${b.Period} — ${b.Status}` }))} />
        </Field>
        {form.anomalyId && <p className="text-xs text-slate-500">About anomaly #{form.anomalyId}</p>}
        <Field label="Subject" error={errors.subject}><Input required value={form.subject} onChange={set('subject')} /></Field>
        <Field label="Message" error={errors.message}><Textarea required value={form.message} onChange={set('message')} /></Field>
        <Field label="Reply by (optional)" error={errors.responseDue}>
          <Input type="date" min={todayISO()} value={form.responseDue} onChange={set('responseDue')} />
        </Field>
        <Button type="submit" loading={busy}>Send notice</Button>
      </form>
    </Card>
  );
}
