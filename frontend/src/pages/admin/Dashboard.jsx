// Tax office home: workload, GST collected, compliance of every university.
import { useState } from 'react';
import { Link, useNavigate } from 'react-router';
import { useApi } from '../../hooks/useApi.js';
import { fyOf, money, todayISO } from '../../utils/format.js';
import { Badge, Card, Loader, PageHeader, StatCard, Table } from '../../components/ui.jsx';
import FySelect from '../../components/FySelect.jsx';
import { CollectionChart, StatusPie } from '../../components/Charts.jsx';

export default function AdminDashboard() {
  const navigate = useNavigate();
  const [fy, setFy] = useState(fyOf(todayISO()));
  const overview = useApi('/admin/stats/overview');
  const monthly = useApi(`/admin/stats/monthly-collection?fy=${fy}`);
  const compliance = useApi('/admin/compliance');
  const o = overview.data;

  const pie = o
    ? Object.entries(o.Compliance_Split).map(([Status, Universities]) => ({ Status, Universities }))
    : [];

  return (
    <>
      <PageHeader title="Tax office dashboard" subtitle="All universities at a glance"
        actions={<FySelect value={fy} onChange={setFy} />} />

      <Loader loading={overview.loading} error={overview.error}>
        {o && (
          <div className="space-y-6">
            <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
              <Link to="/admin/universities"><StatCard label="Registrations to review" value={o.Pending_Registrations} tone={o.Pending_Registrations ? 'warn' : 'default'} /></Link>
              <Link to="/admin/payments"><StatCard label="Payments to verify" value={o.Payments_To_Verify} tone={o.Payments_To_Verify ? 'warn' : 'default'} /></Link>
              <Link to="/admin/anomalies"><StatCard label="Open anomalies" value={o.Open_Anomalies} tone={o.Open_Anomalies ? 'bad' : 'default'} /></Link>
              <Link to="/admin/notices"><StatCard label="Replies to read" value={o.Notices_Awaiting_Review} /></Link>
              <StatCard label="Active universities" value={o.Active_Universities} hint={`${o.Suspended_Universities} suspended`} />
              <StatCard label="GST collected (all time)" value={money(o.Total_GST_Collected)} tone="good" hint={`of ${money(o.Total_GST_Due)} due`} />
              <StatCard label="GST outstanding" value={money(o.Tax_Outstanding)} tone={o.Tax_Outstanding ? 'bad' : 'good'} />
              <StatCard label="Interest outstanding" value={money(o.Interest_Outstanding)} tone={o.Interest_Outstanding ? 'bad' : 'good'} />
            </div>

            <div className="grid gap-6 xl:grid-cols-3">
              <Card title="GST due vs collected" className="xl:col-span-2">
                <Loader loading={monthly.loading} error={monthly.error}><CollectionChart data={monthly.data} /></Loader>
              </Card>
              <Card title="Universities by compliance">
                <StatusPie data={pie} valueKey="Universities" />
              </Card>
            </div>

            <Card title="Compliance of approved universities">
              <Loader loading={compliance.loading} error={compliance.error}>
                <Table rowKey="Univ_ID" rows={compliance.data} onRowClick={(r) => navigate(`/admin/universities/${r.Univ_ID}`)}
                  columns={[
                    { key: 'University', label: 'University', render: (r) => <span className="font-medium">{r.University}</span> },
                    { key: 'GSTIN', label: 'GSTIN' },
                    { key: 'State', label: 'State' },
                    { key: 'Overdue_Bills', label: 'Overdue bills', align: 'right' },
                    { key: 'Tax_Outstanding', label: 'GST outstanding', align: 'right', render: (r) => money(r.Tax_Outstanding) },
                    { key: 'Interest_Outstanding', label: 'Interest', align: 'right', render: (r) => money(r.Interest_Outstanding) },
                    { key: 'Compliance', label: 'Status', render: (r) => <Badge>{r.Compliance}</Badge> },
                  ]} />
              </Loader>
            </Card>
          </div>
        )}
      </Loader>
    </>
  );
}
