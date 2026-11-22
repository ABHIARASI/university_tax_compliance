// Small reusable UI pieces, styled with Tailwind, used by every page.
import { useEffect } from 'react';
import { titleCase } from '../utils/format.js';

export function PageHeader({ title, subtitle, actions }) {
  return (
    <div className="mb-6 flex flex-wrap items-end justify-between gap-3">
      <div>
        <h1 className="text-2xl font-semibold text-slate-900">{title}</h1>
        {subtitle && <p className="mt-1 text-sm text-slate-500">{subtitle}</p>}
      </div>
      {actions && <div className="flex flex-wrap items-center gap-2">{actions}</div>}
    </div>
  );
}

export function Card({ title, actions, children, className = '' }) {
  return (
    <section className={`rounded-xl border border-slate-200 bg-white shadow-sm ${className}`}>
      {(title || actions) && (
        <div className="flex items-center justify-between border-b border-slate-100 px-5 py-3">
          <h2 className="font-medium text-slate-800">{title}</h2>
          {actions}
        </div>
      )}
      <div className="p-5">{children}</div>
    </section>
  );
}

const TONES = {
  default: 'text-slate-900',
  good: 'text-emerald-600',
  warn: 'text-amber-600',
  bad: 'text-rose-600',
};

export function StatCard({ label, value, hint, tone = 'default' }) {
  return (
    <div className="rounded-xl border border-slate-200 bg-white p-4 shadow-sm">
      <p className="text-xs font-medium uppercase tracking-wide text-slate-500">{label}</p>
      <p className={`num mt-2 text-2xl font-semibold ${TONES[tone]}`}>{value}</p>
      {hint && <p className="mt-1 text-xs text-slate-500">{hint}</p>}
    </div>
  );
}

const BADGE_COLORS = {
  green: 'bg-emerald-50 text-emerald-700 ring-emerald-600/20',
  red: 'bg-rose-50 text-rose-700 ring-rose-600/20',
  amber: 'bg-amber-50 text-amber-700 ring-amber-600/20',
  blue: 'bg-blue-50 text-blue-700 ring-blue-600/20',
  slate: 'bg-slate-100 text-slate-700 ring-slate-500/20',
  violet: 'bg-violet-50 text-violet-700 ring-violet-600/20',
};

// one colour per known status word, so the same status looks the same everywhere
const STATUS_COLOR = {
  PAID: 'green', COMPLIANT: 'green', APPROVED: 'green', VERIFIED: 'green', CLOSED: 'slate',
  REVIEWED: 'green', RESPONDED: 'blue', NIL: 'slate', EXEMPT: 'green', NOT_A_SUPPLY: 'slate',
  TAXABLE: 'blue', INVOICE: 'slate', CREDIT_NOTE: 'violet', DUE: 'blue', PARTIAL: 'amber',
  DUE_SOON: 'amber', DUE_TODAY: 'amber', PENDING: 'amber', OPEN: 'amber', MEDIUM: 'amber',
  OVERDUE: 'red', INTEREST_DUE: 'red', REJECTED: 'red', SUSPENDED: 'red', HIGH: 'red',
  DISMISSED: 'slate', LOW: 'slate',
};

export function Badge({ children, color }) {
  const key = String(children ?? '').toUpperCase().replace(/ /g, '_');
  const c = BADGE_COLORS[color ?? STATUS_COLOR[key] ?? 'slate'];
  return (
    <span className={`inline-flex items-center whitespace-nowrap rounded-full px-2 py-0.5 text-xs font-medium ring-1 ring-inset ${c}`}>
      {titleCase(String(children ?? ''))}
    </span>
  );
}

const BUTTONS = {
  primary: 'bg-brand-600 text-white hover:bg-brand-700',
  secondary: 'border border-slate-300 bg-white text-slate-700 hover:bg-slate-50',
  danger: 'bg-rose-600 text-white hover:bg-rose-700',
  success: 'bg-emerald-600 text-white hover:bg-emerald-700',
  ghost: 'text-brand-700 hover:bg-brand-50',
};

export function Button({ variant = 'primary', size = 'md', loading, children, className = '', ...props }) {
  const sizes = size === 'sm' ? 'px-2.5 py-1 text-xs' : 'px-4 py-2 text-sm';
  return (
    <button
      {...props}
      disabled={loading || props.disabled}
      className={`inline-flex items-center justify-center gap-2 rounded-lg font-medium transition disabled:cursor-not-allowed disabled:opacity-50 ${sizes} ${BUTTONS[variant]} ${className}`}
    >
      {loading && <span className="h-3.5 w-3.5 animate-spin rounded-full border-2 border-current border-t-transparent" />}
      {children}
    </button>
  );
}

const inputClass =
  'w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm shadow-sm outline-none transition focus:border-brand-500 focus:ring-2 focus:ring-brand-100 disabled:bg-slate-100';

// label + input/select/textarea + hint + the error for this field
export function Field({ label, error, hint, children, className = '' }) {
  return (
    <label className={`block ${className}`}>
      <span className="mb-1 block text-sm font-medium text-slate-700">{label}</span>
      {children}
      {hint && !error && <span className="mt-1 block text-xs text-slate-500">{hint}</span>}
      {error && <span className="mt-1 block text-xs text-rose-600">{error}</span>}
    </label>
  );
}

export const Input = (props) => <input {...props} className={`${inputClass} ${props.className ?? ''}`} />;
export const Textarea = (props) => <textarea rows={4} {...props} className={`${inputClass} ${props.className ?? ''}`} />;
export function Select({ options, placeholder, ...props }) {
  return (
    <select {...props} className={`${inputClass} ${props.className ?? ''}`}>
      {placeholder !== undefined && <option value="">{placeholder}</option>}
      {options.map((o) =>
        typeof o === 'string'
          ? <option key={o} value={o}>{o}</option>
          : <option key={o.value} value={o.value}>{o.label}</option>
      )}
    </select>
  );
}

export function Alert({ type = 'error', children }) {
  if (!children) return null;
  const styles = {
    error: 'border-rose-200 bg-rose-50 text-rose-800',
    success: 'border-emerald-200 bg-emerald-50 text-emerald-800',
    info: 'border-blue-200 bg-blue-50 text-blue-800',
    warn: 'border-amber-200 bg-amber-50 text-amber-800',
  };
  return <div className={`rounded-lg border px-4 py-3 text-sm ${styles[type]}`}>{children}</div>;
}

export function Spinner({ label = 'Loading…' }) {
  return (
    <div className="flex items-center justify-center gap-3 py-12 text-sm text-slate-500">
      <span className="h-5 w-5 animate-spin rounded-full border-2 border-brand-500 border-t-transparent" />
      {label}
    </div>
  );
}

export function Empty({ children = 'Nothing here yet.' }) {
  return <p className="py-10 text-center text-sm text-slate-500">{children}</p>;
}

// loading / error / content in one wrapper
export function Loader({ loading, error, children }) {
  if (loading) return <Spinner />;
  if (error) return <Alert>{error.message}</Alert>;
  return children;
}

// columns: [{ key, label, render?(row), align? }]
export function Table({ columns, rows, empty, onRowClick, rowKey }) {
  if (!rows?.length) return <Empty>{empty}</Empty>;
  return (
    <div className="-mx-5 overflow-x-auto">
      <table className="min-w-full text-sm">
        <thead>
          <tr className="border-b border-slate-200 text-left text-xs uppercase tracking-wide text-slate-500">
            {columns.map((c) => (
              <th key={c.key} className={`whitespace-nowrap px-5 py-2 font-medium ${c.align === 'right' ? 'text-right' : ''}`}>
                {c.label}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-slate-100">
          {rows.map((r, i) => (
            <tr
              key={rowKey ? r[rowKey] : i}
              onClick={onRowClick ? () => onRowClick(r) : undefined}
              className={onRowClick ? 'cursor-pointer hover:bg-slate-50' : ''}
            >
              {columns.map((c) => (
                <td key={c.key} className={`px-5 py-2.5 align-top ${c.align === 'right' ? 'num text-right' : ''}`}>
                  {c.render ? c.render(r) : r[c.key] ?? '—'}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function Modal({ open, title, onClose, children, wide }) {
  useEffect(() => {
    if (!open) return;
    const onKey = (e) => e.key === 'Escape' && onClose();
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, onClose]);

  if (!open) return null;
  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-slate-900/40 p-4 sm:p-10" onMouseDown={onClose}>
      <div
        className={`w-full ${wide ? 'max-w-4xl' : 'max-w-lg'} rounded-xl bg-white shadow-xl`}
        onMouseDown={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between border-b border-slate-100 px-5 py-3">
          <h3 className="font-semibold text-slate-900">{title}</h3>
          <button onClick={onClose} className="rounded p-1 text-slate-400 hover:bg-slate-100 hover:text-slate-600" aria-label="Close">✕</button>
        </div>
        <div className="p-5">{children}</div>
      </div>
    </div>
  );
}

// turn an ApiError's field list into { fieldName: message }
export function fieldErrors(err) {
  const map = {};
  for (const f of err?.fields ?? []) if (!map[f.field]) map[f.field] = f.message;
  return map;
}
