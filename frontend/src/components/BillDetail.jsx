// One monthly GST bill: totals, the income entries behind it, its payments.
// Used by the university (its own bills) and the admin (any university).
import { useApi } from '../hooks/useApi.js';
import { date, money } from '../utils/format.js';
import { Badge, Loader, Table } from './ui.jsx';

export default function BillDetail({ path }) {
  const { data, loading, error } = useApi(path);

  return (
    <Loader loading={loading} error={error}>
      {data && (
        <div className="space-y-6">
          <div className="grid grid-cols-2 gap-3 text-sm sm:grid-cols-4">
            <Info label="Total income" value={money(data.bill.Total_Income)} />
            <Info label="Taxable income" value={money(data.bill.Taxable_Income)} />
            <Info label="CGST + SGST" value={money(data.bill.CGST + data.bill.SGST)} />
            <Info label="IGST" value={money(data.bill.IGST)} />
            <Info label="GST due" value={money(data.bill.Tax_Due)} />
            <Info label="GST paid" value={money(data.bill.Tax_Paid)} />
            <Info label="Due date" value={date(data.bill.Due_Date)} />
            <Info label="Interest (paid / charged)"
              value={`${money(data.bill.Interest_Paid)} / ${money(data.bill.Interest_Accrued)}`} />
          </div>

          <div>
            <h4 className="mb-2 text-sm font-semibold text-slate-800">Income in this bill</h4>
            <Table rowKey="Trans_ID" rows={data.entries} empty="No entries." columns={[
              { key: 'Trans_Date', label: 'Date', render: (r) => date(r.Trans_Date) },
              { key: 'Source_Name', label: 'Source', render: (r) => (
                <span>{r.Source_Name}{r.Entry_Type === 'CREDIT_NOTE' && <> <Badge>Credit note</Badge></>}</span>
              ) },
              { key: 'Payer_Name', label: 'Payer' },
              { key: 'Amount', label: 'Amount', align: 'right', render: (r) => money(r.Amount) },
              { key: 'GST_Rate', label: 'Rate', align: 'right', render: (r) => `${r.GST_Rate}%` },
              { key: 'GST_Amount', label: 'GST', align: 'right', render: (r) =>
                `${money(r.GST_Amount)}${r.Place_Of_Supply ? ' (IGST)' : ''}` },
            ]} />
          </div>

          <div>
            <h4 className="mb-2 text-sm font-semibold text-slate-800">Payments</h4>
            <Table rowKey="Payment_ID" rows={data.payments} empty="No payments yet." columns={[
              { key: 'Payment_Date', label: 'Date', render: (r) => date(r.Payment_Date) },
              { key: 'Payment_For', label: 'For' },
              { key: 'Reference_No', label: 'CIN' },
              { key: 'Mode', label: 'Mode' },
              { key: 'Amount', label: 'Amount', align: 'right', render: (r) => money(r.Amount) },
              { key: 'Status', label: 'Status', render: (r) => <Badge>{r.Status}</Badge> },
            ]} />
          </div>
        </div>
      )}
    </Loader>
  );
}

function Info({ label, value }) {
  return (
    <div className="rounded-lg bg-slate-50 p-3">
      <p className="text-xs text-slate-500">{label}</p>
      <p className="num mt-1 font-medium text-slate-900">{value}</p>
    </div>
  );
}
