// Display helpers (Indian formats)

const inr = new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 2 });
const inrShort = new Intl.NumberFormat('en-IN', { maximumFractionDigits: 1 });

// 1234567.5 -> ₹12,34,567.50
export const money = (n) => (n === null || n === undefined ? '—' : inr.format(n));

// 1234567 -> ₹12.3 L   |  23400000 -> ₹2.3 Cr   (for chart axes and cards)
export function moneyShort(n) {
  if (n === null || n === undefined) return '—';
  const abs = Math.abs(n);
  if (abs >= 1e7) return `₹${inrShort.format(n / 1e7)} Cr`;
  if (abs >= 1e5) return `₹${inrShort.format(n / 1e5)} L`;
  if (abs >= 1e3) return `₹${inrShort.format(n / 1e3)} K`;
  return `₹${inrShort.format(n)}`;
}

// '2026-11-20' or '2026-11-20 10:15:00' -> 20 Nov 2026
export function date(s) {
  if (!s) return '—';
  const d = new Date(s.length === 10 ? `${s}T00:00:00` : s.replace(' ', 'T'));
  return d.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });
}

export function dateTime(s) {
  if (!s) return '—';
  const d = new Date(s.replace(' ', 'T'));
  return d.toLocaleString('en-IN', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' });
}

// today in India as YYYY-MM-DD
export const todayISO = () =>
  new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kolkata' }).format(new Date());

// '2026-02-15' -> '2025-26'
export function fyOf(isoDate) {
  const [y, m] = isoDate.split('-').map(Number);
  const start = m < 4 ? y - 1 : y;
  return `${start}-${String((start + 1) % 100).padStart(2, '0')}`;
}

// the current FY and the 3 before it, newest first
export function fyOptions() {
  const current = Number(fyOf(todayISO()).slice(0, 4));
  return [0, 1, 2, 3].map((i) => {
    const s = current - i;
    return `${s}-${String((s + 1) % 100).padStart(2, '0')}`;
  });
}

export const titleCase = (s) =>
  s ? s.toLowerCase().replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase()) : '';
