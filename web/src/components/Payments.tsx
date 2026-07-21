import { useEffect, useState } from 'react'
import { api, Payment } from '../api'
import BranchSelect, { useShops } from './BranchSelect'
import { toast } from '../toast'

const METHODS = ['cash', 'ecocash', 'onemoney', 'zipit', 'paynow', 'bank', 'card'] as const

const METHOD_COLOR: Record<string, string> = {
  cash: 'var(--series-2)', ecocash: 'var(--series-6)', onemoney: 'var(--series-4)',
  zipit: 'var(--series-7)', paynow: 'var(--series-1)', bank: 'var(--series-5)',
  card: 'var(--series-3)',
}

export default function Payments() {
  const shops = useShops()
  const [shopId, setShopId] = useState('')
  const [payments, setPayments] = useState<Payment[] | null>(null)
  const [editing, setEditing] = useState<string | null>(null)
  const [draft, setDraft] = useState<{ method: string; reference: string }>({
    method: 'cash', reference: '',
  })
  const [error, setError] = useState('')

  function refresh() {
    const q = shopId ? `?shop_id=${shopId}&limit=100` : '?limit=100'
    api.get<Payment[]>(`/payments${q}`).then(setPayments).catch((e) => setError(e.message))
  }
  useEffect(refresh, [shopId])

  function startEdit(p: Payment) {
    setEditing(p.id)
    setDraft({ method: p.method, reference: p.reference ?? '' })
  }

  async function save(p: Payment) {
    try {
      await api.patch(`/payments/${p.id}`, {
        method: draft.method, reference: draft.reference || null,
      })
      toast('Payment corrected')
      setEditing(null)
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
          <h1 className="text-2xl font-semibold">Payments</h1>
          <p className="text-sm" style={{ color: 'var(--muted)' }}>
            Correct how a payment was recorded — e.g. it was EcoCash, not cash.
          </p>
        </div>
        <BranchSelect shops={shops} value={shopId} onChange={setShopId} />
      </div>

      <div className="card p-5 overflow-x-auto">
        {payments === null ? (
          <div className="skeleton w-full" style={{ height: 240 }} />
        ) : payments.length === 0 ? (
          <p className="text-sm" style={{ color: 'var(--muted)' }}>No payments recorded yet.</p>
        ) : (
          <table className="w-full text-sm" style={{ fontVariantNumeric: 'tabular-nums' }}>
            <thead>
              <tr className="text-left" style={{ color: 'var(--muted)' }}>
                <th className="py-1.5 font-medium">When</th>
                <th className="py-1.5 font-medium">Receipt</th>
                <th className="py-1.5 font-medium">Method</th>
                <th className="py-1.5 font-medium">Reference</th>
                <th className="py-1.5 font-medium text-right">Amount</th>
                <th className="py-1.5 font-medium text-right">Edit</th>
              </tr>
            </thead>
            <tbody>
              {payments.map((p) => (
                <tr key={p.id} className="border-t border-black/5 dark:border-white/5">
                  <td className="py-2.5">{new Date(p.created_at).toLocaleString()}</td>
                  <td className="py-2.5 font-mono text-xs">{p.sale_id.slice(0, 8).toUpperCase()}</td>
                  <td className="py-2.5">
                    {editing === p.id ? (
                      <select value={draft.method}
                              onChange={(e) => setDraft({ ...draft, method: e.target.value })}
                              className="px-2 py-1 rounded-lg border border-black/15 dark:border-white/15 bg-transparent">
                        {METHODS.map((m) => <option key={m} value={m}>{m}</option>)}
                      </select>
                    ) : (
                      <span className="inline-flex items-center gap-1.5 capitalize">
                        <span className="w-2 h-2 rounded-full"
                              style={{ background: METHOD_COLOR[p.method] ?? 'var(--muted)' }} />
                        {p.method}
                      </span>
                    )}
                  </td>
                  <td className="py-2.5">
                    {editing === p.id ? (
                      <input value={draft.reference} placeholder="ref"
                             onChange={(e) => setDraft({ ...draft, reference: e.target.value })}
                             className="px-2 py-1 w-28 rounded-lg border border-black/15 dark:border-white/15 bg-transparent" />
                    ) : (
                      <span style={{ color: 'var(--text-secondary)' }}>{p.reference ?? '—'}</span>
                    )}
                  </td>
                  <td className="py-2.5 text-right">
                    {p.currency === 'USD' ? '$' : `${p.currency} `}{Number(p.amount).toFixed(2)}
                  </td>
                  <td className="py-2.5 text-right whitespace-nowrap">
                    {editing === p.id ? (
                      <>
                        <button onClick={() => save(p)} className="mr-2 font-medium"
                                style={{ color: 'var(--delta-good)' }}>Save</button>
                        <button onClick={() => setEditing(null)}
                                style={{ color: 'var(--text-secondary)' }}>Cancel</button>
                      </>
                    ) : (
                      <button onClick={() => startEdit(p)}
                              style={{ color: 'var(--series-1)' }}>Correct</button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}
