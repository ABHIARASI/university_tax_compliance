// Financial-year dropdown (April-March), e.g. 2026-27
import { fyOptions } from '../utils/format.js';

export default function FySelect({ value, onChange }) {
  return (
    <select
      value={value}
      onChange={(e) => onChange(e.target.value)}
      className="rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm shadow-sm"
      aria-label="Financial year"
    >
      {fyOptions().map((fy) => <option key={fy} value={fy}>FY {fy}</option>)}
    </select>
  );
}
