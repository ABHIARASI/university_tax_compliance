// All "today" dates use India time, whatever timezone the server runs in.
export function todayIST() {
  // 'en-CA' formats dates as YYYY-MM-DD
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kolkata' }).format(new Date());
}

// '2026-02-15' -> '2025-26'   (Indian financial year: April to March)
export function financialYearOf(dateStr) {
  const [year, month] = dateStr.split('-').map(Number);
  const start = month < 4 ? year - 1 : year;
  return `${start}-${String((start + 1) % 100).padStart(2, '0')}`;
}

// '2025-26' -> { from: '2025-04-01', to: '2026-03-31' }
export function financialYearRange(fy) {
  const start = Number(fy.slice(0, 4));
  return { from: `${start}-04-01`, to: `${start + 1}-03-31` };
}
