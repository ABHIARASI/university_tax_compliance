// Anomalies the system flagged on this university's entries (transparency).
import { useApi } from '../../hooks/useApi.js';
import { dateTime } from '../../utils/format.js';
import { Badge, Card, Loader, PageHeader, Table } from '../../components/ui.jsx';

const RULES = {
  CASH_LIMIT: 'Cash of ₹2 lakh or more (Sec 186, IT Act 2025)',
  SPIKE: 'Much larger than usual',
  DUPLICATE: 'Looks like a repeated entry',
  OVERPAYMENT: 'Paid more than was due',
  TDS_MISMATCH: "Client's TDS differs from the expected amount",
};

export default function Flags() {
  const { data, loading, error } = useApi('/university/anomalies');
  return (
    <>
      <PageHeader title="Flags" subtitle="Entries the system flagged automatically. The tax office reviews each one." />
      <Card>
        <Loader loading={loading} error={error}>
          <Table rowKey="Anomaly_ID" rows={data} empty="Nothing flagged." columns={[
            { key: 'Detected_At', label: 'When', render: (r) => dateTime(r.Detected_At) },
            { key: 'Rule_Code', label: 'Rule', render: (r) => (
              <div><p className="font-medium">{r.Rule_Code.replace('_', ' ')}</p><p className="text-xs text-slate-500">{RULES[r.Rule_Code]}</p></div>
            ) },
            { key: 'Severity', label: 'Severity', render: (r) => <Badge>{r.Severity}</Badge> },
            { key: 'Details', label: 'Details' },
            { key: 'Status', label: 'Status', render: (r) => <Badge>{r.Status}</Badge> },
          ]} />
        </Loader>
      </Card>
    </>
  );
}
