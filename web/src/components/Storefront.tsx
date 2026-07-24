import { FormEvent, useEffect, useMemo, useState } from 'react'
import { LogoMark } from './Logo'

// Public, no-login customer storefront. Rendered when the URL has ?store=<tenantId>.
const BASE = '/api/v1'

interface StoreProduct { id: string; name: string; sell_price: string; currency: string }
interface StoreBranch { id: string; name: string; address: string | null }
interface Store {
  business_name: string
  currency: string
  branches: StoreBranch[]
  products: StoreProduct[]
}
interface PlacedOrder { number: string; total: string; status: string; fulfillment: string }

const METHODS = ['ecocash', 'onemoney', 'zipit', 'paynow', 'cash'] as const

export default function Storefront({ tenantId }: { tenantId: string }) {
  const [store, setStore] = useState<Store | null>(null)
  const [error, setError] = useState('')
  const [cart, setCart] = useState<Record<string, number>>({})
  const [search, setSearch] = useState('')
  const [checkout, setCheckout] = useState(false)
  const [placed, setPlaced] = useState<PlacedOrder | null>(null)
  const [form, setForm] = useState({
    customer_name: '', customer_phone: '', customer_address: '',
    fulfillment: 'delivery', shop_id: '', payment_method: 'ecocash',
    payment_reference: '', note: '',
  })
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    fetch(`${BASE}/public/${tenantId}/store`)
      .then((r) => r.ok ? r.json() : Promise.reject(new Error('Store not found')))
      .then((s: Store) => {
        setStore(s)
        setForm((f) => ({ ...f, shop_id: s.branches[0]?.id ?? '' }))
      })
      .catch((e) => setError(e.message))
  }, [tenantId])

  const priceById = useMemo(
    () => Object.fromEntries((store?.products ?? []).map((p) => [p.id, Number(p.sell_price)])),
    [store])
  const nameById = useMemo(
    () => Object.fromEntries((store?.products ?? []).map((p) => [p.id, p.name])),
    [store])
  const total = Object.entries(cart).reduce((s, [id, q]) => s + priceById[id] * q, 0)
  const itemCount = Object.values(cart).reduce((s, q) => s + q, 0)

  const visible = useMemo(() => {
    const q = search.trim().toLowerCase()
    return (store?.products ?? []).filter((p) => !q || p.name.toLowerCase().includes(q))
  }, [store, search])

  function setQty(id: string, qty: number) {
    setCart((c) => {
      const next = { ...c }
      if (qty <= 0) delete next[id]
      else next[id] = qty
      return next
    })
  }

  async function submit(e: FormEvent) {
    e.preventDefault()
    setBusy(true)
    setError('')
    try {
      const resp = await fetch(`${BASE}/public/${tenantId}/orders`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          ...form,
          customer_address: form.customer_address || null,
          payment_reference: form.payment_reference || null,
          note: form.note || null,
          items: Object.entries(cart).map(([product_id, qty]) => ({ product_id, qty })),
        }),
      })
      if (!resp.ok) throw new Error((await resp.json()).detail ?? 'Could not place order')
      setPlaced(await resp.json())
      setCart({})
      setCheckout(false)
    } catch (err) {
      setError((err as Error).message)
    } finally {
      setBusy(false)
    }
  }

  const cur = (n: number) => `${store?.currency === 'USD' ? '$' : `${store?.currency} `}${n.toFixed(2)}`
  const input =
    'w-full px-3 py-2 rounded-lg border border-black/15 dark:border-white/15 bg-transparent outline-none focus:border-brand mt-1'

  if (error && !store) {
    return <div className="min-h-screen grid place-items-center p-6 text-center">
      <div><div className="text-4xl mb-2">🏬</div><p>{error}</p></div>
    </div>
  }
  if (!store) return <div className="min-h-screen grid place-items-center">Loading store…</div>

  if (placed) {
    return (
      <div className="min-h-screen grid place-items-center p-6">
        <div className="card p-8 max-w-sm text-center fade-in">
          <div className="text-5xl mb-3">🎉</div>
          <h1 className="text-xl font-semibold">Order placed!</h1>
          <p className="mt-2 text-sm" style={{ color: 'var(--text-secondary)' }}>
            Your order <b>{placed.number}</b> for <b>{cur(Number(placed.total))}</b> is in.
            {' '}{store.business_name} will {placed.fulfillment === 'delivery'
              ? 'deliver it to you' : 'have it ready for pickup'} shortly.
          </p>
          <button onClick={() => setPlaced(null)}
            className="mt-5 px-5 py-2.5 rounded-lg bg-brand text-white text-sm font-medium">
            Shop again
          </button>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen" style={{ background: 'var(--page)' }}>
      <header className="sticky top-0 z-20 border-b border-black/10 dark:border-white/10"
              style={{ background: 'var(--surface-1)' }}>
        <div className="max-w-5xl mx-auto px-4 py-3 flex items-center justify-between gap-3">
          <div className="flex items-center gap-2.5">
            <LogoMark size={34} />
            <div>
              <div className="font-semibold leading-tight">{store.business_name}</div>
              <div className="text-xs" style={{ color: 'var(--muted)' }}>Online store</div>
            </div>
          </div>
          <button onClick={() => setCheckout(true)} disabled={itemCount === 0}
            className="relative px-4 py-2 rounded-lg bg-brand text-white text-sm font-medium disabled:opacity-40">
            🛒 Cart · {cur(total)}
            {itemCount > 0 && (
              <span className="absolute -top-2 -right-2 w-5 h-5 grid place-items-center rounded-full text-xs"
                    style={{ background: 'var(--series-6)' }}>{itemCount}</span>
            )}
          </button>
        </div>
      </header>

      <main className="max-w-5xl mx-auto p-4">
        <input value={search} onChange={(e) => setSearch(e.target.value)}
               placeholder="Search products…"
               className="w-full px-4 py-2.5 mb-4 rounded-xl border border-black/15 dark:border-white/15 bg-transparent outline-none"
               style={{ background: 'var(--surface-1)' }} />
        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
          {visible.map((p) => {
            const qty = cart[p.id] ?? 0
            return (
              <div key={p.id} className="card p-4 flex flex-col">
                <div className="text-3xl mb-2">🛍️</div>
                <div className="font-medium text-sm leading-tight">{p.name}</div>
                <div className="mt-1 font-semibold">{cur(Number(p.sell_price))}</div>
                {qty === 0 ? (
                  <button onClick={() => setQty(p.id, 1)}
                    className="mt-3 py-1.5 rounded-lg bg-brand text-white text-sm font-medium">
                    Add
                  </button>
                ) : (
                  <div className="mt-3 flex items-center justify-between">
                    <button onClick={() => setQty(p.id, qty - 1)}
                            className="w-8 h-8 rounded-lg border border-black/15 dark:border-white/15">−</button>
                    <span className="font-semibold">{qty}</span>
                    <button onClick={() => setQty(p.id, qty + 1)}
                            className="w-8 h-8 rounded-lg border border-black/15 dark:border-white/15">+</button>
                  </div>
                )}
              </div>
            )
          })}
        </div>
      </main>

      {/* Checkout drawer */}
      {checkout && (
        <div className="fixed inset-0 z-30 flex justify-end"
             style={{ background: 'rgba(0,0,0,0.45)' }} onClick={() => setCheckout(false)}>
          <form onSubmit={submit} onClick={(e) => e.stopPropagation()}
                className="w-full max-w-md h-full overflow-y-auto p-6 flex flex-col gap-3 fade-in"
                style={{ background: 'var(--surface-1)' }}>
            <h2 className="text-lg font-semibold">Checkout</h2>
            <div className="flex flex-col gap-1 text-sm">
              {Object.entries(cart).map(([id, q]) => (
                <div key={id} className="flex justify-between">
                  <span>{nameById[id]} × {q}</span>
                  <span>{cur(priceById[id] * q)}</span>
                </div>
              ))}
              <div className="flex justify-between font-semibold border-t border-black/10 dark:border-white/10 mt-2 pt-2">
                <span>Total</span><span>{cur(total)}</span>
              </div>
            </div>

            <label className="text-sm">Your name
              <input className={input} required value={form.customer_name}
                     onChange={(e) => setForm({ ...form, customer_name: e.target.value })} /></label>
            <label className="text-sm">Phone (EcoCash number)
              <input className={input} required value={form.customer_phone}
                     onChange={(e) => setForm({ ...form, customer_phone: e.target.value })} /></label>

            <div className="text-sm">How would you like it?
              <div className="flex gap-2 mt-1">
                {(['delivery', 'pickup'] as const).map((f) => (
                  <button type="button" key={f} onClick={() => setForm({ ...form, fulfillment: f })}
                    className={`flex-1 py-2 rounded-lg border text-sm capitalize ${
                      form.fulfillment === f
                        ? 'border-brand text-white bg-brand'
                        : 'border-black/15 dark:border-white/15'}`}>
                    {f === 'delivery' ? '🚚 Delivery' : '🏬 Pickup'}
                  </button>
                ))}
              </div>
            </div>

            {form.fulfillment === 'delivery' && (
              <label className="text-sm">Delivery address
                <input className={input} required value={form.customer_address}
                       onChange={(e) => setForm({ ...form, customer_address: e.target.value })} /></label>
            )}
            {store.branches.length > 1 && (
              <label className="text-sm">{form.fulfillment === 'pickup' ? 'Pickup branch' : 'Fulfilling branch'}
                <select className={input} value={form.shop_id}
                        onChange={(e) => setForm({ ...form, shop_id: e.target.value })}>
                  {store.branches.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
                </select></label>
            )}
            <label className="text-sm">Payment method
              <select className={input} value={form.payment_method}
                      onChange={(e) => setForm({ ...form, payment_method: e.target.value })}>
                {METHODS.map((m) => <option key={m} value={m}>{m}</option>)}
              </select></label>
            {form.payment_method !== 'cash' && (
              <label className="text-sm">Payment reference (after you pay)
                <input className={input} placeholder="e.g. EcoCash confirmation code"
                       value={form.payment_reference}
                       onChange={(e) => setForm({ ...form, payment_reference: e.target.value })} /></label>
            )}
            {error && <p className="text-sm" style={{ color: 'var(--status-critical)' }}>{error}</p>}
            <button disabled={busy}
              className="mt-2 py-2.5 rounded-lg bg-brand text-white font-medium disabled:opacity-50">
              {busy ? 'Placing…' : `Place order · ${cur(total)}`}
            </button>
            <button type="button" onClick={() => setCheckout(false)}
                    className="py-2 text-sm" style={{ color: 'var(--text-secondary)' }}>
              Keep shopping
            </button>
          </form>
        </div>
      )}
    </div>
  )
}
