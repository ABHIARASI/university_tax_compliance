// Everything the rules flagged: review, dismiss, or ask the university to explain.
import { useState } from 'react';
import { useNavigate } from 'react-router';
import { api } from '../../api/client.js';
import { useApi } from '../../hooks/useApi.js';
import { date, dateTime, money } from '../../utils/format.js';
import { Alert, Badge, Button, Card, Loader, PageHeader, Table } from '../../components/ui.jsx';

export default function Anomalies() {
  const navigate = useNavigate();
  const [status, setStatus] = useState('Open');
  const [rule, setRule] = useState('');
  const qs = new URLSearchParams({ ...(status && { status }), ...(rule && { rule }) }).toString();
  const { data, loading, error, reload } = useApi(`/admin/anomalies${qs ? `?${qs}` : ''}`);
  const [message, setMessage] = useState({});

  const mark = async (id, s) => {
    try {
      const res = await api.patch(`/admin/anomalies/${id}`, { status: s });
      setMessage({ type: 'success', text: res.message });
      reload();
    } catch (err) {
      setMessage({ type: 'error', text: err.message });
    }
  };

  return (
    <>
      <PageHeader title="Anomalies" subtitle="Flagged automatically by database triggers when income or payments are saved."
        actions={
          <>
            <select value={rule} onChange={(e) => setRule(e.target.value)} className="rounded-lg border border-slate-300 px-3 py-2 text-sm">
              <option value="">All rules</option>
              {['CASH_LIMIT', 'SPIKE', 'DUPLICATE', 'OVERPAYMENT', 'TDS_MISMATCH'].map((r) => <option key={r}>{r}</option>)}
            </select>
            <select value={status} onChange={(e) => setStatus(e.target.value)} className="rounded-lg border border-slate-300 px-3 py-2 text-sm">
              <option value="Open">Open</option><option value="Reviewed">Reviewed</option>
              <option value="Dismissed">Dismissed</option><option value="">All</option>
            </select>
          </>
        } />
      {message.text && <div className="mb-4"><Alert type={message.type}>{message.text}</Alert></div>}
      <Card>
        <Loader loading={loading} error={error}>
          <Table rowKey="Anomaly_ID" rows={data} empty="No anomalies here." columns={[
            { key: 'University', label: 'University', render: (r) => <span className="font-medium">{r.University}</span> },
            { key: 'Rule_Code', label: 'Rule', render: (r) => <div><Badge color="violet">{r.Rule_Code}</Badge><div className="mt-1"><Badge>{r.Severity}</Badge></div></div> },
            { key: 'Details', label: 'Details', render: (r) => (
              <div className="max-w-md">
                <p>{r.Details}</p>
                {r.Trans_Date && <p className="mt-1 text-xs text-slate-500">Entry of {date(r.Trans_Date)} · {money(r.Trans_Amount)} · {r.Mode} · {r.Payer_Name ?? ''}</p>}
              </div>
            ) },
            { key: 'Detected_At', label: 'Detected', render: (r) => dateTime(r.Detected_At) },
            { key: 'Status', label: 'Status', render: (r) => <div><Badge>{r.Status}</Badge>{r.Reviewed_By_Name && <p className="text-xs text-slate-500">by {r.Reviewed_By_Name}</p>}</div> },
            { key: 'actions', label: '', render: (r) => r.Status === 'Open' && (
              <div className="flex flex-wrap gap-1">
                <Button size="sm" variant="secondary"
                  onClick={() => navigate(`/admin/notices?univId=${r.Univ_ID}&anomalyId=${r.Anomaly_ID}`)}>Ask to explain</Button>
                <Button size="sm" variant="success" onClick={() => mark(r.Anomaly_ID, 'Reviewed')}>Reviewed</Button>
                <Button size="sm" variant="ghost" onClick={() => mark(r.Anomaly_ID, 'Dismissed')}>Dismiss</Button>
              </div>
            ) },
          ]} />
        </Loader>
      </Card>
    </>
  );
}
