import { useState } from 'react';
import { Link, Navigate, useLocation, useNavigate } from 'react-router';
import { useAuth } from '../../context/AuthContext.jsx';
import { homeFor } from '../../components/ProtectedRoute.jsx';
import { Alert, Button, Field, Input } from '../../components/ui.jsx';
import AuthShell from './AuthShell.jsx';

export default function Login() {
  const { user, login } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const [form, setForm] = useState({ email: '', password: '' });
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  if (user) return <Navigate to={homeFor(user)} replace />;

  const submit = async (e) => {
    e.preventDefault();
    setBusy(true);
    setError('');
    try {
      const u = await login(form.email, form.password);
      // go back to the page they wanted, if it belongs to their role
      const from = location.state?.from;
      navigate(from && from.startsWith(homeFor(u)) ? from : homeFor(u), { replace: true });
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <AuthShell title="Sign in" subtitle="Universities and the tax office use the same login page.">
      <form onSubmit={submit} className="space-y-4">
        <Alert>{error}</Alert>
        {location.state?.message && <Alert type="success">{location.state.message}</Alert>}
        <Field label="Email">
          <Input type="email" autoComplete="email" required value={form.email}
            onChange={(e) => setForm({ ...form, email: e.target.value })} />
        </Field>
        <Field label="Password">
          <Input type="password" autoComplete="current-password" required value={form.password}
            onChange={(e) => setForm({ ...form, password: e.target.value })} />
        </Field>
        <Button type="submit" loading={busy} className="w-full">Sign in</Button>
      </form>
      <div className="mt-6 flex justify-between text-sm">
        <Link to="/forgot-password" className="text-brand-700 hover:underline">Forgot password?</Link>
        <Link to="/register" className="text-brand-700 hover:underline">Register a university</Link>
      </div>
    </AuthShell>
  );
}
