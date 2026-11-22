// Load data from the API for a page:
//   const { data, loading, error, reload } = useApi('/university/stats/overview?fy=2025-26');
// Re-loads automatically whenever the path changes (e.g. a different year).
// Pass null as the path to skip loading.
import { useCallback, useEffect, useState } from 'react';
import { api } from '../api/client.js';

export function useApi(path) {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(Boolean(path));
  const [error, setError] = useState(null);
  const [version, setVersion] = useState(0);

  useEffect(() => {
    if (!path) return;
    let cancelled = false;          // ignore an old answer if the path changed meanwhile
    setLoading(true);
    setError(null);
    api.get(path)
      .then((d) => { if (!cancelled) setData(d); })
      .catch((e) => { if (!cancelled) setError(e); })
      .finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, [path, version]);

  const reload = useCallback(() => setVersion((v) => v + 1), []);
  return { data, loading, error, reload, setData };
}
