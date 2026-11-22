// University home: headline numbers + the 4 charts.
// Calls the 6 stats endpoints for the chosen financial year.
import { useState } from 'react';
import { Link } from 'react-router';
import { useApi } from '../../hooks/useApi.js';
import { fyOf, money, todayISO } from '../../utils/format.js';
import { Alert, Badge, Card, Loader, PageHeader, StatCard } from '../../components/ui.jsx';
import FySelect from '../../components/FySelect.jsx';
import { IncomeTypeChart, RevenueChart, StatusPie, TaxChart } from '../../components/Charts.jsx';

export default function Dashboard() {
  const [fy, setFy] = useState(fyOf(todayISO()));
  const overview = useApi(`/university/stats/overview?fy=${fy}`);
  const revenue = useApi(`/university/stats/monthly-revenue?fy=${fy}`);
  const tax = useApi(`/university/stats/monthly-tax?fy=${fy}`);
  const status = useApi(`/university/stats/tax-status?fy=${fy}`);
  const byType = useApi(`/university/stats/income-by-type?fy=${fy}`);
  const o = overview.data;

  return (
    <>
      <PageHeader
        title="Dashboard"
        subtitle="GST position of your university for the financial year (April to March)"
        actions={<FySelect value={fy} onChange={setFy} />}
      />

      <Loader loading={overview.loading} error={overview.error}>
        {o && (
          <div className="space-y-6">
            {o.Compliance === 'OVERDUE' && (
              <Alert>
                You have overdue GST. Interest of 18% a year is being added every day.{' '}
                <Link to="/university/bills" className="font-medium underline">View bills and pay</Link>
              </Alert>
            )}

            <div className="flex items-center gap-2 text-sm text-slate-600">
              Compliance status: <Badge>{o.Compliance}</Badge>
            </div>

            <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
              <StatCard label="Total income" value={money(o.Total_Income)}
                hint={`${money(o.Exempt_Income)} exempt / no GST`} />
              <StatCard label="GST due" value={money(o.GST_Due)} hint={`${money(o.GST_Paid)} paid`} />
              <StatCard label="GST outstanding" value={money(o.Outstanding)} tone={o.Outstanding > 0 ? 'bad' : 'good'} />
              <StatCard label="Interest unpaid" value={money(o.Interest_Outstanding)}
                tone={o.Interest_Outstanding > 0 ? 'bad' : 'good'} hint={`${money(o.Interest_Accrued)} charged so far`} />
              <StatCard label="TDS refund claimable" value={money(o.TDS_Refund_Claimable)} tone="good"
                hint="Deducted by clients; claim it back" />
              <StatCard label="Unread alerts" value={o.Unread_Alerts} tone={o.Unread_Alerts ? 'warn' : 'default'} />
              <StatCard label="Open notices" value={o.Open_Notices} tone={o.Open_Notices ? 'warn' : 'default'} />
              <StatCard label="Payments being verified" value={o.Pending_Payments} />
            </div>

            <div className="grid gap-6 xl:grid-cols-2">
              <Card title="Income per month">
                <Loader loading={revenue.loading} error={revenue.error}><RevenueChart data={revenue.data} /></Loader>
              </Card>
              <Card title="GST per month (CGST / SGST / IGST) and paid">
                <Loader loading={tax.loading} error={tax.error}><TaxChart data={tax.data} /></Loader>
              </Card>
              <Card title="Bills by status">
                <Loader loading={status.loading} error={status.error}><StatusPie data={status.data} /></Loader>
              </Card>
              <Card title="Income by type">
                <Loader loading={byType.loading} error={byType.error}><IncomeTypeChart data={byType.data} /></Loader>
              </Card>
            </div>
          </div>
        )}
      </Loader>
    </>
  );
}
