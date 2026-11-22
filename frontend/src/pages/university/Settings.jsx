// University profile, departments, staff logins and password.
import { useState } from 'react';
import { api } from '../../api/client.js';
import { useApi } from '../../hooks/useApi.js';
import { date, dateTime } from '../../utils/format.js';
import {
  Alert, Badge, Button, Card, Field, Input, Loader, PageHeader, Table, fieldErrors,
} from '../../components/ui.jsx';
import { ChangePasswordCard } from '../ChangePassword.jsx';

export default function Settings() {
  const profile = useApi('/university/profile');
  const depts = useApi('/university/departments');
  const users = useApi('/university/users');
  const p = profile.data;

  return (
    <>
      <PageHeader title="Settings" subtitle="Your university, departments and logins" />
      <div className="grid gap-6 xl:grid-cols-2">
        <Card title="University">
          <Loader loading={profile.loading} error={profile.error}>
            {p && (
              <dl className="grid grid-cols-2 gap-x-4 gap-y-3 text-sm">
                <Item label="Name" value={p.Name} />
                <Item label="Status" value={<Badge>{p.Status}</Badge>} />
                <Item label="GSTIN" value={p.GSTIN} />
                <Item label="PAN" value={p.PAN} />
                <Item label="State" value={p.State} />
                <Item label="Type" value={p.Institution_Type} />
                <Item label="Income-tax exemption" value={p.IT_Exemption} />
                <Item label="Approved on" value={date(p.Reviewed_At)} />
                <Item label="Contact" value={`${p.Contact_Person} · ${p.Phone ?? '—'}`} />
                <Item label="Email" value={p.Email} />
              </dl>
            )}
            <p className="mt-4 text-xs text-slate-500">GSTIN and state are locked after approval because every tax calculation depends on them.</p>
          </Loader>
        </Card>

        <Card title="Departments">
          <Loader loading={depts.loading} error={depts.error}>
            <Table rowKey="Dept_ID" rows={depts.data} columns={[
              { key: 'Name', label: 'Department' },
              { key: 'Entries', label: 'Income entries', align: 'right' },
            ]} />
            <AddForm
              fields={[{ key: 'name', label: 'New department' }]}
              submitLabel="Add department"
              onSubmit={(body) => api.post('/university/departments', body)}
              onDone={depts.reload}
            />
          </Loader>
        </Card>

        <Card title="Staff logins">
          <Loader loading={users.loading} error={users.error}>
            <Table rowKey="User_ID" rows={users.data} columns={[
              { key: 'Name', label: 'Name' },
              { key: 'Email', label: 'Email' },
              { key: 'Last_Login', label: 'Last login', render: (r) => dateTime(r.Last_Login) },
            ]} />
            <AddForm
              fields={[
                { key: 'name', label: 'Name' },
                { key: 'email', label: 'Email', type: 'email' },
                { key: 'password', label: 'Their password', type: 'password', hint: '8+ characters, upper, lower, number, symbol' },
              ]}
              submitLabel="Add staff login"
              onSubmit={(body) => api.post('/university/users', body)}
              onDone={users.reload}
            />
          </Loader>
        </Card>

        <ChangePasswordCard />
      </div>
    </>
  );
}

function Item({ label, value }) {
  return (
    <div>
      <dt className="text-xs text-slate-500">{label}</dt>
      <dd className="mt-0.5 font-medium text-slate-800">{value || '—'}</dd>
    </div>
  );
}

// small inline form used for "add department" and "add staff login"
export function AddForm({ fields, submitLabel, onSubmit, onDone }) {
  const empty = Object.fromEntries(fields.map((f) => [f.key, '']));
  const [form, setForm] = useState(empty);
  const [errors, setErrors] = useState({});
  const [msg, setMsg] = useState({});
  const [busy, setBusy] = useState(false);

  const submit = async (e) => {
    e.preventDefault();
    setBusy(true);
    setErrors({});
    setMsg({});
    try {
      await onSubmit(form);
      setForm(empty);
      setMsg({ type: 'success', text: 'Saved' });
      onDone();
    } catch (err) {
      setErrors(fieldErrors(err));
      setMsg({ type: 'error', text: err.message });
    } finally {
      setBusy(false);
    }
  };

  return (
    <form onSubmit={submit} className="mt-4 space-y-3 border-t border-slate-100 pt-4">
      <Alert type={msg.type}>{msg.text}</Alert>
      <div className="grid gap-3 sm:grid-cols-2">
        {fields.map((f) => (
          <Field key={f.key} label={f.label} error={errors[f.key]} hint={f.hint}>
            <Input type={f.type ?? 'text'} required value={form[f.key]}
              onChange={(e) => setForm({ ...form, [f.key]: e.target.value })} />
          </Field>
        ))}
      </div>
      <Button type="submit" variant="secondary" loading={busy}>{submitLabel}</Button>
    </form>
  );
}
