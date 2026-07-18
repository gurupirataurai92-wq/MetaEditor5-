import { useEffect, useState } from 'react'
import { hasToken, setToken } from './api'
import Assistant from './components/Assistant'
import Dashboard from './components/Dashboard'
import Inventory from './components/Inventory'
import Login from './components/Login'
import { LogoWordmark } from './components/Logo'
import Pos from './components/Pos'
import Sales from './components/Sales'
import Toasts from './components/Toasts'

type Page = 'dashboard' | 'pos' | 'sales' | 'inventory' | 'assistant'

const NAV: { id: Page; label: string; icon: string }[] = [
  { id: 'dashboard', label: 'Dashboard', icon: '📊' },
  { id: 'pos', label: 'Point of Sale', icon: '🛒' },
  { id: 'sales', label: 'Sales', icon: '🧾' },
  { id: 'inventory', label: 'Inventory', icon: '📦' },
  { id: 'assistant', label: 'AI Assistant', icon: '✨' },
]

export default function App() {
  const [authed, setAuthed] = useState(hasToken())
  const [page, setPage] = useState<Page>('dashboard')
  const [dark, setDark] = useState(
    () => localStorage.getItem('sims_theme') === 'dark' ||
      (localStorage.getItem('sims_theme') === null &&
        window.matchMedia('(prefers-color-scheme: dark)').matches),
  )

  useEffect(() => {
    document.documentElement.classList.toggle('dark', dark)
    localStorage.setItem('sims_theme', dark ? 'dark' : 'light')
  }, [dark])

  if (!authed) return <Login onLogin={() => setAuthed(true)} />

  return (
    <div className="min-h-screen flex">
      <aside className="w-60 shrink-0 border-r border-black/10 dark:border-white/10 p-4 flex flex-col gap-1"
             style={{ background: 'var(--surface-1)' }}>
        <div className="px-2 py-3 mb-2">
          <LogoWordmark />
        </div>
        {NAV.map((item) => (
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
          {page === 'dashboard' && <Dashboard onGoToPos={() => setPage('pos')} />}
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
