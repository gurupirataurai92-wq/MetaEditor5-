import { FormEvent, useEffect, useState } from 'react'
import { api } from '../api'
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

  const staffAt = (shopId: string) => employees.filter((e) => e.shop_id === shopId)

  const input =
    'px-3 py-2 rounded-lg border border-black/15 dark:border-white/15 bg-transparent outline-none w-full mt-1'

  return (
    <div className="max-w-4xl flex flex-col gap-4">
      <h1 className="text-2xl font-semibold">Branches</h1>

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
                <div className="mt-3 text-sm" style={{ color: 'var(--text-secondary)' }}>
                  {staff.length} staff assigned ·{' '}
                  <span style={{ color: onDuty > 0 ? 'var(--delta-good)' : 'var(--muted)' }}>
                    {onDuty} on duty now
                  </span>
                </div>
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}
