import { useEffect, useMemo, useState } from 'react'
import { can, getClaims, hasToken, setToken } from './api'
import Assistant from './components/Assistant'
import Dashboard from './components/Dashboard'
import Inventory from './components/Inventory'
import Login from './components/Login'
import { LogoWordmark } from './components/Logo'
import Monitor from './components/Monitor'
import Pos from './components/Pos'
import Sales from './components/Sales'
import Toasts from './components/Toasts'

type Page = 'dashboard' | 'monitor' | 'pos' | 'sales' | 'inventory' | 'assistant'

// Each surface is gated by the permission that its data actually requires —
// the same grants the API enforces. A till operator (cashier) therefore sees
// only POS + Sales; owner/manager get the full cockpit incl. the Live Monitor.
const NAV: { id: Page; label: string; icon: string; perm: string }[] = [
  { id: 'dashboard', label: 'Dashboard', icon: '📊', perm: 'reports.read' },
  { id: 'monitor', label: 'Live Monitor', icon: '📡', perm: 'users.read' },
  { id: 'pos', label: 'Point of Sale', icon: '🛒', perm: 'sales.create' },
  { id: 'sales', label: 'Sales', icon: '🧾', perm: 'sales.read' },
  { id: 'inventory', label: 'Inventory', icon: '📦', perm: 'stock.create' },
  { id: 'assistant', label: 'AI Assistant', icon: '✨', perm: 'analytics.read' },
]

export default function App() {
  const [authed, setAuthed] = useState(hasToken())
  const visibleNav = useMemo(() => NAV.filter((item) => can(item.perm)), [authed])
  const [page, setPage] = useState<Page>(visibleNav[0]?.id ?? 'pos')
  const [dark, setDark] = useState(
    () => localStorage.getItem('sims_theme') === 'dark' ||
      (localStorage.getItem('sims_theme') === null &&
        window.matchMedia('(prefers-color-scheme: dark)').matches),
  )

  useEffect(() => {
    document.documentElement.classList.toggle('dark', dark)
    localStorage.setItem('sims_theme', dark ? 'dark' : 'light')
  }, [dark])

  // On (re)auth, land on the first surface the role can see:
  // owner/manager → Dashboard, till operator → Point of Sale.
  useEffect(() => {
    if (authed && visibleNav.length) setPage(visibleNav[0].id)
  }, [authed, visibleNav])

  if (!authed) return <Login onLogin={() => setAuthed(true)} />

  const role = getClaims()?.role ?? ''

  return (
    <div className="min-h-screen flex">
      <aside className="w-60 shrink-0 border-r border-black/10 dark:border-white/10 p-4 flex flex-col gap-1"
             style={{ background: 'var(--surface-1)' }}>
        <div className="px-2 py-3 mb-1">
          <LogoWordmark />
        </div>
        {role && (
          <div className="mx-2 mb-2 px-2.5 py-1 rounded-full text-xs self-start capitalize"
               style={{ background: 'var(--grid)', color: 'var(--text-secondary)' }}>
            {role === 'owner' || role === 'manager' ? `${role} · full access` : `${role} mode`}
          </div>
        )}
        {visibleNav.map((item) => (
          <button key={item.id} onClick={() => setPage(item.id)}
            className={`text-left px-3 py-2 rounded-lg text-sm transition-colors ${
              page === item.id
                ? 'bg-brand/10 dark:bg-brand-dark/20 font-medium'
                : 'hover:bg-black/5 dark:hover:bg-white/5'
            }`}>
            <span className="mr-2">{item.icon}</span>
            {item.label}
          </button>
        ))}
        <div className="mt-auto flex flex-col gap-1">
          <button onClick={() => setDark(!dark)}
            className="text-left px-3 py-2 rounded-lg text-sm hover:bg-black/5 dark:hover:bg-white/5">
            {dark ? '☀️ Light mode' : '🌙 Dark mode'}
          </button>
          <button onClick={() => { setToken(null); setAuthed(false) }}
            className="text-left px-3 py-2 rounded-lg text-sm hover:bg-black/5 dark:hover:bg-white/5">
            ↩ Sign out
          </button>
        </div>
      </aside>
      <main className="flex-1 p-6 overflow-x-hidden">
        <div key={page} className="fade-in">
          {page === 'dashboard' && <Dashboard onGoToPos={
            can('sales.create') ? () => setPage('pos') : undefined} />}
          {page === 'monitor' && <Monitor />}
          {page === 'pos' && <Pos />}
          {page === 'sales' && <Sales />}
          {page === 'inventory' && <Inventory />}
          {page === 'assistant' && <Assistant />}
        </div>
      </main>
      <Toasts />
    </div>
  )
}
