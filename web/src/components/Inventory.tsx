import { FormEvent, useEffect, useState } from 'react'
import { api, can, StockLevel } from '../api'
import BarcodeScanner from './BarcodeScanner'
import BranchSelect, { useShops } from './BranchSelect'
import { toast } from '../toast'

interface ReorderSuggestion {
  name: string
  on_hand: number
  suggested_order_qty: number
}

interface ProductRow {
  id: string
  name: string
  sku: string
  barcode: string | null
  sell_price: string
  cost_price: string
  is_active: boolean
}

export default function Inventory() {
  const shops = useShops()
  const [shopId, setShopId] = useState('')
  const [levels, setLevels] = useState<StockLevel[]>([])
  const [products, setProducts] = useState<Record<string, ProductRow>>({})
  const [suggestions, setSuggestions] = useState<ReorderSuggestion[]>([])
  const [name, setName] = useState('')
  const [sell, setSell] = useState('')
  const [cost, setCost] = useState('')
  const [qty, setQty] = useState('')
  const [barcode, setBarcode] = useState('')
  const [editPrice, setEditPrice] = useState<{ id: string; value: string } | null>(null)
  const [editBarcode, setEditBarcode] = useState<{ id: string; value: string } | null>(null)
  // 'form' scans into the new-product code field; 'edit:<id>' assigns to a row.
  const [scanTarget, setScanTarget] = useState<null | 'form' | string>(null)
  const [error, setError] = useState('')

  const canEditPrice = can('products.update')

  function refresh() {
    const q = shopId ? `?shop_id=${shopId}` : ''
    api.get<StockLevel[]>(`/stock/levels${q}`).then(setLevels).catch((e) => setError(e.message))
    api.get<ProductRow[]>('/products').then((rows) =>
      setProducts(Object.fromEntries(rows.map((r) => [r.id, r])))).catch(() => {})
    api.get<ReorderSuggestion[]>('/analytics/reorder-suggestions')
      .then(setSuggestions).catch(() => setSuggestions([]))
  }
  useEffect(refresh, [shopId])

  async function addProduct(e: FormEvent) {
    e.preventDefault()
    setError('')
    if (!barcode.trim()) {
      setError('Please enter or scan the product code')
      return
    }
    try {
      const product = await api.post<{ id: string }>('/products', {
        name, sell_price: sell, cost_price: cost || '0', barcode: barcode.trim(),
      })
      if (Number(qty) > 0) {
        await api.post('/stock/movements', {
          product_id: product.id, movement_type: 'purchase', qty: Number(qty),
          ...(shopId ? { shop_id: shopId } : {}),
        })
      }
      setName(''); setSell(''); setCost(''); setQty(''); setBarcode('')
      toast('Product added')
      refresh()
    } catch (err) {
      setError((err as Error).message)
    }
  }

  async function savePrice() {
    if (!editPrice) return
    try {
      await api.patch(`/products/${editPrice.id}`, { sell_price: editPrice.value })
      toast('Price updated')
      setEditPrice(null)
      refresh()
    } catch (e) {
      toast((e as Error).message, 'error')
    }
  }

  async function saveBarcode() {
    if (!editBarcode) return
    try {
      await api.patch(`/products/${editBarcode.id}`, { barcode: editBarcode.value.trim() })
      toast('Barcode assigned')
      setEditBarcode(null)
      refresh()
    } catch (e) {
      toast((e as Error).message, 'error')
    }
  }

  async function retire(id: string, nameLabel: string) {
    try {
      await api.patch(`/products/${id}`, { is_active: false })
      toast(`${nameLabel} retired`)
      refresh()
    } catch (e) {
      toast((e as Error).message, 'error')
    }
  }

  const input =
    'px-3 py-2 rounded-lg border border-black/15 dark:border-white/15 bg-transparent outline-none'

  return (
    <div className="max-w-4xl flex flex-col gap-4">
      {scanTarget && (
        <BarcodeScanner title="Scan product code"
          onClose={() => setScanTarget(null)}
          onDetect={(code) => {
            if (scanTarget === 'form') setBarcode(code)
            else setEditBarcode({ id: scanTarget, value: code })
            setScanTarget(null)
          }} />
      )}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-2xl font-semibold">Inventory</h1>
          <p className="text-sm" style={{ color: 'var(--muted)' }}>
            {shopId ? `Stock at ${shops.find((s) => s.id === shopId)?.name}` : 'Stock across all branches'}
          </p>
        </div>
        <BranchSelect shops={shops} value={shopId} onChange={setShopId} />
      </div>

      <form onSubmit={addProduct} className="card p-5 grid md:grid-cols-6 gap-3 items-end">
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
        <label className="text-sm">Product code <span style={{ color: 'var(--status-critical)' }}>*</span>
          <div className="flex gap-1 mt-1">
            <input className={`${input} w-full`} value={barcode} required
                   placeholder="scan or type"
                   onChange={(e) => setBarcode(e.target.value)} />
            <button type="button" onClick={() => setScanTarget('form')}
                    title="Scan with camera"
                    className="px-3 rounded-lg border border-black/15 dark:border-white/15">📷</button>
          </div></label>
        <button className="md:col-span-6 justify-self-start px-4 py-2 rounded-lg bg-brand dark:bg-brand-dark text-white text-sm font-medium">
          Add product
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
              <th className="py-1 font-medium">Barcode</th>
              <th className="py-1 font-medium text-right">Price</th>
              <th className="py-1 font-medium text-right">On hand</th>
              <th className="py-1 font-medium text-right">Reorder</th>
              <th className="py-1 font-medium">Status</th>
              {canEditPrice && <th className="py-1 font-medium text-right">Manage</th>}
            </tr>
          </thead>
          <tbody>
            {levels.map((l) => {
              const p = products[l.product_id]
              return (
                <tr key={l.product_id} className="border-t border-black/5 dark:border-white/5">
                  <td className="py-2">{l.name}</td>
                  <td className="py-2">
                    {editBarcode?.id === l.product_id ? (
                      <span className="whitespace-nowrap">
                        <input autoFocus value={editBarcode.value}
                               placeholder="scan or type"
                               onChange={(e) => setEditBarcode({ id: l.product_id, value: e.target.value })}
                               onKeyDown={(e) => { if (e.key === 'Enter') saveBarcode() }}
                               className="w-32 px-2 py-0.5 rounded border border-black/15 dark:border-white/15 bg-transparent" />
                        <button onClick={() => setScanTarget(l.product_id)} className="ml-1 text-xs"
                                title="Scan with camera">📷</button>
                        <button onClick={saveBarcode} className="ml-1 text-xs font-medium"
                                style={{ color: 'var(--delta-good)' }}>✓</button>
                        <button onClick={() => setEditBarcode(null)} className="ml-1 text-xs"
                                style={{ color: 'var(--text-secondary)' }}>✕</button>
                      </span>
                    ) : (
                      <span className="inline-flex items-center gap-1.5">
                        <span className="font-mono text-xs" style={{ color: 'var(--text-secondary)' }}>
                          {p?.barcode ?? '—'}
                        </span>
                        {canEditPrice && (
                          <button onClick={() => setEditBarcode({
                                    id: l.product_id, value: p?.barcode ?? '' })}
                                  className="text-xs" style={{ color: 'var(--series-1)' }}
                                  title="Assign / change barcode">✎</button>
                        )}
                      </span>
                    )}
                  </td>
                  <td className="py-2 text-right">
                    {editPrice?.id === l.product_id ? (
                      <input autoFocus type="number" step="0.01" value={editPrice.value}
                             onChange={(e) => setEditPrice({ id: l.product_id, value: e.target.value })}
                             className="w-20 px-2 py-0.5 rounded border border-black/15 dark:border-white/15 bg-transparent text-right" />
                    ) : (
                      <>${p ? Number(p.sell_price).toFixed(2) : '—'}</>
                    )}
                  </td>
                  <td className="py-2 text-right">{l.on_hand}</td>
                  <td className="py-2 text-right">{l.reorder_level}</td>
                  <td className="py-2">
                    {l.below_reorder
                      ? <span style={{ color: 'var(--status-critical)' }}>⚠ Reorder</span>
                      : <span style={{ color: 'var(--delta-good)' }}>✓ OK</span>}
                  </td>
                  {canEditPrice && (
                    <td className="py-2 text-right whitespace-nowrap">
                      {editPrice?.id === l.product_id ? (
                        <>
                          <button onClick={savePrice} className="mr-2 font-medium"
                                  style={{ color: 'var(--delta-good)' }}>Save</button>
                          <button onClick={() => setEditPrice(null)}
                                  style={{ color: 'var(--text-secondary)' }}>Cancel</button>
                        </>
                      ) : (
                        <>
                          <button onClick={() => setEditPrice({
                                    id: l.product_id, value: p ? p.sell_price : '0' })}
                                  className="mr-3" style={{ color: 'var(--series-1)' }}>
                            Price
                          </button>
                          <button onClick={() => retire(l.product_id, l.name)}
                                  style={{ color: 'var(--status-critical)' }}>Retire</button>
                        </>
                      )}
                    </td>
                  )}
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>
    </div>
  )
}
