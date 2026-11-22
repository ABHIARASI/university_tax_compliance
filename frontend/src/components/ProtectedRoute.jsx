// Wraps pages that need a login (and the right role).
// This only decides what the user SEES - the real security is the backend,
// which checks the JWT cookie and the role on every API call.
import { Navigate, Outlet, useLocation } from 'react-router';
import { useAuth } from '../context/AuthContext.jsx';
import { Spinner } from './ui.jsx';

export default function ProtectedRoute({ role }) {
  const { user, checking } = useAuth();
  const location = useLocation();

  if (checking) return <Spinner label="Checking your session…" />;
  if (!user) return <Navigate to="/login" replace state={{ from: location.pathname }} />;
  if (role && user.role !== role) return <Navigate to={homeFor(user)} replace />;
  return <Outlet />;
}

export const homeFor = (user) => (user?.role === 'ADMIN' ? '/admin' : '/university');
