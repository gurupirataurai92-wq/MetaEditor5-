import { useEffect, useState } from 'react'
import { Anomaly, api, SalesSummary, StockLevel } from '../api'

const REFRESH_MS = 10_000

interface CashierRow {
  cashier_id: string
  name: string
  sales_count: number
  revenue: string
  voids: number
}

interface FeedSale {
  id: string
  total: string
  currency: string
  status: string
  captured_at: string
  cashier_id: string
  payments: { method: string }[]
}

function timeAgo(iso: string): string {
  const seconds = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000)
  if (seconds < 60) return `${Math.floor(seconds)}s ago`
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`
  return `${Math.floor(seconds / 86400)}d ago`
}

export default function Monitor() {
  const [summary, setSummary] = useState<SalesSummary | null>(null)
  const [cashiers, setCashiers] = useState<CashierRow[]>([])
  const [feed, setFeed] = useState<FeedSale[]>([])
  const [levels, setLevels] = useState<StockLevel[]>([])
  const [anomalies, setAnomalies] = useState<Anomaly[]>([])
  const [updatedAt, setUpdatedAt] = useState<Date | null>(null)
  const [error, setError] = useState('')

  useEffect(() => {
    let alive = true
    async function refresh() {
      const dayStart = new Date()
      dayStart.setHours(0, 0, 0, 0)
      const q = `date_from=${dayStart.toISOString()}`
      try {
        const [s, c, f, l, a] = await Promise.all([
          api.get<SalesSummary>(`/reports/sales-summary?${q}`),
          api.get<CashierRow[]>(`/reports/cashier-performance?${q}`),
          api.get<FeedSale[]>('/sales?limit=12'),
          api.get<StockLevel[]>('/stock/levels'),
          api.get<Anomaly[]>('/analytics/anomalies?window=7'),
        ])
        if (!alive) return
        setSummary(s); setCashiers(c); setFeed(f); setLevels(l); setAnomalies(a)
        setUpdatedAt(new Date()); setError('')
      } catch (e) {
        if (alive) setError((e as Error).message)
      }
    }
    refresh()
    const timer = setInterval(refresh, REFRESH_MS)
    return () => { alive = false; clearInterval(timer) }
  }, [])

  const nameById = Object.fromEntries(cashiers.map((c) => [c.cashier_id, c.name]))
  const voidsToday = cashiers.reduce((n, c) => n + c.voids, 0)
  const lowStock = levels.filter((l) => l.below_reorder)

  if (error) return <p style={{ color: 'var(--status-critical)' }}>{error}</p>

  return (
    <div className="max-w-6xl flex flex-col gap-4">
      <div className="flex items-center justify-between flex-wrap gap-2">
        <div className="flex items-center gap-3">
          <h1 className="text-2xl font-semibold">Live monitor</h1>
          <span className="flex items-center gap-1.5 text-xs px-2.5 py-1 rounded-full"
                style={{ background: 'rgba(12,163,12,0.12)', color: 'var(--delta-good)' }}>
            <span className="w-2 h-2 rounded-full animate-pulse"
                  style={{ background: 'var(--delta-good)' }} />
            LIVE · auto-refresh {REFRESH_MS / 1000}s
          </span>
        </div>
        {updatedAt && (
          <span className="text-xs" style={{ color: 'var(--muted)' }}>
            Updated {updatedAt.toLocaleTimeString()}
          </span>
        )}
      </div>

      {!summary ? (
        <div className="skeleton w-full" style={{ height: 400 }} />
      ) : (
        <>
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
            <div className="card p-5">
              <div className="text-sm" style={{ color: 'var(--text-secondary)' }}>Revenue today</div>
              <div className="text-3xl font-semibold mt-1">${summary.revenue}</div>
            </div>
            <div className="card p-5">
              <div className="text-sm" style={{ color: 'var(--text-secondary)' }}>Transactions today</div>
              <div className="text-3xl font-semibold mt-1">{summary.sales_count}</div>
            </div>
            <div className="card p-5">
              <div className="text-sm" style={{ color: 'var(--text-secondary)' }}>Voids today</div>
              <div className="text-3xl font-semibold mt-1"
                   style={voidsToday > 0 ? { color: 'var(--status-critical)' } : undefined}>
                {voidsToday}
              </div>
            </div>
            <div className="card p-5">
              <div className="text-sm" style={{ color: 'var(--text-secondary)' }}>Low-stock items</div>
              <div className="text-3xl font-semibold mt-1"
                   style={lowStock.length > 0 ? { color: 'var(--status-warning)' } : undefined}>
                {lowStock.length}
              </div>
            </div>
          </div>

          <div className="grid lg:grid-cols-2 gap-4">
            <div className="card p-5">
              <h2 className="font-medium mb-3">Till performance (today)</h2>
              {cashiers.length === 0 ? (
                <p className="text-sm" style={{ color: 'var(--muted)' }}>No activity yet today.</p>
              ) : (
                <table className="w-full text-sm" style={{ fontVariantNumeric: 'tabular-nums' }}>
                  <thead>
                    <tr className="text-left" style={{ color: 'var(--muted)' }}>
                      <th className="py-1 font-medium">Operator</th>
                      <th className="py-1 font-medium text-right">Sales</th>
                      <th className="py-1 font-medium text-right">Revenue</th>
                      <th className="py-1 font-medium text-right">Voids</th>
                    </tr>
                  </thead>
                  <tbody>
                    {cashiers.map((c) => (
                      <tr key={c.cashier_id} className="border-t border-black/5 dark:border-white/5">
                        <td className="py-2">{c.name}</td>
                        <td className="py-2 text-right">{c.sales_count}</td>
                        <td className="py-2 text-right">${c.revenue}</td>
                        <td className="py-2 text-right"
                            style={c.voids > 0 ? { color: 'var(--status-critical)' } : undefined}>
                          {c.voids}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </div>

            <div className="card p-5">
              <h2 className="font-medium mb-3">Live sales feed</h2>
              <div className="flex flex-col gap-2">
                {feed.map((s) => (
                  <div key={s.id} className="flex items-center justify-between text-sm">
                    <span className="flex items-center gap-2 min-w-0">
                      <span aria-hidden>{s.status === 'void' ? '🚫' : '🧾'}</span>
                      <span className="truncate">
                        {nameById[s.cashier_id] ?? 'Till'}
                        <span style={{ color: 'var(--muted)' }}>
                          {' '}· {[...new Set(s.payments.map((p) => p.method))].join('+') || 'cash'}
                        </span>
                      </span>
                    </span>
                    <span className="shrink-0 flex items-center gap-3"
                          style={{ fontVariantNumeric: 'tabular-nums' }}>
                      <span className={s.status === 'void' ? 'line-through' : ''}>
                        ${Number(s.total).toFixed(2)}
                      </span>
                      <span className="text-xs w-16 text-right" style={{ color: 'var(--muted)' }}>
                        {timeAgo(s.captured_at)}
                      </span>
                    </span>
                  </div>
                ))}
              </div>
            </div>

            <div className="card p-5">
              <h2 className="font-medium mb-3">⚠ Low stock</h2>
              {lowStock.length === 0 ? (
                <p className="text-sm" style={{ color: 'var(--muted)' }}>All items above reorder level.</p>
              ) : (
                <ul className="text-sm flex flex-col gap-1.5">
                  {lowStock.slice(0, 8).map((l) => (
                    <li key={l.product_id} className="flex justify-between">
                      <span>{l.name}</span>
                      <span style={{ color: 'var(--status-critical)', fontVariantNumeric: 'tabular-nums' }}>
                        {l.on_hand} left (min {l.reorder_level})
                      </span>
                    </li>
                  ))}
                </ul>
              )}
            </div>

            <div className="card p-5">
              <h2 className="font-medium mb-3">Alerts (7 days)</h2>
              {anomalies.length === 0 ? (
                <p className="text-sm" style={{ color: 'var(--muted)' }}>✓ Nothing unusual.</p>
              ) : (
                <ul className="flex flex-col gap-2 text-sm">
                  {anomalies.slice(0, 6).map((a, i) => (
                    <li key={i} className="flex gap-2 items-start">
                      <span aria-hidden>{a.severity === 'high' ? '⛔' : '⚠️'}</span>
                      <span style={{ color: 'var(--text-secondary)' }}>{a.detail}</span>
                    </li>
                  ))}
                </ul>
              )}
            </div>
          </div>
        </>
      )}
    </div>
  )
}
