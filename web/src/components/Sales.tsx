import { useEffect, useState } from 'react'
import { api, can } from '../api'
import { toast } from '../toast'

interface SaleRow {
  id: string
  total: string
  tax_amount: string
  currency: string
  status: string
  captured_at: string
  cashier_id: string
  payments: { method: string }[]
}

interface Operator {
  user_id: string | null
  full_name: string
}

export default function Sales() {
  const [sales, setSales] = useState<SaleRow[] | null>(null)
  const [operators, setOperators] = useState<Operator[]>([])
  const [operator, setOperator] = useState('')
  const [confirming, setConfirming] = useState<string | null>(null)
  const [error, setError] = useState('')

  // Owner/manager can slice history by till operator; a cashier only ever
  // sees their own receipts (the API enforces this regardless).
  const canFilterByOperator = can('employees.read')

  function refresh() {
    const q = operator ? `/sales?limit=100&cashier_id=${operator}` : '/sales?limit=100'
    api.get<SaleRow[]>(q).then(setSales).catch((e) => setError(e.message))
  }
  useEffect(refresh, [operator])

  useEffect(() => {
    if (canFilterByOperator) {
      api.get<Operator[]>('/employees')
        .then((rows) => setOperators(rows.filter((r) => r.user_id)))
        .catch(() => setOperators([]))
    }
  }, [canFilterByOperator])

  async function voidSale(id: string) {
    try {
      await api.post(`/sales/${id}/void`, {})
      toast('Sale voided — stock restored')
      setConfirming(null)
      refresh()
    } catch (e) {
      toast((e as Error).message, 'error')
    }
  }

  if (error) return <p style={{ color: 'var(--status-critical)' }}>{error}</p>

  return (
    <div className="max-w-5xl flex flex-col gap-4">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <h1 className="text-2xl font-semibold">Sales history</h1>
        {canFilterByOperator && operators.length > 0 && (
          <select value={operator} onChange={(e) => setOperator(e.target.value)}
            className="px-3 py-1.5 rounded-lg text-sm border border-black/15 dark:border-white/15 bg-transparent outline-none">
            <option value="">All till operators</option>
            {operators.map((o) => (
              <option key={o.user_id!} value={o.user_id!}>{o.full_name}</option>
            ))}
          </select>
        )}
      </div>

      {sales === null ? (
        <div className="skeleton w-full" style={{ height: 300 }} />
      ) : sales.length === 0 ? (
        <div className="card p-12 text-center">
          <div className="text-5xl mb-3">🧾</div>
          <p className="text-sm" style={{ color: 'var(--text-secondary)' }}>
            No sales recorded yet — they will appear here as receipts are issued.
          </p>
        </div>
      ) : (
        <div className="card p-5 overflow-x-auto">
          <table className="w-full text-sm" style={{ fontVariantNumeric: 'tabular-nums' }}>
            <thead>
              <tr className="text-left" style={{ color: 'var(--muted)' }}>
                <th className="py-1.5 font-medium">Receipt</th>
                <th className="py-1.5 font-medium">Date</th>
                <th className="py-1.5 font-medium">Paid via</th>
                <th className="py-1.5 font-medium text-right">Total</th>
                <th className="py-1.5 font-medium">Status</th>
                <th className="py-1.5 font-medium text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              {sales.map((s) => (
                <tr key={s.id} className="border-t border-black/5 dark:border-white/5">
                  <td className="py-2.5 font-mono text-xs">{s.id.slice(0, 8).toUpperCase()}</td>
                  <td className="py-2.5">{new Date(s.captured_at).toLocaleString()}</td>
                  <td className="py-2.5 capitalize">
                    {[...new Set(s.payments.map((p) => p.method))].join(' + ')}
                  </td>
                  <td className="py-2.5 text-right">
                    {s.currency === 'USD' ? '$' : `${s.currency} `}{Number(s.total).toFixed(2)}
                  </td>
                  <td className="py-2.5">
                    {s.status === 'void' ? (
                      <span className="px-2 py-0.5 rounded-full text-xs"
                            style={{ background: 'var(--grid)', color: 'var(--text-secondary)' }}>
                        voided
                      </span>
                    ) : (
                      <span className="px-2 py-0.5 rounded-full text-xs"
                            style={{ background: 'rgba(12,163,12,0.12)', color: 'var(--delta-good)' }}>
                        completed
                      </span>
                    )}
                  </td>
                  <td className="py-2.5 text-right whitespace-nowrap">
                    <a className="underline underline-offset-2 mr-3"
                       href={`/api/v1/sales/${s.id}/receipt.pdf`}
                       target="_blank" rel="noreferrer">
                      Receipt
                    </a>
                    {s.status === 'committed' && can('sales.void') && (
                      confirming === s.id ? (
                        <>
                          <button onClick={() => voidSale(s.id)} className="mr-2 font-medium"
                                  style={{ color: 'var(--status-critical)' }}>
                            Confirm void
                          </button>
                          <button onClick={() => setConfirming(null)}
                                  style={{ color: 'var(--text-secondary)' }}>
                            Cancel
                          </button>
                        </>
                      ) : (
                        <button onClick={() => setConfirming(s.id)}
                                style={{ color: 'var(--text-secondary)' }}>
                          Void
                        </button>
                      )
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
