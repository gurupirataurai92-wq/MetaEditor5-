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
  tax_amount: string
  currency: string
}

const METHODS = ['cash', 'ecocash', 'onemoney', 'zipit', 'paynow', 'bank'] as const

export default function Pos() {
  const [products, setProducts] = useState<Product[]>([])
  const [search, setSearch] = useState('')
  const [cart, setCart] = useState<CartLine[]>([])
  const [method, setMethod] = useState<(typeof METHODS)[number]>('cash')
  const [receipt, setReceipt] = useState<SaleOut | null>(null)
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

  function add(product: Product) {
    setCart((c) => {
      const line = c.find((l) => l.product.id === product.id)
      return line
        ? c.map((l) => (l.product.id === product.id ? { ...l, qty: l.qty + 1 } : l))
        : [...c, { product, qty: 1 }]
    })
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
            <button key={p.id} onClick={() => add(p)}
                    className="card p-4 text-left hover:border-brand dark:hover:border-brand-dark transition-colors">
              <div className="font-medium text-sm">{p.name}</div>
              <div className="text-xs mt-1" style={{ color: 'var(--muted)' }}>{p.sku}</div>
              <div className="mt-2 font-semibold">${Number(p.sell_price).toFixed(2)}</div>
            </button>
          ))}
        </div>
      </div>

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
            <div className="text-sm mt-2">
              <p style={{ color: 'var(--delta-good)' }}>✓ Sale completed</p>
              <p style={{ color: 'var(--text-secondary)' }}>
                Total ${Number(receipt.total).toFixed(2)} (VAT ${Number(receipt.tax_amount).toFixed(2)})
              </p>
              <a className="underline"
                 href={`/api/v1/sales/${receipt.id}/receipt.pdf`}
                 target="_blank" rel="noreferrer">
                Download receipt (PDF)
              </a>
            </div>
          )}
        </div>
      </aside>
    </div>
  )
}
