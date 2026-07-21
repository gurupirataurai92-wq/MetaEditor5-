import { useEffect, useMemo, useState } from 'react'
import { can, getClaims, hasToken, setToken } from './api'
import Assistant from './components/Assistant'
import Branches from './components/Branches'
import Dashboard from './components/Dashboard'
import Inventory from './components/Inventory'
import Login from './components/Login'
import { LogoWordmark } from './components/Logo'
import Monitor from './components/Monitor'
import Payments from './components/Payments'
import Pos from './components/Pos'
import Sales from './components/Sales'
import Staff from './components/Staff'
import Toasts from './components/Toasts'

type Page = 'dashboard' | 'monitor' | 'branches' | 'staff' | 'pos' | 'sales'
          | 'inventory' | 'payments' | 'assistant'

const NAV: Record<Page, { label: string; icon: string; perm: string }> = {
  dashboard: { label: 'Dashboard', icon: '📊', perm: 'reports.read' },
  monitor: { label: 'Live Monitor', icon: '📡', perm: 'users.read' },
  branches: { label: 'Branches', icon: '🏬', perm: 'shops.create' },
  staff: { label: 'Staff & Duty', icon: '👥', perm: 'employees.read' },
  pos: { label: 'Point of Sale', icon: '🛒', perm: 'sales.create' },
  sales: { label: 'Sales', icon: '🧾', perm: 'sales.read' },
  inventory: { label: 'Inventory', icon: '📦', perm: 'stock.create' },
  payments: { label: 'Payments', icon: '💳', perm: 'payments.update' },
  assistant: { label: 'AI Assistant', icon: '✨', perm: 'analytics.read' },
}

// Three workspaces, one login. The order defines each role's landing page;
// the permission check below is the safety net (and the API enforces again).
const ROLE_NAV: Record<string, Page[]> = {
  owner: ['dashboard', 'monitor', 'branches', 'staff', 'pos', 'sales',
          'inventory', 'payments', 'assistant'],
  manager: ['staff', 'monitor', 'inventory', 'pos', 'sales', 'payments', 'assistant'],
  cashier: ['pos', 'sales', 'inventory'],
  storekeeper: ['inventory', 'staff'],
  accountant: ['dashboard', 'sales', 'payments', 'assistant'],
}
const ALL_PAGES = Object.keys(NAV) as Page[]

export default function App() {
  const [authed, setAuthed] = useState(hasToken())
  const visibleNav = useMemo(() => {
    const role = getClaims()?.role ?? ''
    const pages = ROLE_NAV[role] ?? ALL_PAGES
    return pages.filter((id) => can(NAV[id].perm))
  }, [authed])
  const [page, setPage] = useState<Page>(visibleNav[0] ?? 'pos')
  const [dark, setDark] = useState(
    () => localStorage.getItem('sims_theme') === 'dark' ||
      (localStorage.getItem('sims_theme') === null &&
        window.matchMedia('(prefers-color-scheme: dark)').matches),
  )

  useEffect(() => {
    document.documentElement.classList.toggle('dark', dark)
    localStorage.setItem('sims_theme', dark ? 'dark' : 'light')
  }, [dark])

  // On (re)auth, land on the first surface of the role's workspace:
  // owner → Dashboard, manager → Staff & Duty, till operator → POS.
  useEffect(() => {
    if (authed && visibleNav.length) setPage(visibleNav[0])
  }, [authed, visibleNav])

  if (!authed) return <Login onLogin={() => setAuthed(true)} />

  const role = getClaims()?.role ?? ''
  const roleBadge =
    role === 'owner' ? 'Owner · full access'
    : role === 'manager' ? 'Manager · staff & stock'
    : role === 'cashier' ? 'Till operator'
    : role

  return (
    <div className="min-h-screen flex">
      <aside className="w-60 shrink-0 border-r border-black/10 dark:border-white/10 p-4 flex flex-col gap-1"
             style={{ background: 'var(--surface-1)' }}>
        <div className="px-2 py-3 mb-1">
          <LogoWordmark />
        </div>
        {role && (
          <div className="mx-2 mb-2 px-2.5 py-1 rounded-full text-xs self-start"
               style={{ background: 'var(--grid)', color: 'var(--text-secondary)' }}>
            {roleBadge}
          </div>
        )}
        {visibleNav.map((id) => (
          <button key={id} onClick={() => setPage(id)}
            className={`text-left px-3 py-2 rounded-lg text-sm transition-colors ${
              page === id
                ? 'nav-active font-medium'
                : 'hover:bg-black/5 dark:hover:bg-white/5'
            }`}>
            <span className="mr-2">{NAV[id].icon}</span>
            {NAV[id].label}
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
          {page === 'branches' && <Branches />}
          {page === 'staff' && <Staff />}
          {page === 'pos' && <Pos />}
          {page === 'sales' && <Sales />}
          {page === 'inventory' && <Inventory />}
          {page === 'payments' && <Payments />}
          {page === 'assistant' && <Assistant />}
        </div>
      </main>
      <Toasts />
    </div>
  )
}
