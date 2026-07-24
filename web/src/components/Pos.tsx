import { useEffect, useMemo, useState } from 'react'
import { api, Product } from '../api'
import { toast } from '../toast'

interface CartLine {
  product: Product
  qty: number
}

interface SaleOut {
  id: string
  total: string
  subtotal: string
  tax_amount: string
  currency: string
  captured_at: string
  lines: { product_name: string; qty: number; line_total: string }[]
  payments: { method: string; amount: string }[]
}

const METHODS = ['cash', 'ecocash', 'onemoney', 'zipit', 'paynow', 'bank'] as const

export default function Pos() {
  const [products, setProducts] = useState<Product[]>([])
  const [search, setSearch] = useState('')
  const [cart, setCart] = useState<CartLine[]>([])
  const [method, setMethod] = useState<(typeof METHODS)[number]>('cash')
  const [receipt, setReceipt] = useState<SaleOut | null>(null)
  const [picking, setPicking] = useState<Product | null>(null)  // qty picker
  const [pickQty, setPickQty] = useState(1)
  const [error, setError] = useState('')

  useEffect(() => {
    api.get<Product[]>('/products').then(setProducts).catch((e) => setError(e.message))
  }, [])

  const visible = useMemo(() => {
    const q = search.trim().toLowerCase()
    if (!q) return products
    return products.filter(
      (p) => p.name.toLowerCase().includes(q) || p.barcode === q || p.sku.toLowerCase() === q,
    )
  }, [products, search])

  const total = cart.reduce((sum, l) => sum + Number(l.product.sell_price) * l.qty, 0)

  function add(product: Product, qty = 1) {
    setCart((c) => {
      const line = c.find((l) => l.product.id === product.id)
      return line
        ? c.map((l) => (l.product.id === product.id ? { ...l, qty: l.qty + qty } : l))
        : [...c, { product, qty }]
    })
  }

  function openPicker(product: Product) {
    setPicking(product)
    setPickQty(1)
  }

  function confirmPick() {
    if (picking) add(picking, pickQty)
    setPicking(null)
  }

  // Scanning a barcode adds a single unit immediately (no picker needed).
  function onSearchEnter() {
    const q = search.trim().toLowerCase()
    const hit = products.find((p) => p.barcode === q || p.sku.toLowerCase() === q)
    if (hit) {
      add(hit, 1)
      setSearch('')
    }
  }

  async function checkout() {
    setError('')
    try {
      const sale = await api.post<SaleOut>('/sales', {
        id: crypto.randomUUID(), // client-generated → idempotent retry
        currency: 'USD',
        lines: cart.map((l) => ({ product_id: l.product.id, qty: l.qty })),
        payments: [{ method, amount: total.toFixed(2) }],
      })
      setReceipt(sale)
      setCart([])
      toast(`Sale completed — $${sale.total}`)
    } catch (e) {
      setError((e as Error).message)
      toast((e as Error).message, 'error')
    }
  }

  return (
    <div className="flex gap-4 max-w-6xl">
      <div className="flex-1">
        <h1 className="text-2xl font-semibold mb-4">Point of Sale</h1>
        <input
          className="w-full px-3 py-2 mb-4 rounded-lg border border-black/15 dark:border-white/15 bg-transparent outline-none"
          placeholder="Scan barcode or search products…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter') onSearchEnter() }}
        />
        {error && <p className="mb-2 text-sm" style={{ color: 'var(--status-critical)' }}>{error}</p>}
        {products.length === 0 && (
          <div className="card p-10 text-center">
            <div className="text-4xl mb-2">📦</div>
            <p className="text-sm" style={{ color: 'var(--text-secondary)' }}>
              No products yet — add stock on the Inventory page first.
            </p>
          </div>
        )}
        <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
          {visible.map((p) => (
            <button key={p.id} onClick={() => openPicker(p)}
                    className="card p-4 text-left hover:border-brand dark:hover:border-brand-dark transition-colors">
              <div className="font-medium text-sm">{p.name}</div>
              <div className="text-xs mt-1" style={{ color: 'var(--muted)' }}>{p.sku}</div>
              <div className="mt-2 font-semibold">${Number(p.sell_price).toFixed(2)}</div>
            </button>
          ))}
        </div>
      </div>

      {/* Quantity picker — opens each time a product is clicked */}
      {picking && (
        <div className="fixed inset-0 z-40 grid place-items-center p-4"
             style={{ background: 'rgba(0,0,0,0.45)' }}
             onClick={() => setPicking(null)}>
          <div className="card p-6 w-full max-w-xs fade-in" onClick={(e) => e.stopPropagation()}>
            <div className="font-medium">{picking.name}</div>
            <div className="text-sm mb-4" style={{ color: 'var(--muted)' }}>
              ${Number(picking.sell_price).toFixed(2)} each
            </div>
            <div className="flex items-center justify-center gap-3">
              <button onClick={() => setPickQty((q) => Math.max(1, q - 1))}
                      className="w-11 h-11 rounded-lg border border-black/15 dark:border-white/15 text-xl">
                −
              </button>
              <input type="number" min={1} value={pickQty}
                     onChange={(e) => setPickQty(Math.max(1, Number(e.target.value) || 1))}
                     autoFocus
                     onKeyDown={(e) => { if (e.key === 'Enter') confirmPick() }}
                     className="w-20 text-center text-xl font-semibold py-2 rounded-lg border border-black/15 dark:border-white/15 bg-transparent outline-none" />
              <button onClick={() => setPickQty((q) => q + 1)}
                      className="w-11 h-11 rounded-lg border border-black/15 dark:border-white/15 text-xl">
                +
              </button>
            </div>
            <div className="mt-4 text-center text-sm" style={{ color: 'var(--text-secondary)' }}>
              Subtotal ${(Number(picking.sell_price) * pickQty).toFixed(2)}
            </div>
            <div className="flex gap-2 mt-5">
              <button onClick={() => setPicking(null)}
                      className="flex-1 py-2 rounded-lg border border-black/15 dark:border-white/15 text-sm">
                Cancel
              </button>
              <button onClick={confirmPick}
                      className="flex-1 py-2 rounded-lg bg-brand dark:bg-brand-dark text-white text-sm font-medium">
                Add {pickQty} to cart
              </button>
            </div>
          </div>
        </div>
      )}

      <aside className="w-80 shrink-0">
        <div className="card p-5 sticky top-6">
          <h2 className="font-medium mb-3">Cart</h2>
          {cart.length === 0 && !receipt && (
            <p className="text-sm" style={{ color: 'var(--muted)' }}>Tap a product to add it.</p>
          )}
          {cart.map((l) => (
            <div key={l.product.id} className="flex justify-between items-center text-sm py-1">
              <span>{l.product.name} × {l.qty}</span>
              <span>${(Number(l.product.sell_price) * l.qty).toFixed(2)}</span>
            </div>
          ))}
          {cart.length > 0 && (
            <>
              <div className="border-t border-black/10 dark:border-white/10 mt-3 pt-3 flex justify-between font-semibold">
                <span>Total</span>
                <span>${total.toFixed(2)}</span>
              </div>
              <select value={method} onChange={(e) => setMethod(e.target.value as typeof method)}
                      className="w-full mt-3 px-3 py-2 rounded-lg border border-black/15 dark:border-white/15 bg-transparent">
                {METHODS.map((m) => <option key={m} value={m}>{m}</option>)}
              </select>
              <button onClick={checkout}
                      className="w-full mt-3 py-2 rounded-lg bg-brand dark:bg-brand-dark text-white font-medium">
                Charge ${total.toFixed(2)}
              </button>
            </>
          )}
          {receipt && cart.length === 0 && (
            <div className="mt-1 fade-in">
              <div className="flex items-center gap-2 mb-3 text-sm font-medium"
                   style={{ color: 'var(--delta-good)' }}>
                <span className="text-lg">✓</span> Sale completed
              </div>
              {/* Receipt slot — a printable facsimile of the paper receipt */}
              <div className="rounded-lg border border-dashed border-black/20 dark:border-white/20 p-4"
                   style={{ background: 'var(--page)', fontFamily: 'ui-monospace, monospace' }}>
                <div className="text-center">
                  <div className="font-semibold">RECEIPT</div>
                  <div className="text-xs" style={{ color: 'var(--muted)' }}>
                    No. {receipt.id.slice(0, 8).toUpperCase()}
                  </div>
                  <div className="text-xs" style={{ color: 'var(--muted)' }}>
                    {new Date(receipt.captured_at).toLocaleString()}
                  </div>
                </div>
                <div className="border-t border-dashed my-2"
                     style={{ borderColor: 'var(--baseline)' }} />
                {receipt.lines.map((l, i) => (
                  <div key={i} className="flex justify-between text-xs py-0.5">
                    <span className="truncate">{l.product_name} ×{l.qty}</span>
                    <span>{Number(l.line_total).toFixed(2)}</span>
                  </div>
                ))}
                <div className="border-t border-dashed my-2"
                     style={{ borderColor: 'var(--baseline)' }} />
                <div className="flex justify-between text-xs">
                  <span>Subtotal (ex VAT)</span><span>{Number(receipt.subtotal).toFixed(2)}</span>
                </div>
                <div className="flex justify-between text-xs">
                  <span>VAT</span><span>{Number(receipt.tax_amount).toFixed(2)}</span>
                </div>
                <div className="flex justify-between text-sm font-semibold mt-1">
                  <span>TOTAL {receipt.currency}</span>
                  <span>{Number(receipt.total).toFixed(2)}</span>
                </div>
                <div className="text-center text-xs mt-3" style={{ color: 'var(--muted)' }}>
                  Thank you! · Powered by SIMS AI
                </div>
              </div>
              <div className="flex gap-2 mt-3">
                <a href={`/api/v1/sales/${receipt.id}/receipt.pdf`}
                   target="_blank" rel="noreferrer"
                   onClick={(e) => {
                     e.preventDefault()
                     const w = window.open(`/api/v1/sales/${receipt.id}/receipt.pdf`, '_blank')
                     w?.addEventListener('load', () => w.print())
                   }}
                   className="flex-1 text-center py-2 rounded-lg bg-brand dark:bg-brand-dark text-white text-sm font-medium">
                  🖨 Print
                </a>
                <a href={`/api/v1/sales/${receipt.id}/receipt.pdf`}
                   target="_blank" rel="noreferrer"
                   className="flex-1 text-center py-2 rounded-lg border border-black/15 dark:border-white/15 text-sm">
                  ⬇ PDF
                </a>
              </div>
              <button onClick={() => setReceipt(null)}
                      className="w-full mt-2 py-2 rounded-lg text-sm hover:bg-black/5 dark:hover:bg-white/5"
                      style={{ color: 'var(--text-secondary)' }}>
                New sale
              </button>
            </div>
          )}
        </div>
      </aside>
    </div>
  )
}
