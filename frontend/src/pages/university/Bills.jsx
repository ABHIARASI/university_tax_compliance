// Monthly GST bills: what is due, paid, overdue, interest; pay a bill.
import { useState } from 'react';
import { api } from '../../api/client.js';
import { useApi } from '../../hooks/useApi.js';
import { date, fyOf, money, todayISO } from '../../utils/format.js';
import {
  Alert, Badge, Button, Card, Field, Input, Loader, Modal, PageHeader, Select, Table, fieldErrors,
} from '../../components/ui.jsx';
import FySelect from '../../components/FySelect.jsx';
import BillDetail from '../../components/BillDetail.jsx';

export default function Bills() {
  const [fy, setFy] = useState(fyOf(todayISO()));
  const bills = useApi(`/university/tax-records?fy=${fy}`);
  const [viewing, setViewing] = useState(null);
  const [paying, setPaying] = useState(null);
  const [message, setMessage] = useState('');

  const columns = [
    { key: 'Period', label: 'Month', render: (r) => <span className="font-medium">{r.Period}</span> },
    { key: 'Total_Income', label: 'Income', align: 'right', render: (r) => money(r.Total_Income) },
    { key: 'Tax_Due', label: 'GST due', align: 'right', render: (r) => money(r.Tax_Due) },
    { key: 'Tax_Paid', label: 'Paid', align: 'right', render: (r) => money(r.Tax_Paid) },
    { key: 'Tax_Outstanding', label: 'Outstanding', align: 'right', render: (r) => (
      <span className={r.Tax_Outstanding > 0 ? 'font-medium text-rose-600' : ''}>{money(r.Tax_Outstanding)}</span>
    ) },
    { key: 'Interest_Outstanding', label: 'Interest due', align: 'right', render: (r) => money(r.Interest_Outstanding) },
    { key: 'Due_Date', label: 'Due date', render: (r) => date(r.Due_Date) },
    { key: 'Status', label: 'Status', render: (r) => (
      <div className="space-y-1">
        <Badge>{r.Status}</Badge>
        {r.Pending_Verification > 0 && <p className="text-xs text-amber-700">{money(r.Pending_Verification)} being verified</p>}
      </div>
    ) },
    { key: 'actions', label: '', render: (r) => (
      <div className="flex gap-1" onClick={(e) => e.stopPropagation()}>
        <Button size="sm" variant="ghost" onClick={() => setViewing(r)}>View</Button>
        {(r.Tax_Outstanding > 0 || r.Interest_Outstanding > 0) && (
          <Button size="sm" onClick={() => setPaying(r)}>Pay</Button>
        )}
      </div>
    ) },
  ];

  return (
    <>
      <PageHeader
        title="GST bills"
        subtitle="One bill per month. GST is due on the 20th of the next month; after that 18% interest a year is charged per day."
        actions={<FySelect value={fy} onChange={setFy} />}
      />
      {message && <div className="mb-4"><Alert type="success">{message}</Alert></div>}
      <Card>
        <Loader loading={bills.loading} error={bills.error}>
          <Table columns={columns} rows={bills.data} rowKey="Tax_ID" onRowClick={setViewing}
            empty="No bills in this financial year." />
        </Loader>
      </Card>

      <Modal open={Boolean(viewing)} title={`GST bill — ${viewing?.Period ?? ''}`} onClose={() => setViewing(null)} wide>
        {viewing && <BillDetail path={`/university/tax-records/${viewing.Tax_ID}`} />}
      </Modal>

      <Modal open={Boolean(paying)} title={`Pay GST — ${paying?.Period ?? ''}`} onClose={() => setPaying(null)}>
        {paying && (
          <PayForm bill={paying} onDone={(msg) => { setPaying(null); setMessage(msg); bills.reload(); }} />
        )}
      </Modal>
    </>
  );
}

function PayForm({ bill, onDone }) {
  const defaultFor = bill.Tax_Outstanding > 0 ? 'Tax' : 'Interest';
  const owed = (f) => (f === 'Tax' ? bill.Tax_Outstanding : bill.Interest_Outstanding);
  const [form, setForm] = useState({
    paymentFor: defaultFor, amount: owed(defaultFor), paymentDate: todayISO(), mode: 'Net Banking', referenceNo: '',
  });
  const [errors, setErrors] = useState({});
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const submit = async (e) => {
    e.preventDefault();
    setBusy(true);
    setError('');
    try {
      const res = await api.post('/university/payments', { ...form, taxId: bill.Tax_ID });
      onDone(res.message);
    } catch (err) {
      setErrors(fieldErrors(err));
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <form onSubmit={submit} className="space-y-4">
      <Alert type="info">
        Pay on the GST portal first, then record the challan here with its CIN.
        The tax office verifies it before it counts.
      </Alert>
      <Alert>{error}</Alert>
      <Field label="Paying for" error={errors.paymentFor}>
        <Select value={form.paymentFor}
          onChange={(e) => setForm({ ...form, paymentFor: e.target.value, amount: owed(e.target.value) })}
          options={[
            { value: 'Tax', label: `GST (outstanding ${money(bill.Tax_Outstanding)})` },
            { value: 'Interest', label: `Interest (outstanding ${money(bill.Interest_Outstanding)})` },
          ]} />
      </Field>
      <Field label="Amount" error={errors.amount}>
        <Input type="number" step="0.01" min="0.01" required value={form.amount}
          onChange={(e) => setForm({ ...form, amount: e.target.value })} />
      </Field>
      <Field label="Payment date" error={errors.paymentDate}>
        <Input type="date" required max={todayISO()} value={form.paymentDate}
          onChange={(e) => setForm({ ...form, paymentDate: e.target.value })} />
      </Field>
      <Field label="Mode" error={errors.mode} hint="Over the counter is allowed only up to ₹10,000">
        <Select value={form.mode} onChange={(e) => setForm({ ...form, mode: e.target.value })}
          options={['Net Banking', 'NEFT/RTGS', 'UPI', 'Card', 'Over the Counter']} />
      </Field>
      <Field label="Challan CIN (reference number)" error={errors.referenceNo}>
        <Input required minLength={5} value={form.referenceNo}
          onChange={(e) => setForm({ ...form, referenceNo: e.target.value })} />
      </Field>
      <div className="flex justify-end"><Button type="submit" loading={busy}>Record payment</Button></div>
    </form>
  );
}
