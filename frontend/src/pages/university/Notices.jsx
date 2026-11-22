// Notices from the tax office, and the university's replies.
import { useState } from 'react';
import { api } from '../../api/client.js';
import { useApi } from '../../hooks/useApi.js';
import { date, dateTime } from '../../utils/format.js';
import { Alert, Badge, Button, Card, Empty, Loader, PageHeader, Textarea } from '../../components/ui.jsx';

export default function Notices() {
  const { data, loading, error, reload } = useApi('/university/notices');

  return (
    <>
      <PageHeader title="Notices" subtitle="Messages from the tax office. Reply to open notices before the response date." />
      <Loader loading={loading} error={error}>
        {!data?.length ? <Card><Empty>No notices.</Empty></Card> : (
          <div className="space-y-4">
            {data.map((n) => <NoticeCard key={n.Notice_ID} notice={n} onReplied={reload} />)}
          </div>
        )}
      </Loader>
    </>
  );
}

function NoticeCard({ notice: n, onReplied }) {
  const [reply, setReply] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const send = async () => {
    setBusy(true);
    setError('');
    try {
      await api.patch(`/university/notices/${n.Notice_ID}/respond`, { response: reply });
      onReplied();
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Card>
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <div className="flex items-center gap-2">
            <Badge color="blue">{n.Type}</Badge>
            <Badge>{n.Status}</Badge>
          </div>
          <h3 className="mt-2 font-semibold text-slate-900">{n.Subject}</h3>
          <p className="text-xs text-slate-500">
            From {n.Issued_By_Name} on {dateTime(n.Issued_At)}{n.Period ? ` · about the ${n.Period} bill` : ''}
          </p>
        </div>
        {n.Response_Due && <p className="text-sm text-slate-600">Reply by <b>{date(n.Response_Due)}</b></p>}
      </div>
      <p className="mt-3 whitespace-pre-line text-sm text-slate-800">{n.Message}</p>

      {n.Response ? (
        <div className="mt-4 rounded-lg bg-slate-50 p-3 text-sm">
          <p className="text-xs font-medium text-slate-500">Your reply · {dateTime(n.Responded_At)}</p>
          <p className="mt-1 whitespace-pre-line">{n.Response}</p>
        </div>
      ) : n.Status === 'Open' && (
        <div className="mt-4 space-y-2">
          <Alert>{error}</Alert>
          <Textarea placeholder="Write your reply…" value={reply} onChange={(e) => setReply(e.target.value)} />
          <Button onClick={send} loading={busy} disabled={reply.trim().length < 5}>Send reply</Button>
        </div>
      )}
    </Card>
  );
}
