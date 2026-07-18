import { FormEvent, useEffect, useState } from 'react'
import { api, StockLevel } from '../api'

interface ReorderSuggestion {
  name: string
  on_hand: number
  suggested_order_qty: number
}

export default function Inventory() {
  const [levels, setLevels] = useState<StockLevel[]>([])
  const [suggestions, setSuggestions] = useState<ReorderSuggestion[]>([])
  const [name, setName] = useState('')
  const [sell, setSell] = useState('')
  const [cost, setCost] = useState('')
  const [qty, setQty] = useState('')
  const [error, setError] = useState('')

  function refresh() {
    api.get<StockLevel[]>('/stock/levels').then(setLevels).catch((e) => setError(e.message))
    api.get<ReorderSuggestion[]>('/analytics/reorder-suggestions')
      .then(setSuggestions).catch(() => setSuggestions([]))
  }
  useEffect(refresh, [])

  async function addProduct(e: FormEvent) {
    e.preventDefault()
    setError('')
    try {
      const product = await api.post<{ id: string }>('/products', {
        name, sell_price: sell, cost_price: cost || '0',
      })
      if (Number(qty) > 0) {
        await api.post('/stock/movements', {
          product_id: product.id, movement_type: 'purchase', qty: Number(qty),
        })
      }
      setName(''); setSell(''); setCost(''); setQty('')
      refresh()
    } catch (err) {
      setError((err as Error).message)
    }
  }

  const input =
    'px-3 py-2 rounded-lg border border-black/15 dark:border-white/15 bg-transparent outline-none'

  return (
    <div className="max-w-4xl flex flex-col gap-4">
      <h1 className="text-2xl font-semibold">Inventory</h1>

      <form onSubmit={addProduct} className="card p-5 grid md:grid-cols-5 gap-3 items-end">
        <label className="text-sm md:col-span-2">Product name
          <input className={`${input} w-full mt-1`} value={name}
                 onChange={(e) => setName(e.target.value)} required /></label>
        <label className="text-sm">Sell price $
          <input className={`${input} w-full mt-1`} value={sell} type="number" step="0.01"
                 onChange={(e) => setSell(e.target.value)} required /></label>
        <label className="text-sm">Cost $
          <input className={`${input} w-full mt-1`} value={cost} type="number" step="0.01"
                 onChange={(e) => setCost(e.target.value)} /></label>
        <label className="text-sm">Opening qty
          <input className={`${input} w-full mt-1`} value={qty} type="number"
                 onChange={(e) => setQty(e.target.value)} /></label>
        <button className="md:col-span-5 justify-self-start px-4 py-2 rounded-lg bg-brand dark:bg-brand-dark text-white text-sm font-medium">
          Add product (barcode auto-generated)
        </button>
      </form>
      {error && <p className="text-sm" style={{ color: 'var(--status-critical)' }}>{error}</p>}

      {suggestions.length > 0 && (
        <div className="card p-5">
          <h2 className="font-medium mb-2">🔮 AI reorder suggestions</h2>
          <ul className="text-sm flex flex-col gap-1">
            {suggestions.map((s) => (
              <li key={s.name}>
                <span className="font-medium">{s.name}</span>
                <span style={{ color: 'var(--text-secondary)' }}>
                  {' '}— {s.on_hand} left, order ~{s.suggested_order_qty}
                </span>
              </li>
            ))}
          </ul>
        </div>
      )}

      <div className="card p-5 overflow-x-auto">
        <h2 className="font-medium mb-3">Stock levels</h2>
        <table className="w-full text-sm" style={{ fontVariantNumeric: 'tabular-nums' }}>
          <thead>
            <tr className="text-left" style={{ color: 'var(--muted)' }}>
              <th className="py-1 font-medium">Product</th>
              <th className="py-1 font-medium">On hand</th>
              <th className="py-1 font-medium">Reorder level</th>
              <th className="py-1 font-medium">Status</th>
            </tr>
          </thead>
          <tbody>
            {levels.map((l) => (
              <tr key={l.product_id} className="border-t border-black/5 dark:border-white/5">
                <td className="py-2">{l.name}</td>
                <td className="py-2">{l.on_hand}</td>
                <td className="py-2">{l.reorder_level}</td>
                <td className="py-2">
                  {l.below_reorder
                    ? <span style={{ color: 'var(--status-critical)' }}>⚠ Reorder</span>
                    : <span style={{ color: 'var(--delta-good)' }}>✓ OK</span>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}
