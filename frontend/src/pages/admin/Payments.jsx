// Verify the payments universities recorded (only verified money counts).
import { useState } from 'react';
import { api } from '../../api/client.js';
import { useApi } from '../../hooks/useApi.js';
import { date, money } from '../../utils/format.js';
import { Alert, Badge, Button, Card, Field, Input, Loader, Modal, PageHeader, Table } from '../../components/ui.jsx';

export default function AdminPayments() {
  const [status, setStatus] = useState('Pending');
  const { data, loading, error, reload } = useApi(`/admin/payments${status ? `?status=${status}` : ''}`);
  const [deciding, setDeciding] = useState(null);
  const [message, setMessage] = useState({});

  const decide = async (decision, remarks) => {
    setMessage({});
    try {
      const res = await api.patch(`/admin/payments/${deciding.Payment_ID}/verify`, { decision, remarks: remarks || undefined });
      const extra = res.anomalies?.length ? ` Note: ${res.anomalies[0].Details}` : '';
      setMessage({ type: 'success', text: `${res.message}.${extra}` });
      setDeciding(null);
      reload();
    } catch (err) {
      setMessage({ type: 'error', text: err.message });
    }
  };

  return (
    <>
      <PageHeader title="Verify payments"
        subtitle="Match each challan (CIN) with the bank / GST portal before verifying. Verifying adds it to the bill."
        actions={
          <select value={status} onChange={(e) => setStatus(e.target.value)} className="rounded-lg border border-slate-300 px-3 py-2 text-sm">
            <option value="Pending">Pending</option><option value="Verified">Verified</option>
            <option value="Rejected">Rejected</option><option value="">All</option>
          </select>
        } />
      {message.text && <div className="mb-4"><Alert type={message.type}>{message.text}</Alert></div>}
      <Card>
        <Loader loading={loading} error={error}>
          <Table rowKey="Payment_ID" rows={data} empty="No payments here." columns={[
            { key: 'University', label: 'University', render: (r) => <span className="font-medium">{r.University}</span> },
            { key: 'Period', label: 'Bill' },
            { key: 'Payment_For', label: 'For' },
            { key: 'Payment_Date', label: 'Paid on', render: (r) => date(r.Payment_Date) },
            { key: 'Reference_No', label: 'CIN', render: (r) => <span>{r.Reference_No}<br /><span className="text-xs text-slate-500">{r.Mode}</span></span> },
            { key: 'Amount', label: 'Amount', align: 'right', render: (r) => money(r.Amount) },
            { key: 'Tax_Outstanding', label: 'Bill outstanding', align: 'right', render: (r) => money(r.Tax_Outstanding) },
            { key: 'Status', label: 'Status', render: (r) => (
              <div><Badge>{r.Status}</Badge>{r.Verified_By_Name && <p className="text-xs text-slate-500">by {r.Verified_By_Name}</p>}</div>
            ) },
            { key: 'actions', label: '', render: (r) => r.Status === 'Pending' && (
              <Button size="sm" onClick={() => setDeciding(r)}>Review</Button>
            ) },
          ]} />
        </Loader>
      </Card>

      <Modal open={Boolean(deciding)} title="Review payment" onClose={() => setDeciding(null)}>
        {deciding && <DecideForm payment={deciding} onDecide={decide} />}
      </Modal>
    </>
  );
}

function DecideForm({ payment: p, onDecide }) {
  const [remarks, setRemarks] = useState('');
  const [busy, setBusy] = useState('');
  const go = async (d) => { setBusy(d); await onDecide(d, remarks); setBusy(''); };
  return (
    <div className="space-y-4 text-sm">
      <dl className="grid grid-cols-2 gap-3">
        <div><dt className="text-xs text-slate-500">University</dt><dd>{p.University}</dd></div>
        <div><dt className="text-xs text-slate-500">Bill</dt><dd>{p.Period} ({p.Payment_For})</dd></div>
        <div><dt className="text-xs text-slate-500">Amount</dt><dd className="font-semibold">{money(p.Amount)}</dd></div>
        <div><dt className="text-xs text-slate-500">CIN</dt><dd>{p.Reference_No}</dd></div>
      </dl>
      <Field label="Remarks (required when rejecting)">
        <Input value={remarks} onChange={(e) => setRemarks(e.target.value)} />
      </Field>
      <div className="flex gap-2">
        <Button variant="success" loading={busy === 'Verified'} onClick={() => go('Verified')}>Verify</Button>
        <Button variant="danger" loading={busy === 'Rejected'} disabled={!remarks.trim()} onClick={() => go('Rejected')}>Reject</Button>
      </div>
    </div>
  );
}
