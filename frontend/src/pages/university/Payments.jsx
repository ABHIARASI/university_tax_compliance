import { useState } from 'react';
import { useApi } from '../../hooks/useApi.js';
import { date, fyOf, money, todayISO } from '../../utils/format.js';
import { Badge, Card, Loader, PageHeader, Table } from '../../components/ui.jsx';
import FySelect from '../../components/FySelect.jsx';

export default function Payments() {
  const [fy, setFy] = useState(fyOf(todayISO()));
  const { data, loading, error } = useApi(`/university/stats/payments?fy=${fy}`);

  return (
    <>
      <PageHeader title="Payments" subtitle="GST and interest payments you recorded, and whether the tax office verified them."
        actions={<FySelect value={fy} onChange={setFy} />} />
      <Card>
        <Loader loading={loading} error={error}>
          <Table rowKey="Payment_ID" rows={data} empty="No payments in this financial year." columns={[
            { key: 'Payment_Date', label: 'Date', render: (r) => date(r.Payment_Date) },
            { key: 'Period', label: 'Bill' },
            { key: 'Payment_For', label: 'For' },
            { key: 'Reference_No', label: 'CIN' },
            { key: 'Mode', label: 'Mode' },
            { key: 'Amount', label: 'Amount', align: 'right', render: (r) => money(r.Amount) },
            { key: 'Status', label: 'Status', render: (r) => <Badge>{r.Status}</Badge> },
            { key: 'Remarks', label: 'Remarks' },
          ]} />
        </Loader>
      </Card>
    </>
  );
}
