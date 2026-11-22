// A university registers itself and chooses its OWN password.
// It can log in only after the tax office approves the registration.
import { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router';
import { api } from '../../api/client.js';
import { Alert, Button, Field, Input, Select, fieldErrors } from '../../components/ui.jsx';
import AuthShell from './AuthShell.jsx';

const EMPTY = {
  universityName: '', gstin: '', institutionType: 'Private', itExemption: 'None',
  address: '', city: '', state: '', contactPerson: '', phone: '', email: '',
  password: '', confirm: '',
};

export default function Register() {
  const navigate = useNavigate();
  const [form, setForm] = useState(EMPTY);
  const [states, setStates] = useState([]);
  const [options, setOptions] = useState({ institutionTypes: [], itExemptions: [] });
  const [errors, setErrors] = useState({});
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    api.get('/meta/states').then(setStates).catch(() => {});
    api.get('/meta/registration-options').then(setOptions).catch(() => {});
  }, []);

  const set = (key) => (e) => setForm({ ...form, [key]: e.target.value });

  // the first 2 digits of a GSTIN are the state code -> pick the state automatically
  const onGstin = (e) => {
    const gstin = e.target.value.toUpperCase().replace(/\s/g, '');
    const match = states.find((s) => s.State_Code === gstin.slice(0, 2));
    setForm({ ...form, gstin, state: match ? match.State_Name : form.state });
  };

  const submit = async (e) => {
    e.preventDefault();
    setErrors({});
    setError('');
    if (form.password !== form.confirm) {
      setErrors({ confirm: 'Passwords do not match' });
      return;
    }
    setBusy(true);
    try {
      const { confirm, ...body } = form;
      // send only filled-in optional fields
      for (const k of ['address', 'city', 'phone']) if (!body[k]) delete body[k];
      const res = await api.post('/auth/register', body);
      navigate('/login', { state: { message: res.message } });
    } catch (err) {
      setErrors(fieldErrors(err));
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <AuthShell wide title="Register your university"
      subtitle="The tax office checks your GSTIN and approves the account. You can sign in after approval.">
      <form onSubmit={submit} className="space-y-6">
        <Alert>{error}</Alert>

        <fieldset className="grid gap-4 sm:grid-cols-2">
          <legend className="mb-2 text-sm font-semibold text-slate-900">University</legend>
          <Field label="University name" error={errors.universityName} className="sm:col-span-2">
            <Input required value={form.universityName} onChange={set('universityName')} />
          </Field>
          <Field label="GSTIN" error={errors.gstin} hint="15 characters, e.g. 29AABTG4521K1ZL">
            <Input required maxLength={15} value={form.gstin} onChange={onGstin} className="uppercase" />
          </Field>
          <Field label="State" error={errors.state} hint="Filled from the GSTIN state code">
            <Select required value={form.state} onChange={set('state')} placeholder="Select state"
              options={states.map((s) => ({ value: s.State_Name, label: `${s.State_Name} (${s.State_Code})` }))} />
          </Field>
          <Field label="Type of institution" error={errors.institutionType}>
            <Select value={form.institutionType} onChange={set('institutionType')} options={options.institutionTypes} />
          </Field>
          <Field label="Income-tax exemption" error={errors.itExemption}>
            <Select value={form.itExemption} onChange={set('itExemption')} options={options.itExemptions} />
          </Field>
          <Field label="Address" error={errors.address}>
            <Input value={form.address} onChange={set('address')} />
          </Field>
          <Field label="City" error={errors.city}>
            <Input value={form.city} onChange={set('city')} />
          </Field>
        </fieldset>

        <fieldset className="grid gap-4 sm:grid-cols-2">
          <legend className="mb-2 text-sm font-semibold text-slate-900">Your login</legend>
          <Field label="Contact person" error={errors.contactPerson}>
            <Input required value={form.contactPerson} onChange={set('contactPerson')} />
          </Field>
          <Field label="Mobile" error={errors.phone}>
            <Input inputMode="numeric" maxLength={10} value={form.phone} onChange={set('phone')} />
          </Field>
          <Field label="Email (your login)" error={errors.email} className="sm:col-span-2">
            <Input type="email" required autoComplete="email" value={form.email} onChange={set('email')} />
          </Field>
          <Field label="Choose a password" error={errors.password}
            hint="8+ characters with upper and lower case, a number and a symbol">
            <Input type="password" required autoComplete="new-password" value={form.password} onChange={set('password')} />
          </Field>
          <Field label="Confirm password" error={errors.confirm}>
            <Input type="password" required autoComplete="new-password" value={form.confirm} onChange={set('confirm')} />
          </Field>
        </fieldset>

        <div className="flex flex-wrap items-center justify-between gap-3">
          <Link to="/login" className="text-sm text-brand-700 hover:underline">Already registered? Sign in</Link>
          <Button type="submit" loading={busy}>Submit registration</Button>
        </div>
      </form>
    </AuthShell>
  );
}
