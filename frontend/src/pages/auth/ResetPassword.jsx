import { useState } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router';
import { api } from '../../api/client.js';
import { Alert, Button, Field, Input, fieldErrors } from '../../components/ui.jsx';
import AuthShell from './AuthShell.jsx';

export default function ResetPassword() {
  const [params] = useSearchParams();
  const navigate = useNavigate();
  const token = params.get('token') ?? '';
  const [form, setForm] = useState({ newPassword: '', confirm: '' });
  const [errors, setErrors] = useState({});
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const submit = async (e) => {
    e.preventDefault();
    setErrors({});
    setError('');
    if (form.newPassword !== form.confirm) return setErrors({ confirm: 'Passwords do not match' });
    setBusy(true);
    try {
      const res = await api.post('/auth/reset-password', { token, newPassword: form.newPassword });
      navigate('/login', { state: { message: res.message } });
    } catch (err) {
      setErrors(fieldErrors(err));
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <AuthShell title="Set a new password">
      {!token ? (
        <Alert>This link is incomplete. Ask for a new one from “Forgot password”.</Alert>
      ) : (
        <form onSubmit={submit} className="space-y-4">
          <Alert>{error}</Alert>
          <Field label="New password" error={errors.newPassword}
            hint="8+ characters with upper and lower case, a number and a symbol">
            <Input type="password" required autoComplete="new-password" value={form.newPassword}
              onChange={(e) => setForm({ ...form, newPassword: e.target.value })} />
          </Field>
          <Field label="Confirm" error={errors.confirm}>
            <Input type="password" required autoComplete="new-password" value={form.confirm}
              onChange={(e) => setForm({ ...form, confirm: e.target.value })} />
          </Field>
          <Button type="submit" loading={busy} className="w-full">Save password</Button>
        </form>
      )}
      <p className="mt-6 text-sm"><Link to="/login" className="text-brand-700 hover:underline">Back to sign in</Link></p>
    </AuthShell>
  );
}
