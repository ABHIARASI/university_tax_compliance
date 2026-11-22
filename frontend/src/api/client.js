// The ONE place the frontend talks to the backend.
//   api.get('/university/tax-records?fy=2025-26')
//   api.post('/auth/login', { email, password })
// - sends and receives JSON
// - `credentials: 'include'` makes the browser send the httpOnly login cookie
//   (JavaScript never sees the token itself)
// - any non-2xx response becomes an ApiError with the server's message
// - a 401 anywhere means "session over" -> tell the app to log out
export class ApiError extends Error {
  constructor(status, message, fields = []) {
    super(message);
    this.status = status;
    this.fields = fields;   // [{ field, message }] from Zod validation
  }
}

async function request(method, path, body) {
  const res = await fetch(`/api${path}`, {
    method,
    credentials: 'include',
    headers: body !== undefined ? { 'Content-Type': 'application/json' } : undefined,
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });

  const data = await res.json().catch(() => ({}));

  if (!res.ok) {
    if (res.status === 401 && !path.startsWith('/auth/login')) {
      window.dispatchEvent(new Event('session-expired'));
    }
    throw new ApiError(res.status, data.error ?? `Request failed (${res.status})`, data.fields ?? []);
  }
  return data;
}

export const api = {
  get: (path) => request('GET', path),
  post: (path, body = {}) => request('POST', path, body),
  patch: (path, body = {}) => request('PATCH', path, body),
};
