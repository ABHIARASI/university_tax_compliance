// Shared frame for the login / register / password pages
export default function AuthShell({ title, subtitle, children, wide }) {
  return (
    <div className="flex min-h-screen items-start justify-center bg-gradient-to-br from-brand-900 via-brand-700 to-brand-500 px-4 py-10 sm:items-center">
      <div className={`w-full ${wide ? 'max-w-3xl' : 'max-w-md'}`}>
        <div className="mb-6 text-center text-white">
          <p className="text-3xl font-bold">₹ Tax Compliance</p>
          <p className="mt-1 text-sm text-blue-100">GST compliance portal for universities</p>
        </div>
        <div className="rounded-2xl bg-white p-6 shadow-2xl sm:p-8">
          <h1 className="text-xl font-semibold text-slate-900">{title}</h1>
          {subtitle && <p className="mt-1 text-sm text-slate-500">{subtitle}</p>}
          <div className="mt-6">{children}</div>
        </div>
      </div>
    </div>
  );
}
