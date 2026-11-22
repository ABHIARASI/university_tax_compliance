// Income entries: list with filters and pages, add new income, correct with a credit note.
import { useEffect, useMemo, useState } from 'react';
import { api } from '../../api/client.js';
import { useApi } from '../../hooks/useApi.js';
import { date, money, todayISO } from '../../utils/format.js';
import {
  Alert, Badge, Button, Card, Field, Input, Loader, Modal, PageHeader, Select, Table, Textarea, fieldErrors,
} from '../../components/ui.jsx';

export default function Income() {
  const [filters, setFilters] = useState({ from: '', to: '', deptId: '', sourceId: '', search: '' });
  const [page, setPage] = useState(1);
  const [adding, setAdding] = useState(false);
  const [crediting, setCrediting] = useState(null);
  const [notice, setNotice] = useState(null);

  const qs = useMemo(() => {
    const p = new URLSearchParams({ page, pageSize: 20 });
    for (const [k, v] of Object.entries(filters)) if (v) p.set(k, v);
    return p.toString();
  }, [filters, page]);

  const list = useApi(`/university/transactions?${qs}`);
  const depts = useApi('/university/departments');
  const sources = useApi('/meta/income-sources');

  const setFilter = (k) => (e) => { setFilters({ ...filters, [k]: e.target.value }); setPage(1); };
  const pages = list.data ? Math.max(1, Math.ceil(list.data.total / list.data.pageSize)) : 1;

  const afterSave = (result, label) => {
    setAdding(false);
    setCrediting(null);
    setNotice({ label, ...result });
    list.reload();
  };

  const columns = [
    { key: 'Trans_Date', label: 'Date', render: (r) => date(r.Trans_Date) },
    { key: 'Source_Name', label: 'Source', render: (r) => (
      <div>
        <p className="font-medium">{r.Source_Name}</p>
        <p className="text-xs text-slate-500">{r.Department}{r.Payer_Name ? ` · ${r.Payer_Name}` : ''}</p>
      </div>
    ) },
    { key: 'Entry_Type', label: 'Type', render: (r) => (
      <div className="space-y-1">
        <Badge>{r.Entry_Type}</Badge>
        {r.Anomalies > 0 && <div><Badge color="red">Flagged</Badge></div>}
      </div>
    ) },
    { key: 'Amount', label: 'Amount', align: 'right', render: (r) =>
      <span className={r.Entry_Type === 'CREDIT_NOTE' ? 'text-violet-700' : ''}>
        {r.Entry_Type === 'CREDIT_NOTE' ? '−' : ''}{money(r.Amount)}
      </span> },
    { key: 'GST_Amount', label: 'GST', align: 'right', render: (r) => (
      <div>
        <p>{money(r.GST_Amount)}</p>
        <p className="text-xs text-slate-500">{r.GST_Rate}%{r.Place_Of_Supply ? ' IGST' : ''}</p>
      </div>
    ) },
    { key: 'TDS_Deducted', label: 'TDS', align: 'right', render: (r) => money(r.TDS_Deducted) },
    { key: 'Mode', label: 'Mode' },
    { key: 'actions', label: '', render: (r) =>
      r.Entry_Type === 'INVOICE' && r.Credited < r.Amount && (
        <Button size="sm" variant="ghost" onClick={() => setCrediting(r)}>Credit note</Button>
      ) },
  ];

  return (
    <>
      <PageHeader
        title="Income"
        subtitle="Every receipt of the university. GST, TDS and the monthly bill are worked out automatically."
        actions={<Button onClick={() => setAdding(true)}>+ Add income</Button>}
      />

      {notice && (
        <div className="mb-4 space-y-2">
          <Alert type="success">
            {notice.label}: GST {money(notice.entry.GST_Amount)} at {notice.entry.GST_Rate}%,
            TDS {money(notice.entry.TDS_Deducted)}. Added to the {notice.entry.Trans_Date.slice(0, 7)} bill.
          </Alert>
          {notice.anomalies.map((a) => (
            <Alert key={a.Rule_Code} type="warn"><b>{a.Rule_Code.replace('_', ' ')}:</b> {a.Details}</Alert>
          ))}
        </div>
      )}

      <Card>
        <div className="mb-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
          <Input type="date" value={filters.from} onChange={setFilter('from')} aria-label="From" />
          <Input type="date" value={filters.to} onChange={setFilter('to')} aria-label="To" />
          <Select value={filters.deptId} onChange={setFilter('deptId')} placeholder="All departments"
            options={(depts.data ?? []).map((d) => ({ value: d.Dept_ID, label: d.Name }))} />
          <Select value={filters.sourceId} onChange={setFilter('sourceId')} placeholder="All sources"
            options={(sources.data ?? []).map((s) => ({ value: s.Source_ID, label: s.Source_Name }))} />
          <Input placeholder="Search payer / reference" value={filters.search} onChange={setFilter('search')} />
        </div>

        <Loader loading={list.loading && !list.data} error={list.error}>
          <Table columns={columns} rows={list.data?.rows} rowKey="Trans_ID" empty="No income entries match." />
          <div className="mt-4 flex items-center justify-between text-sm text-slate-600">
            <span>{list.data?.total ?? 0} entries</span>
            <div className="flex items-center gap-2">
              <Button size="sm" variant="secondary" disabled={page <= 1} onClick={() => setPage(page - 1)}>Previous</Button>
              <span>Page {page} of {pages}</span>
              <Button size="sm" variant="secondary" disabled={page >= pages} onClick={() => setPage(page + 1)}>Next</Button>
            </div>
          </div>
        </Loader>
      </Card>

      <Modal open={adding} title="Add income" onClose={() => setAdding(false)} wide>
        <AddIncomeForm depts={depts.data ?? []} sources={sources.data ?? []}
          onSaved={(r) => afterSave(r, 'Income saved')} />
      </Modal>

      <Modal open={Boolean(crediting)} title="Credit note" onClose={() => setCrediting(null)}>
        {crediting && <CreditNoteForm entry={crediting} onSaved={(r) => afterSave(r, 'Credit note saved')} />}
      </Modal>
    </>
  );
}

function AddIncomeForm({ depts, sources, onSaved }) {
  const [form, setForm] = useState({
    transDate: todayISO(), amount: '', mode: 'Bank Transfer', deptId: '', sourceId: '',
    payerName: '', payerGstin: '', placeOfSupply: '', referenceNo: '', beneficiaries: '',
    stayDays: '', tdsDeducted: '', description: '',
  });
  const [states, setStates] = useState([]);
  const [errors, setErrors] = useState({});
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  useEffect(() => { api.get('/meta/states').then(setStates).catch(() => {}); }, []);

  const set = (k) => (e) => setForm({ ...form, [k]: e.target.value });
  const source = sources.find((s) => String(s.Source_ID) === String(form.sourceId));
  const isHostel = source?.Special_Rule === 'ACCOMMODATION';
  const needsPayer = form.mode === 'Cash' || (source && source.TDS_Rate > 0);
  const gstPreview = source && !isHostel && form.amount ? (Number(form.amount) * source.Tax_Rate) / 100 : null;

  const submit = async (e) => {
    e.preventDefault();
    setBusy(true);
    setErrors({});
    setError('');
    try {
      const body = Object.fromEntries(Object.entries(form).filter(([, v]) => v !== ''));
      onSaved(await api.post('/university/transactions', body));
    } catch (err) {
      setErrors(fieldErrors(err));
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <form onSubmit={submit} className="space-y-4">
      <Alert>{error}</Alert>
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="Income source" error={errors.sourceId} className="sm:col-span-2"
          hint={source && `${source.Income_Type}: ${source.GST_Category.replace(/_/g, ' ').toLowerCase()}, GST ${source.Tax_Rate}%${source.TDS_Rate ? `, TDS ${source.TDS_Rate}%` : ''}. ${source.Conditions ?? ''}`}>
          <Select required value={form.sourceId} onChange={set('sourceId')} placeholder="Choose…"
            options={sources.map((s) => ({ value: s.Source_ID, label: `${s.Source_Name} — ${s.Income_Type}` }))} />
        </Field>
        <Field label="Department" error={errors.deptId}>
          <Select required value={form.deptId} onChange={set('deptId')} placeholder="Choose…"
            options={depts.map((d) => ({ value: d.Dept_ID, label: d.Name }))} />
        </Field>
        <Field label="Date" error={errors.transDate}>
          <Input type="date" required max={todayISO()} value={form.transDate} onChange={set('transDate')} />
        </Field>
        <Field label="Amount (before GST)" error={errors.amount}
          hint={gstPreview !== null ? `GST about ${money(gstPreview)}` : undefined}>
          <Input type="number" step="0.01" min="0.01" required value={form.amount} onChange={set('amount')} />
        </Field>
        <Field label="Received by" error={errors.mode}
          hint={form.mode === 'Cash' ? 'Cash of Rs 2 lakh or more is not allowed (Sec 186 / old 269ST)' : undefined}>
          <Select value={form.mode} onChange={set('mode')} options={['Bank Transfer', 'UPI', 'Cheque', 'Cash']} />
        </Field>
        <Field label={`Payer name${needsPayer ? ' (required)' : ''}`} error={errors.payerName}>
          <Input required={needsPayer} value={form.payerName} onChange={set('payerName')} />
        </Field>
        <Field label="Payer GSTIN (business clients)" error={errors.payerGstin}>
          <Input maxLength={15} className="uppercase" value={form.payerGstin}
            onChange={(e) => setForm({ ...form, payerGstin: e.target.value.toUpperCase() })} />
        </Field>
        <Field label="Client's state (if another state → IGST)" error={errors.placeOfSupply}>
          <Select value={form.placeOfSupply} onChange={set('placeOfSupply')} placeholder="Same state as university"
            options={states.map((s) => s.State_Name)} />
        </Field>
        <Field label="Invoice / event reference" error={errors.referenceNo}>
          <Input value={form.referenceNo} onChange={set('referenceNo')} />
        </Field>
        {isHostel && (
          <>
            <Field label="Number of students" error={errors.beneficiaries}>
              <Input type="number" min="1" required value={form.beneficiaries} onChange={set('beneficiaries')} />
            </Field>
            <Field label="Days covered" error={errors.stayDays}
              hint="Exempt if ≤ ₹20,000 per student per month for 90+ days">
              <Input type="number" min="1" required value={form.stayDays} onChange={set('stayDays')} />
            </Field>
          </>
        )}
        {source?.TDS_Rate > 0 && (
          <Field label="TDS deducted by client (optional)" error={errors.tdsDeducted}
            hint="From the client's TDS certificate. Leave empty to calculate.">
            <Input type="number" step="0.01" min="0" value={form.tdsDeducted} onChange={set('tdsDeducted')} />
          </Field>
        )}
        <Field label="Description" error={errors.description} className="sm:col-span-2">
          <Input value={form.description} onChange={set('description')} />
        </Field>
      </div>
      <div className="flex justify-end"><Button type="submit" loading={busy}>Save income</Button></div>
    </form>
  );
}

function CreditNoteForm({ entry, onSaved }) {
  const left = entry.Amount - entry.Credited;
  const [form, setForm] = useState({ amount: left, transDate: todayISO(), reason: '' });
  const [errors, setErrors] = useState({});
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const submit = async (e) => {
    e.preventDefault();
    setBusy(true);
    setError('');
    try {
      onSaved(await api.post(`/university/transactions/${entry.Trans_ID}/credit-note`, form));
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
        Entries can't be edited or deleted (audit trail). A credit note reverses all or part of
        entry #{entry.Trans_ID} ({entry.Source_Name}, {money(entry.Amount)}) and corrects that month's GST bill.
      </Alert>
      <Alert>{error}</Alert>
      <Field label={`Amount (at most ${money(left)})`} error={errors.amount}>
        <Input type="number" step="0.01" min="0.01" max={left} required value={form.amount}
          onChange={(e) => setForm({ ...form, amount: e.target.value })} />
      </Field>
      <Field label="Date" error={errors.transDate}>
        <Input type="date" required max={todayISO()} value={form.transDate}
          onChange={(e) => setForm({ ...form, transDate: e.target.value })} />
      </Field>
      <Field label="Reason" error={errors.reason}>
        <Textarea required value={form.reason} onChange={(e) => setForm({ ...form, reason: e.target.value })} />
      </Field>
      <div className="flex justify-end"><Button type="submit" loading={busy}>Save credit note</Button></div>
    </form>
  );
}
