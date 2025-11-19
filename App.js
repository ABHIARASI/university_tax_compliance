// import React from "react";
// import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
// import { AuthProvider, AuthContext } from "./context/AuthContext";

// import Login from "./pages/Login";
// import UniversityDashboard from "./pages/UniversityDashboard";
// import AdminDashboard from "./pages/AdminDashboard";

// function PrivateRoute({ children, role }) {
//     return (
//         <AuthContext.Consumer>
//             {({ user }) =>
//                 user && user.role === role ? children : <Navigate to="/" />
//             }
//         </AuthContext.Consumer>
//     );
// }

// function App() {
//     return (
//         <AuthProvider>
//             <BrowserRouter>
//                 <Routes>
//                     <Route path="/" element={<Login />} />

//                     {/* UNIVERSITY ONLY */}
//                     <Route
//                         path="/university/dashboard"
//                         element={
//                             <PrivateRoute role="university">
//                                 <UniversityDashboard />
//                             </PrivateRoute>
//                         }
//                     />

//                     {/* ADMIN ONLY */}
//                     <Route
//                         path="/admin/dashboard"
//                         element={
//                             <PrivateRoute role="admin">
//                                 <AdminDashboard />
//                             </PrivateRoute>
//                         }
//                     />
//                 </Routes>
//             </BrowserRouter>
//         </AuthProvider>
//     );
// }

// export default App;
import React from "react";
import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { AuthProvider, AuthContext } from "./context/AuthContext";

import Login from "./pages/Login";
import UniversityDashboard from "./pages/UniversityDashboard";
import AdminDashboard from "./pages/AdminDashboard";
import AdminUniversityStats from "./pages/AdminUniversityStats";
import AddRevenue from "./pages/AddRevenue";
import AdminSendNotice from "./pages/AdminSendNotice";
import AdminAllNotices from "./pages/AdminAllNotices";
import UniversityMyNotices from "./pages/UniversityMyNotices";



import AdminTaxPayments from "./pages/AdminTaxPayments";
import AdminAnomalies from "./pages/AdminAnomalies";













function PrivateRoute({ children, role }) {
    return (
        <AuthContext.Consumer>
            {({ user }) =>
                user && user.role === role ? children : <Navigate to="/" />
            }
        </AuthContext.Consumer>
    );
}

function App() {
    return (
        <AuthProvider>
            <BrowserRouter>
                <Routes>
                    <Route
                        path="/admin/university-stats"
                        element={
                            <PrivateRoute role="admin">
                                <AdminUniversityStats />
                            </PrivateRoute>
                        }
                    />

                    <Route path="/" element={<Login />} />

                    <Route
                        path="/university/dashboard"
                        element={
                            <PrivateRoute role="university">
                                <UniversityDashboard />
                            </PrivateRoute>
                        }
                    />
                    <Route path="/admin/send-notice" element={<AdminSendNotice />} />
                    <Route path="/admin/notices" element={<AdminAllNotices />} />
                    <Route path="/university/notices" element={<UniversityMyNotices />} />
                    {/* University */}
                    <Route path="/university/dashboard" element={<UniversityDashboard />} />
                    <Route path="/university/notices" element={<UniversityMyNotices />} />

                    {/* Admin */}
                    <Route path="/admin/send-notice" element={<AdminSendNotice />} />
                    <Route path="/admin/notices" element={<AdminAllNotices />} />
                    <Route path="/admin/payments" element={<AdminTaxPayments />} />
                    <Route path="/admin/anomalies" element={<AdminAnomalies />} />



                    <Route
                        path="/admin/dashboard"
                        element={
                            <PrivateRoute role="admin">
                                <AdminDashboard />
                            </PrivateRoute>
                        }
                    />
                    <Route
                        path="/university/add-revenue"
                        element={
                            <PrivateRoute role="university">
                                <AddRevenue />
                            </PrivateRoute>
                        }
                    />
                </Routes>
            </BrowserRouter>
        </AuthProvider>
    );
}

export default App;

