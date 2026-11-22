// Chart components (Recharts). Each takes rows straight from a stats API.
import {
  Area, AreaChart, Bar, BarChart, CartesianGrid, Cell, ComposedChart, Legend, Line,
  Pie, PieChart, ResponsiveContainer, Tooltip, XAxis, YAxis,
} from 'recharts';
import { money, moneyShort, titleCase } from '../utils/format.js';
import { Empty } from './ui.jsx';

const C = {
  blue: '#2563eb', sky: '#38bdf8', indigo: '#6366f1', green: '#10b981',
  amber: '#f59e0b', red: '#ef4444', slate: '#94a3b8', violet: '#8b5cf6',
};
const STATUS_COLORS = {
  PAID: C.green, NIL: C.slate, DUE: C.blue, PARTIAL: C.amber, OVERDUE: C.red, INTEREST_DUE: C.violet,
  COMPLIANT: C.green, DUE_SOON: C.amber,
};
const tooltipMoney = (v) => money(v);

// income per month: taxable vs exempt (stacked area)
export function RevenueChart({ data }) {
  if (!data?.length) return <Empty>No income in this year.</Empty>;
  return (
    <ResponsiveContainer width="100%" height={280}>
      <AreaChart data={data} margin={{ left: 10, right: 10 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
        <XAxis dataKey="Month" tick={{ fontSize: 12 }} />
        <YAxis tickFormatter={moneyShort} tick={{ fontSize: 12 }} width={70} />
        <Tooltip formatter={tooltipMoney} />
        <Legend />
        <Area type="monotone" dataKey="Exempt_Income" name="Exempt / no GST" stackId="1" stroke={C.green} fill={C.green} fillOpacity={0.25} />
        <Area type="monotone" dataKey="Taxable_Income" name="Taxable" stackId="1" stroke={C.blue} fill={C.blue} fillOpacity={0.35} />
      </AreaChart>
    </ResponsiveContainer>
  );
}

// GST per month: CGST/SGST/IGST bars + paid line
export function TaxChart({ data }) {
  if (!data?.length) return <Empty>No GST bills in this year.</Empty>;
  return (
    <ResponsiveContainer width="100%" height={280}>
      <ComposedChart data={data} margin={{ left: 10, right: 10 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
        <XAxis dataKey="Month" tick={{ fontSize: 12 }} />
        <YAxis tickFormatter={moneyShort} tick={{ fontSize: 12 }} width={70} />
        <Tooltip formatter={tooltipMoney} />
        <Legend />
        <Bar dataKey="CGST" stackId="g" fill={C.blue} />
        <Bar dataKey="SGST" stackId="g" fill={C.sky} />
        <Bar dataKey="IGST" stackId="g" fill={C.indigo} />
        <Line type="monotone" dataKey="Tax_Paid" name="Paid" stroke={C.green} strokeWidth={2} dot={{ r: 3 }} />
      </ComposedChart>
    </ResponsiveContainer>
  );
}

// bills by status (donut)
export function StatusPie({ data, valueKey = 'Bills', nameKey = 'Status' }) {
  const rows = (data ?? []).filter((d) => d[valueKey] > 0);
  if (!rows.length) return <Empty>No bills in this year.</Empty>;
  return (
    <ResponsiveContainer width="100%" height={260}>
      <PieChart>
        <Pie data={rows} dataKey={valueKey} nameKey={nameKey} innerRadius={55} outerRadius={90} paddingAngle={2}
          label={({ value }) => value}>
          {rows.map((r) => <Cell key={r[nameKey]} fill={STATUS_COLORS[r[nameKey]] ?? C.slate} />)}
        </Pie>
        <Tooltip formatter={(v, n) => [v, titleCase(n)]} />
        <Legend formatter={(v) => titleCase(v)} />
      </PieChart>
    </ResponsiveContainer>
  );
}

// income by type (horizontal bars, coloured by GST treatment)
export function IncomeTypeChart({ data }) {
  if (!data?.length) return <Empty>No income in this year.</Empty>;
  const color = { EXEMPT: C.green, NOT_A_SUPPLY: C.slate, TAXABLE: C.blue };
  return (
    <ResponsiveContainer width="100%" height={Math.max(220, data.length * 34)}>
      <BarChart data={data} layout="vertical" margin={{ left: 20, right: 20 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
        <XAxis type="number" tickFormatter={moneyShort} tick={{ fontSize: 12 }} />
        <YAxis type="category" dataKey="Income_Type" width={170} tick={{ fontSize: 12 }} />
        <Tooltip formatter={tooltipMoney} />
        <Bar dataKey="Amount" name="Income">
          {data.map((r) => <Cell key={r.Income_Type} fill={color[r.GST_Category]} />)}
        </Bar>
      </BarChart>
    </ResponsiveContainer>
  );
}

// admin: GST due vs collected per month
export function CollectionChart({ data }) {
  if (!data?.length) return <Empty>No GST bills in this year.</Empty>;
  return (
    <ResponsiveContainer width="100%" height={280}>
      <BarChart data={data} margin={{ left: 10, right: 10 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
        <XAxis dataKey="Month" tick={{ fontSize: 12 }} />
        <YAxis tickFormatter={moneyShort} tick={{ fontSize: 12 }} width={70} />
        <Tooltip formatter={tooltipMoney} />
        <Legend />
        <Bar dataKey="Tax_Due" name="GST due" fill={C.blue} />
        <Bar dataKey="Tax_Paid" name="GST collected" fill={C.green} />
      </BarChart>
    </ResponsiveContainer>
  );
}
