import { useEffect, useState } from 'react'
import { api, can, getClaims } from '../api'
import { toast } from '../toast'

interface OrderLine { product_name: string; qty: number; line_total: string }
interface Order {
  id: string
  number: string
  customer_name: string
  customer_phone: string
  customer_address: string | null
  fulfillment: string
  payment_method: string
  payment_reference: string | null
  status: string
  total: string
  currency: string
  created_at: string
  lines: OrderLine[]
}

const STATUS_STYLE: Record<string, { bg: string; fg: string }> = {
  pending: { bg: 'rgba(250,178,25,0.15)', fg: 'var(--status-warning)' },
  confirmed: { bg: 'rgba(42,120,214,0.15)', fg: 'var(--series-1)' },
  fulfilled: { bg: 'rgba(12,163,12,0.14)', fg: 'var(--delta-good)' },
  cancelled: { bg: 'var(--grid)', fg: 'var(--text-secondary)' },
}

const TABS = ['pending', 'confirmed', 'fulfilled', 'cancelled', 'all'] as const

export default function Orders() {
  const [orders, setOrders] = useState<Order[] | null>(null)
  const [tab, setTab] = useState<(typeof TABS)[number]>('pending')
  const [error, setError] = useState('')
  const storeLink = `${window.location.origin}/?store=${getClaims()?.tenant_id ?? ''}`
  const canUpdate = can('orders.update')

  function refresh() {
    const q = tab === 'all' ? '' : `?status_filter=${tab}`
    api.get<Order[]>(`/orders${q}`).then(setOrders).catch((e) => setError(e.message))
  }
  useEffect(refresh, [tab])

  async function setStatus(o: Order, status: string) {
    try {
      await api.patch(`/orders/${o.id}`, { status })
      toast(`Order ${o.number} ${status}`)
      refresh()
    } catch (e) {
      toast((e as Error).message, 'error')
    }
  }

  if (error) return <p style={{ color: 'var(--status-critical)' }}>{error}</p>

  return (
    <div className="max-w-5xl flex flex-col gap-4">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-2xl font-semibold">Online orders</h1>
          <p className="text-sm" style={{ color: 'var(--muted)' }}>
            Orders customers placed from home. Confirm → fulfil turns one into a sale.
          </p>
        </div>
        <button onClick={() => { navigator.clipboard?.writeText(storeLink); toast('Store link copied — share it with customers') }}
          className="text-sm px-3 py-1.5 rounded-lg border border-black/15 dark:border-white/15">
          🔗 Copy store link
        </button>
      </div>

      <div className="flex gap-1 card p-1 self-start">
        {TABS.map((t) => (
          <button key={t} onClick={() => setTab(t)}
            className={`px-3 py-1.5 rounded-lg text-sm capitalize transition-colors ${
              tab === t ? 'nav-active font-medium' : 'hover:bg-black/5 dark:hover:bg-white/5'}`}>
            {t}
          </button>
        ))}
      </div>

      {orders === null ? (
        <div className="skeleton w-full" style={{ height: 240 }} />
      ) : orders.length === 0 ? (
        <div className="card p-12 text-center">
          <div className="text-5xl mb-3">📦</div>
          <p className="text-sm" style={{ color: 'var(--muted)' }}>No {tab === 'all' ? '' : tab} orders.</p>
        </div>
      ) : (
        <div className="flex flex-col gap-3">
          {orders.map((o) => {
            const st = STATUS_STYLE[o.status] ?? STATUS_STYLE.cancelled
            return (
              <div key={o.id} className="card p-5">
                <div className="flex items-start justify-between gap-3 flex-wrap">
                  <div>
                    <div className="flex items-center gap-2">
                      <span className="font-mono text-sm font-medium">{o.number}</span>
                      <span className="px-2 py-0.5 rounded-full text-xs capitalize"
                            style={{ background: st.bg, color: st.fg }}>{o.status}</span>
                      <span className="text-xs px-2 py-0.5 rounded-full"
                            style={{ background: 'var(--grid)', color: 'var(--text-secondary)' }}>
                        {o.fulfillment === 'delivery' ? '🚚 delivery' : '🏬 pickup'}
                      </span>
                    </div>
                    <div className="text-sm mt-1">{o.customer_name} · {o.customer_phone}</div>
                    {o.customer_address && (
                      <div className="text-xs" style={{ color: 'var(--muted)' }}>{o.customer_address}</div>
                    )}
                  </div>
                  <div className="text-right">
                    <div className="text-lg font-semibold">
                      {o.currency === 'USD' ? '$' : `${o.currency} `}{Number(o.total).toFixed(2)}
                    </div>
                    <div className="text-xs capitalize" style={{ color: 'var(--muted)' }}>
                      {o.payment_method}{o.payment_reference ? ` · ${o.payment_reference}` : ''}
                    </div>
                  </div>
                </div>

                <div className="mt-3 text-sm" style={{ color: 'var(--text-secondary)' }}>
                  {o.lines.map((l, i) => (
                    <span key={i}>{l.product_name} ×{l.qty}{i < o.lines.length - 1 ? ' · ' : ''}</span>
                  ))}
                </div>

                {canUpdate && (o.status === 'pending' || o.status === 'confirmed') && (
                  <div className="mt-4 flex gap-2">
                    {o.status === 'pending' && (
                      <button onClick={() => setStatus(o, 'confirmed')}
                        className="px-4 py-1.5 rounded-lg bg-brand dark:bg-brand-dark text-white text-sm font-medium">
                        Confirm
                      </button>
                    )}
                    {o.status === 'confirmed' && (
                      <button onClick={() => setStatus(o, 'fulfilled')}
                        className="px-4 py-1.5 rounded-lg text-white text-sm font-medium"
                        style={{ background: 'var(--delta-good)' }}>
                        Fulfil → create sale
                      </button>
                    )}
                    <button onClick={() => setStatus(o, 'cancelled')}
                      className="px-4 py-1.5 rounded-lg text-sm border border-black/15 dark:border-white/15"
                      style={{ color: 'var(--status-critical)' }}>
                      Cancel
                    </button>
                  </div>
                )}
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}
