// The Indian tax rules the whole system uses. Changes are logged and only
// affect NEW income (each entry keeps the rate it was saved with).
import { useState } from 'react';
import { api } from '../../api/client.js';
import { useApi } from '../../hooks/useApi.js';
import { dateTime } from '../../utils/format.js';
import { Alert, Badge, Button, Card, Field, Input, Loader, Modal, PageHeader, Table } from '../../components/ui.jsx';

export default function TaxRules() {
  const rules = useApi('/admin/tax-rules');
  const audit = useApi('/admin/tax-rules/audit');
  const [editing, setEditing] = useState(null);
  const [message, setMessage] = useState({});

  return (
    <>
      <PageHeader title="Tax rules" subtitle="GST and TDS treatment of each kind of university income (India)." />
      {message.text && <div className="mb-4"><Alert type={message.type}>{message.text}</Alert></div>}
      <div className="space-y-6">
        <Card>
          <Loader loading={rules.loading} error={rules.error}>
            <Table rowKey="TaxRule_ID" rows={rules.data} columns={[
              { key: 'Income_Type', label: 'Income type', render: (r) => <div><p className="font-medium">{r.Income_Type}</p><p className="text-xs text-slate-500">SAC {r.SAC_Code ?? '—'} · {r.Sources} sources</p></div> },
              { key: 'GST_Category', label: 'GST', render: (r) => <div><Badge>{r.GST_Category}</Badge><p className="mt-1 font-medium">{r.Tax_Rate}%{r.Special_Rule === 'ACCOMMODATION' ? ' / 5% / 18%' : ''}</p></div> },
              { key: 'TDS_Rate', label: 'TDS', render: (r) => r.TDS_Rate ? <div><p>{r.TDS_Rate}%</p><p className="text-xs text-slate-500">above ₹{r.TDS_Threshold.toLocaleString('en-IN')} {r.TDS_Threshold_Basis === 'MONTHLY_PER_PAYER' ? 'a month' : 'a year'}</p></div> : '—' },
              { key: 'Legal_Basis', label: 'Legal basis', render: (r) => <div className="max-w-sm"><p className="text-xs">{r.Legal_Basis}</p><p className="mt-1 text-xs text-slate-500">{r.Conditions}</p></div> },
              { key: 'actions', label: '', render: (r) => <Button size="sm" variant="ghost" onClick={() => setEditing(r)}>Edit</Button> },
            ]} />
          </Loader>
        </Card>
        <Card title="Change history">
          <Loader loading={audit.loading} error={audit.error}>
            <Table rowKey="Audit_ID" rows={audit.data} empty="No changes yet." columns={[
              { key: 'Changed_At', label: 'When', render: (r) => dateTime(r.Changed_At) },
              { key: 'Income_Type', label: 'Rule' },
              { key: 'gst', label: 'GST', render: (r) => `${r.Old_Tax_Rate}% → ${r.New_Tax_Rate}%` },
              { key: 'tds', label: 'TDS', render: (r) => `${r.Old_TDS_Rate}% → ${r.New_TDS_Rate}%` },
              { key: 'Changed_By_Name', label: 'By' },
            ]} />
          </Loader>
        </Card>
      </div>

      <Modal open={Boolean(editing)} title={`Edit — ${editing?.Income_Type ?? ''}`} onClose={() => setEditing(null)}>
        {editing && (
          <EditRule rule={editing} onSaved={(text) => {
            setEditing(null); setMessage({ type: 'success', text }); rules.reload(); audit.reload();
          }} />
        )}
      </Modal>
    </>
  );
}

function EditRule({ rule, onSaved }) {
  const [form, setForm] = useState({
    taxRate: rule.Tax_Rate, tdsRate: rule.TDS_Rate, legalBasis: rule.Legal_Basis, conditions: rule.Conditions ?? '',
  });
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const submit = async (e) => {
    e.preventDefault();
    setBusy(true);
    setError('');
    try {
      const res = await api.patch(`/admin/tax-rules/${rule.TaxRule_ID}`, form);
      onSaved(res.message);
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <form onSubmit={submit} className="space-y-4">
      <Alert type="info">A new rate applies only to income saved from now on. Past entries keep their rate.</Alert>
      <Alert>{error}</Alert>
      <div className="grid grid-cols-2 gap-4">
        <Field label="GST %"><Input type="number" step="0.01" min="0" max="100" value={form.taxRate} onChange={(e) => setForm({ ...form, taxRate: e.target.value })} /></Field>
        <Field label="TDS %"><Input type="number" step="0.01" min="0" max="100" value={form.tdsRate} onChange={(e) => setForm({ ...form, tdsRate: e.target.value })} /></Field>
      </div>
      <Field label="Legal basis"><Input value={form.legalBasis} onChange={(e) => setForm({ ...form, legalBasis: e.target.value })} /></Field>
      <Field label="Conditions"><Input value={form.conditions} onChange={(e) => setForm({ ...form, conditions: e.target.value })} /></Field>
      <Button type="submit" loading={busy}>Save</Button>
    </form>
  );
}
