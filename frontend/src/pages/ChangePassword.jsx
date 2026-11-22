// Change password (used by both roles). Changing it logs out every other device.
import { useState } from 'react';
import { api } from '../api/client.js';
import { Alert, Button, Card, Field, Input, PageHeader, fieldErrors } from '../components/ui.jsx';

export function ChangePasswordCard() {
  const [form, setForm] = useState({ currentPassword: '', newPassword: '', confirm: '' });
  const [errors, setErrors] = useState({});
  const [msg, setMsg] = useState({ type: '', text: '' });
  const [busy, setBusy] = useState(false);

  const submit = async (e) => {
    e.preventDefault();
    setErrors({});
    setMsg({});
    if (form.newPassword !== form.confirm) return setErrors({ confirm: 'Passwords do not match' });
    setBusy(true);
    try {
      const res = await api.post('/auth/change-password', {
        currentPassword: form.currentPassword, newPassword: form.newPassword,
      });
      setMsg({ type: 'success', text: res.message });
      setForm({ currentPassword: '', newPassword: '', confirm: '' });
    } catch (err) {
      setErrors(fieldErrors(err));
      setMsg({ type: 'error', text: err.message });
    } finally {
      setBusy(false);
    }
  };

  return (
    <Card title="Change password">
      <form onSubmit={submit} className="max-w-md space-y-4">
        <Alert type={msg.type}>{msg.text}</Alert>
        <Field label="Current password" error={errors.currentPassword}>
          <Input type="password" required value={form.currentPassword} autoComplete="current-password"
            onChange={(e) => setForm({ ...form, currentPassword: e.target.value })} />
        </Field>
        <Field label="New password" error={errors.newPassword}
          hint="8+ characters with upper and lower case, a number and a symbol">
          <Input type="password" required value={form.newPassword} autoComplete="new-password"
            onChange={(e) => setForm({ ...form, newPassword: e.target.value })} />
        </Field>
        <Field label="Confirm new password" error={errors.confirm}>
          <Input type="password" required value={form.confirm} autoComplete="new-password"
            onChange={(e) => setForm({ ...form, confirm: e.target.value })} />
        </Field>
        <Button type="submit" loading={busy}>Change password</Button>
      </form>
    </Card>
  );
}

export default function ChangePassword() {
  return (
    <>
      <PageHeader title="Settings" subtitle="Your account" />
      <ChangePasswordCard />
    </>
  );
}
