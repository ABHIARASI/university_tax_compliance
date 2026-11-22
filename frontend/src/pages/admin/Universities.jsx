// Registrations and universities: approve / reject / suspend / reactivate.
import { useState } from 'react';
import { useNavigate } from 'react-router';
import { api } from '../../api/client.js';
import { useApi } from '../../hooks/useApi.js';
import { dateTime } from '../../utils/format.js';
import { Alert, Badge, Button, Card, Field, Loader, Modal, PageHeader, Table, Textarea } from '../../components/ui.jsx';

const TABS = ['PENDING', 'APPROVED', 'SUSPENDED', 'REJECTED', ''];

export default function Universities() {
  const navigate = useNavigate();
  const [tab, setTab] = useState('PENDING');
  const { data, loading, error, reload } = useApi(`/admin/universities${tab ? `?status=${tab}` : ''}`);
  const [action, setAction] = useState(null);   // { type: 'reject' | 'suspend', uni }
  const [message, setMessage] = useState({});

  const run = async (fn) => {
    setMessage({});
    try {
      const res = await fn();
      setMessage({ type: 'success', text: res.message });
      reload();
    } catch (err) {
      setMessage({ type: 'error', text: err.message });
    }
  };

  const columns = [
    { key: 'Name', label: 'University', render: (r) => (
      <div><p className="font-medium">{r.Name}</p><p className="text-xs text-slate-500">{r.Institution_Type} · {r.City ?? ''} {r.State}</p></div>
    ) },
    { key: 'GSTIN', label: 'GSTIN / PAN', render: (r) => <div><p>{r.GSTIN}</p><p className="text-xs text-slate-500">{r.PAN}</p></div> },
    { key: 'IT_Exemption', label: 'IT exemption' },
    { key: 'Contact_Person', label: 'Contact', render: (r) => <div><p>{r.Contact_Person}</p><p className="text-xs text-slate-500">{r.Email}</p></div> },
    { key: 'Registered_At', label: 'Registered', render: (r) => dateTime(r.Registered_At) },
    { key: 'Status', label: 'Status', render: (r) => (
      <div className="space-y-1">
        <Badge>{r.Status}</Badge>
        {r.Compliance && <div><Badge>{r.Compliance}</Badge></div>}
        {r.Status_Reason && <p className="max-w-48 text-xs text-slate-500">{r.Status_Reason}</p>}
      </div>
    ) },
    { key: 'actions', label: '', render: (r) => (
      <div className="flex flex-wrap gap-1" onClick={(e) => e.stopPropagation()}>
        {r.Status === 'PENDING' && (
          <>
            <Button size="sm" variant="success" onClick={() => run(() => api.patch(`/admin/universities/${r.Univ_ID}/approve`))}>Approve</Button>
            <Button size="sm" variant="danger" onClick={() => setAction({ type: 'reject', uni: r })}>Reject</Button>
          </>
        )}
        {r.Status === 'APPROVED' && (
          <Button size="sm" variant="secondary" onClick={() => setAction({ type: 'suspend', uni: r })}>Suspend</Button>
        )}
        {r.Status === 'SUSPENDED' && (
          <Button size="sm" variant="success" onClick={() => run(() => api.patch(`/admin/universities/${r.Univ_ID}/reactivate`))}>Reactivate</Button>
        )}
      </div>
    ) },
  ];

  return (
    <>
      <PageHeader title="Universities" subtitle="Check each new registration (GSTIN, details) before approving it." />
      <div className="mb-4 flex flex-wrap gap-2">
        {TABS.map((t) => (
          <button key={t || 'ALL'} onClick={() => setTab(t)}
            className={`rounded-full px-3 py-1 text-sm ${tab === t ? 'bg-brand-600 text-white' : 'bg-white text-slate-600 ring-1 ring-slate-200 hover:bg-slate-50'}`}>
            {t ? t[0] + t.slice(1).toLowerCase() : 'All'}
          </button>
        ))}
      </div>
      {message.text && <div className="mb-4"><Alert type={message.type}>{message.text}</Alert></div>}
      <Card>
        <Loader loading={loading} error={error}>
          <Table rowKey="Univ_ID" rows={data} columns={columns} empty="No universities here."
            onRowClick={(r) => r.Status !== 'PENDING' && r.Status !== 'REJECTED' && navigate(`/admin/universities/${r.Univ_ID}`)} />
        </Loader>
      </Card>

      <Modal open={Boolean(action)} title={action?.type === 'reject' ? 'Reject registration' : 'Suspend university'}
        onClose={() => setAction(null)}>
        {action && (
          <ReasonForm
            label={action.type === 'reject' ? 'Why is it rejected? (the university sees this)' : 'Why is it suspended? (its users are logged out at once)'}
            onSubmit={(reason) => run(() => api.patch(`/admin/universities/${action.uni.Univ_ID}/${action.type}`, { reason }))
              .then(() => setAction(null))}
          />
        )}
      </Modal>
    </>
  );
}

function ReasonForm({ label, onSubmit }) {
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  return (
    <div className="space-y-4">
      <Field label={label}><Textarea value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
      <Button variant="danger" loading={busy} disabled={reason.trim().length < 5}
        onClick={async () => { setBusy(true); await onSubmit(reason); setBusy(false); }}>
        Confirm
      </Button>
    </div>
  );
}
