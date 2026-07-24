import { FormEvent, useEffect, useState } from 'react'
import { api, can, getClaims } from '../api'
import { toast } from '../toast'

interface Shop {
  id: string
  name: string
  address: string | null
}

interface EmployeeRow {
  shop_id: string | null
  on_duty: boolean
}

export default function Branches() {
  const [shops, setShops] = useState<Shop[] | null>(null)
  const [employees, setEmployees] = useState<EmployeeRow[]>([])
  const [name, setName] = useState('')
  const [address, setAddress] = useState('')
  const [error, setError] = useState('')

  function refresh() {
    api.get<Shop[]>('/shops').then(setShops).catch((e) => setError(e.message))
    api.get<EmployeeRow[]>('/employees').then(setEmployees).catch(() => setEmployees([]))
  }
  useEffect(refresh, [])

  async function addBranch(e: FormEvent) {
    e.preventDefault()
    setError('')
    try {
      await api.post('/shops', { name, address: address || null })
      toast(`Branch "${name}" opened`)
      setName('')
      setAddress('')
      refresh()
    } catch (err) {
      setError((err as Error).message)
    }
  }

  const [confirmDel, setConfirmDel] = useState<string | null>(null)
  async function deleteBranch(id: string, label: string) {
    try {
      await api.del(`/shops/${id}`)
      toast(`Branch "${label}" closed`)
      setConfirmDel(null)
      refresh()
    } catch (e) {
      toast((e as Error).message, 'error')
    }
  }

  const staffAt = (shopId: string) => employees.filter((e) => e.shop_id === shopId)

  const input =
    'px-3 py-2 rounded-lg border border-black/15 dark:border-white/15 bg-transparent outline-none w-full mt-1'

  return (
    <div className="max-w-4xl flex flex-col gap-4">
      <h1 className="text-2xl font-semibold">Branches</h1>

      <div className="card p-5" style={{ backgroundImage: 'var(--brand-grad)', color: '#fff' }}>
        <div className="flex items-center justify-between flex-wrap gap-3">
          <div>
            <div className="font-medium">🛍️ Your online store</div>
            <div className="text-sm text-white/80">
              Share this link — customers order from home; orders appear under Online Orders.
            </div>
          </div>
          <button onClick={() => {
                    const link = `${window.location.origin}/?store=${getClaims()?.tenant_id ?? ''}`
                    navigator.clipboard?.writeText(link)
                    toast('Store link copied')
                  }}
                  className="px-4 py-2 rounded-lg bg-white/20 hover:bg-white/30 text-sm font-medium">
            🔗 Copy store link
          </button>
        </div>
      </div>

      <form onSubmit={addBranch} className="card p-5 grid md:grid-cols-3 gap-3 items-end">
        <label className="text-sm">Branch name
          <input className={input} value={name} required
                 onChange={(e) => setName(e.target.value)} /></label>
        <label className="text-sm">Address
          <input className={input} value={address} placeholder="optional"
                 onChange={(e) => setAddress(e.target.value)} /></label>
        <button className="justify-self-start px-4 py-2 rounded-lg bg-brand dark:bg-brand-dark text-white text-sm font-medium">
          Open branch
        </button>
      </form>
      {error && <p className="text-sm" style={{ color: 'var(--status-critical)' }}>{error}</p>}

      {shops === null ? (
        <div className="skeleton w-full" style={{ height: 160 }} />
      ) : (
        <div className="grid md:grid-cols-2 gap-4">
          {shops.map((shop) => {
            const staff = staffAt(shop.id)
            const onDuty = staff.filter((s) => s.on_duty).length
            return (
              <div key={shop.id} className="card p-5">
                <div className="flex items-start justify-between">
                  <div>
                    <div className="font-medium">🏬 {shop.name}</div>
                    <div className="text-sm mt-0.5" style={{ color: 'var(--text-secondary)' }}>
                      {shop.address ?? 'No address recorded'}
                    </div>
                  </div>
                </div>
                <div className="mt-3 flex items-center justify-between">
                  <span className="text-sm" style={{ color: 'var(--text-secondary)' }}>
                    {staff.length} staff ·{' '}
                    <span style={{ color: onDuty > 0 ? 'var(--delta-good)' : 'var(--muted)' }}>
                      {onDuty} on duty
                    </span>
                  </span>
                  {can('shops.delete') && (
                    confirmDel === shop.id ? (
                      <span className="text-xs">
                        <button onClick={() => deleteBranch(shop.id, shop.name)}
                                className="font-medium mr-2"
                                style={{ color: 'var(--status-critical)' }}>Confirm close</button>
                        <button onClick={() => setConfirmDel(null)}
                                style={{ color: 'var(--text-secondary)' }}>Cancel</button>
                      </span>
                    ) : (
                      <button onClick={() => setConfirmDel(shop.id)}
                              className="text-xs" style={{ color: 'var(--status-critical)' }}>
                        Close branch
                      </button>
                    )
                  )}
                </div>
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}
