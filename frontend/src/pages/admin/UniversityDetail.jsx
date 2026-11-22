// One university, as the tax office sees it: profile, numbers, bills, charts.
import { useState } from 'react';
import { Link, useParams } from 'react-router';
import { useApi } from '../../hooks/useApi.js';
import { date, fyOf, money, todayISO } from '../../utils/format.js';
import { Badge, Card, Loader, Modal, PageHeader, StatCard, Table } from '../../components/ui.jsx';
import FySelect from '../../components/FySelect.jsx';
import BillDetail from '../../components/BillDetail.jsx';
import { IncomeTypeChart, RevenueChart } from '../../components/Charts.jsx';

export default function UniversityDetail() {
  const { id } = useParams();
  const [fy, setFy] = useState(fyOf(todayISO()));
  const { data, loading, error } = useApi(`/admin/universities/${id}?fy=${fy}`);
  const [viewing, setViewing] = useState(null);
  const u = data?.university;
  const o = data?.overview;

  return (
    <Loader loading={loading && !data} error={error}>
      {u && (
        <>
          <PageHeader
            title={u.Name}
            subtitle={`${u.GSTIN} · ${u.Institution_Type} · ${u.City ?? ''} ${u.State} · ${u.IT_Exemption}`}
            actions={
              <>
                <Badge>{u.Status}</Badge>
                {o && <Badge>{o.Compliance}</Badge>}
                <FySelect value={fy} onChange={setFy} />
                <Link to={`/admin/notices?univId=${u.Univ_ID}`} className="rounded-lg bg-brand-600 px-4 py-2 text-sm font-medium text-white hover:bg-brand-700">
                  Send notice
                </Link>
              </>
            }
          />
          {o && (
            <div className="mb-6 grid grid-cols-2 gap-4 lg:grid-cols-4">
              <StatCard label="Total income" value={money(o.Total_Income)} />
              <StatCard label="GST due / paid" value={money(o.GST_Due)} hint={`${money(o.GST_Paid)} paid`} />
              <StatCard label="Outstanding" value={money(o.Outstanding)} tone={o.Outstanding ? 'bad' : 'good'} />
              <StatCard label="Interest unpaid" value={money(o.Interest_Outstanding)} tone={o.Interest_Outstanding ? 'bad' : 'good'} />
            </div>
          )}

          <div className="space-y-6">
            <Card title="Monthly GST bills">
              <Table rowKey="Tax_ID" rows={data.bills} onRowClick={setViewing} empty="No bills in this year." columns={[
                { key: 'Period', label: 'Month' },
                { key: 'Tax_Due', label: 'GST due', align: 'right', render: (r) => money(r.Tax_Due) },
                { key: 'Tax_Paid', label: 'Paid', align: 'right', render: (r) => money(r.Tax_Paid) },
                { key: 'Tax_Outstanding', label: 'Outstanding', align: 'right', render: (r) => money(r.Tax_Outstanding) },
                { key: 'Interest_Outstanding', label: 'Interest due', align: 'right', render: (r) => money(r.Interest_Outstanding) },
                { key: 'Due_Date', label: 'Due', render: (r) => date(r.Due_Date) },
                { key: 'Status', label: 'Status', render: (r) => <Badge>{r.Status}</Badge> },
              ]} />
            </Card>
            <div className="grid gap-6 xl:grid-cols-2">
              <Card title="Income per month"><RevenueChart data={data.monthlyRevenue} /></Card>
              <Card title="Income by type"><IncomeTypeChart data={data.incomeByType} /></Card>
            </div>
          </div>

          <Modal open={Boolean(viewing)} title={`${u.Name} — ${viewing?.Period ?? ''}`} onClose={() => setViewing(null)} wide>
            {viewing && <BillDetail path={`/admin/universities/${u.Univ_ID}/tax-records/${viewing.Tax_ID}`} />}
          </Modal>
        </>
      )}
    </Loader>
  );
}
