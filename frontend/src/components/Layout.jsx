// The frame around every logged-in page: sidebar menu (by role) + top bar.
import { useEffect, useState } from 'react';
import { Link, NavLink, Outlet, useLocation, useNavigate } from 'react-router';
import { useAuth } from '../context/AuthContext.jsx';
import { api } from '../api/client.js';

const MENUS = {
  UNIVERSITY: [
    { to: '/university', label: 'Dashboard', end: true },
    { to: '/university/income', label: 'Income' },
    { to: '/university/bills', label: 'GST Bills' },
    { to: '/university/payments', label: 'Payments' },
    { to: '/university/alerts', label: 'Alerts', badge: 'alerts' },
    { to: '/university/notices', label: 'Notices' },
    { to: '/university/flags', label: 'Flags' },
    { to: '/university/settings', label: 'Settings' },
  ],
  ADMIN: [
    { to: '/admin', label: 'Dashboard', end: true },
    { to: '/admin/universities', label: 'Universities' },
    { to: '/admin/payments', label: 'Verify Payments' },
    { to: '/admin/anomalies', label: 'Anomalies' },
    { to: '/admin/notices', label: 'Notices' },
    { to: '/admin/tax-rules', label: 'Tax Rules' },
    { to: '/admin/tools', label: 'Tools' },
    { to: '/admin/settings', label: 'Settings' },
  ],
};

export default function Layout() {
  const { user, logout } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const [unread, setUnread] = useState(0);
  const [menuOpen, setMenuOpen] = useState(false);

  // unread alert count for the bell (universities only), refreshed on every page change
  useEffect(() => {
    setMenuOpen(false);
    if (user?.role !== 'UNIVERSITY') return;
    api.get('/university/alerts/unread-count').then((d) => setUnread(d.count)).catch(() => {});
  }, [user, location.pathname]);

  const onLogout = async () => {
    await logout();
    navigate('/login');
  };

  const menu = MENUS[user.role];

  return (
    <div className="min-h-screen lg:flex">
      <aside className={`${menuOpen ? 'block' : 'hidden'} bg-brand-900 text-blue-100 lg:block lg:w-60 lg:shrink-0`}>
        <div className="px-5 py-5">
          <p className="text-lg font-semibold text-white">₹ Tax Compliance</p>
          <p className="text-xs text-blue-300">{user.role === 'ADMIN' ? 'Tax Office' : 'University Portal'}</p>
        </div>
        <nav className="space-y-0.5 px-3 pb-6">
          {menu.map((m) => (
            <NavLink
              key={m.to}
              to={m.to}
              end={m.end}
              className={({ isActive }) =>
                `flex items-center justify-between rounded-lg px-3 py-2 text-sm transition ${
                  isActive ? 'bg-white/15 font-medium text-white' : 'hover:bg-white/10'
                }`}
            >
              {m.label}
              {m.badge === 'alerts' && unread > 0 && (
                <span className="rounded-full bg-rose-500 px-2 text-xs font-semibold text-white">{unread}</span>
              )}
            </NavLink>
          ))}
        </nav>
      </aside>

      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex items-center justify-between border-b border-slate-200 bg-white px-4 py-3 sm:px-6">
          <button className="rounded-lg border border-slate-300 px-3 py-1 text-sm lg:hidden" onClick={() => setMenuOpen((o) => !o)}>
            Menu
          </button>
          <p className="hidden truncate text-sm text-slate-500 lg:block">
            {user.role === 'ADMIN' ? 'Tax office administration' : user.university}
          </p>
          <div className="flex items-center gap-4">
            {user.role === 'UNIVERSITY' && (
              <Link to="/university/alerts" className="relative text-slate-500 hover:text-slate-800" title="Alerts">
                <BellIcon />
                {unread > 0 && (
                  <span className="absolute -right-2 -top-2 rounded-full bg-rose-500 px-1.5 text-[10px] font-bold text-white">{unread}</span>
                )}
              </Link>
            )}
            <div className="text-right">
              <p className="text-sm font-medium text-slate-800">{user.name}</p>
              <p className="text-xs text-slate-500">{user.email}</p>
            </div>
            <button onClick={onLogout} className="rounded-lg border border-slate-300 px-3 py-1.5 text-sm hover:bg-slate-50">
              Log out
            </button>
          </div>
        </header>

        <main className="mx-auto w-full max-w-7xl flex-1 p-4 sm:p-6">
          <Outlet />
        </main>
      </div>
    </div>
  );
}

function BellIcon() {
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9" />
      <path d="M13.73 21a2 2 0 0 1-3.46 0" />
    </svg>
  );
}
