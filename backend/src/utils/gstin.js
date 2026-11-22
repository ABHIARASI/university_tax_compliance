// Same check-digit algorithm as the SQL function Is_Valid_GSTIN.
// Checked here too, so the user gets a clear message before anything
// reaches the database (the database still checks again - defence in depth).
const CHARS = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const FORMAT = /^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/;

export function isValidGSTIN(gstin) {
  if (typeof gstin !== 'string' || !FORMAT.test(gstin)) return false;
  let total = 0;
  for (let i = 0; i < 14; i++) {
    const product = CHARS.indexOf(gstin[i]) * (i % 2 === 0 ? 1 : 2);
    total += Math.floor(product / 36) + (product % 36);
  }
  return CHARS[(36 - (total % 36)) % 36] === gstin[14];
}
