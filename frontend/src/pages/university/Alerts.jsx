// Automatic alerts created every morning by the daily job.
import { useState } from 'react';
import { api } from '../../api/client.js';
import { useApi } from '../../hooks/useApi.js';
import { date } from '../../utils/format.js';
import { Badge, Button, Card, Empty, Loader, PageHeader } from '../../components/ui.jsx';

export default function Alerts() {
  const [onlyUnread, setOnlyUnread] = useState(false);
  const { data, loading, error, reload } = useApi(`/university/alerts${onlyUnread ? '?unread=true' : ''}`);

  const markRead = async (id) => { await api.patch(`/university/alerts/${id}/read`); reload(); };
  const markAll = async () => { await api.patch('/university/alerts/read-all'); reload(); };

  return (
    <>
      <PageHeader
        title="Alerts"
        subtitle="Sent automatically: 7, 3 and 1 day before a due date, on the due date, and every day after it until GST and interest are paid."
        actions={
          <>
            <label className="flex items-center gap-2 text-sm text-slate-600">
              <input type="checkbox" checked={onlyUnread} onChange={(e) => setOnlyUnread(e.target.checked)} />
              Unread only
            </label>
            <Button variant="secondary" onClick={markAll}>Mark all as read</Button>
          </>
        }
      />
      <Card>
        <Loader loading={loading} error={error}>
          {!data?.length ? <Empty>No alerts.</Empty> : (
            <ul className="divide-y divide-slate-100">
              {data.map((a) => (
                <li key={a.Alert_ID} className={`flex items-start justify-between gap-4 py-3 ${a.Is_Read ? 'opacity-60' : ''}`}>
                  <div>
                    <div className="flex items-center gap-2">
                      <Badge>{a.Alert_Type}</Badge>
                      <span className="text-xs text-slate-500">{date(a.Alert_Date)} · {a.Period} bill</span>
                      {!a.Is_Read && <span className="h-2 w-2 rounded-full bg-rose-500" />}
                    </div>
                    <p className="mt-1 text-sm text-slate-800">{a.Message}</p>
                  </div>
                  {!a.Is_Read && <Button size="sm" variant="ghost" onClick={() => markRead(a.Alert_ID)}>Mark read</Button>}
                </li>
              ))}
            </ul>
          )}
        </Loader>
      </Card>
    </>
  );
}
