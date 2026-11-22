// All the pages (routes) of the app.
//  /login /register /forgot-password /reset-password   -> anyone
//  /university/...                                      -> UNIVERSITY users only
//  /admin/...                                           -> ADMIN users only
import { Navigate, Route, Routes } from 'react-router';
import { useAuth } from './context/AuthContext.jsx';
import ProtectedRoute, { homeFor } from './components/ProtectedRoute.jsx';
import Layout from './components/Layout.jsx';
import { Spinner } from './components/ui.jsx';

import Login from './pages/auth/Login.jsx';
import Register from './pages/auth/Register.jsx';
import ForgotPassword from './pages/auth/ForgotPassword.jsx';
import ResetPassword from './pages/auth/ResetPassword.jsx';
import NotFound from './pages/NotFound.jsx';
import ChangePassword from './pages/ChangePassword.jsx';

import UniDashboard from './pages/university/Dashboard.jsx';
import UniIncome from './pages/university/Income.jsx';
import UniBills from './pages/university/Bills.jsx';
import UniPayments from './pages/university/Payments.jsx';
import UniAlerts from './pages/university/Alerts.jsx';
import UniNotices from './pages/university/Notices.jsx';
import UniFlags from './pages/university/Flags.jsx';
import UniSettings from './pages/university/Settings.jsx';

import AdminDashboard from './pages/admin/Dashboard.jsx';
import AdminUniversities from './pages/admin/Universities.jsx';
import AdminUniversityDetail from './pages/admin/UniversityDetail.jsx';
import AdminPayments from './pages/admin/Payments.jsx';
import AdminAnomalies from './pages/admin/Anomalies.jsx';
import AdminNotices from './pages/admin/Notices.jsx';
import AdminTaxRules from './pages/admin/TaxRules.jsx';
import AdminTools from './pages/admin/Tools.jsx';

export default function App() {
  const { user, checking } = useAuth();

  return (
    <Routes>
      <Route path="/" element={checking ? <Spinner /> : <Navigate to={user ? homeFor(user) : '/login'} replace />} />
      <Route path="/login" element={<Login />} />
      <Route path="/register" element={<Register />} />
      <Route path="/forgot-password" element={<ForgotPassword />} />
      <Route path="/reset-password" element={<ResetPassword />} />

      <Route element={<ProtectedRoute role="UNIVERSITY" />}>
        <Route path="/university" element={<Layout />}>
          <Route index element={<UniDashboard />} />
          <Route path="income" element={<UniIncome />} />
          <Route path="bills" element={<UniBills />} />
          <Route path="payments" element={<UniPayments />} />
          <Route path="alerts" element={<UniAlerts />} />
          <Route path="notices" element={<UniNotices />} />
          <Route path="flags" element={<UniFlags />} />
          <Route path="settings" element={<UniSettings />} />
        </Route>
      </Route>

      <Route element={<ProtectedRoute role="ADMIN" />}>
        <Route path="/admin" element={<Layout />}>
          <Route index element={<AdminDashboard />} />
          <Route path="universities" element={<AdminUniversities />} />
          <Route path="universities/:id" element={<AdminUniversityDetail />} />
          <Route path="payments" element={<AdminPayments />} />
          <Route path="anomalies" element={<AdminAnomalies />} />
          <Route path="notices" element={<AdminNotices />} />
          <Route path="tax-rules" element={<AdminTaxRules />} />
          <Route path="tools" element={<AdminTools />} />
          <Route path="settings" element={<ChangePassword />} />
        </Route>
      </Route>

      <Route path="*" element={<NotFound />} />
    </Routes>
  );
}
