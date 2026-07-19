import { FormEvent, useEffect, useState } from 'react'
import { api } from '../api'
import { toast } from '../toast'

interface EmployeeRow {
  id: string
  full_name: string
  position: string | null
  shop_id: string | null
  on_duty: boolean
  user_id: string | null
}

interface Shop {
  id: string
  name: string
}

const ROLES = ['cashier', 'storekeeper', 'accountant', 'manager'] as const

export default function Staff() {
  const [employees, setEmployees] = useState<EmployeeRow[] | null>(null)
  const [shops, setShops] = useState<Shop[]>([])
  const [form, setForm] = useState({
    full_name: '', position: '', email: '', password: '',
    role: 'cashier', shop_id: '',
  })
  const [error, setError] = useState('')

  function refresh() {
    api.get<EmployeeRow[]>('/employees').then(setEmployees).catch((e) => setError(e.message))
    api.get<Shop[]>('/shops').then(setShops).catch(() => setShops([]))
  }
  useEffect(refresh, [])

  async function hire(e: FormEvent) {
    e.preventDefault()
    setError('')
    try {
      await api.post('/staff', {
        ...form,
        position: form.position || null,
        shop_id: form.shop_id || null,
      })
      toast(`${form.full_name} hired — they sign in with their own password`)
      setForm({ full_name: '', position: '', email: '', password: '',
                role: 'cashier', shop_id: '' })
      refresh()
    } catch (err) {
      setError((err as Error).message)
    }
  }

  async function setDuty(emp: EmployeeRow, on: boolean) {
    try {
      await api.patch(`/employees/${emp.id}`, { on_duty: on })
      toast(`${emp.full_name} is now ${on ? 'ON' : 'OFF'} duty`)
      refresh()
    } catch (e) {
      toast((e as Error).message, 'error')
    }
  }

  const shopName = (id: string | null) =>
    shops.find((s) => s.id === id)?.name ?? '—'
  const onDuty = employees?.filter((e) => e.on_duty).length ?? 0

  const input =
    'px-3 py-2 rounded-lg border border-black/15 dark:border-white/15 bg-transparent outline-none w-full mt-1'

  return (
    <div className="max-w-5xl flex flex-col gap-4">
      <div className="flex items-center gap-3 flex-wrap">
        <h1 className="text-2xl font-semibold">Staff & duty</h1>
        {employees && (
          <span className="text-xs px-2.5 py-1 rounded-full"
                style={{ background: 'rgba(12,163,12,0.12)', color: 'var(--delta-good)' }}>
            {onDuty} on duty · {employees.length - onDuty} off duty
          </span>
        )}
      </div>

      <form onSubmit={hire} className="card p-5 grid md:grid-cols-3 gap-3">
        <h2 className="font-medium md:col-span-3">Hire a new employee</h2>
        <label className="text-sm">Full name
          <input className={input} value={form.full_name} required
                 onChange={(e) => setForm({ ...form, full_name: e.target.value })} /></label>
        <label className="text-sm">Position
          <input className={input} value={form.position} placeholder="e.g. Till Operator"
                 onChange={(e) => setForm({ ...form, position: e.target.value })} /></label>
        <label className="text-sm">System role
          <select className={input} value={form.role}
                  onChange={(e) => setForm({ ...form, role: e.target.value })}>
            {ROLES.map((r) => <option key={r} value={r}>{r}</option>)}
          </select></label>
        <label className="text-sm">Branch
          <select className={input} value={form.shop_id}
                  onChange={(e) => setForm({ ...form, shop_id: e.target.value })}>
            <option value="">— unassigned —</option>
            {shops.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </select></label>
        <label className="text-sm">Login email
          <input className={input} type="email" value={form.email} required
                 onChange={(e) => setForm({ ...form, email: e.target.value })} /></label>
        <label className="text-sm">Password <span style={{ color: 'var(--muted)' }}>(typed by the employee)</span>
          <input className={input} type="password" value={form.password} required minLength={8}
                 onChange={(e) => setForm({ ...form, password: e.target.value })} /></label>
        <p className="text-xs md:col-span-2 self-center" style={{ color: 'var(--muted)' }}>
          🔒 The employee types their own password at hiring. It is stored
          encrypted and can never be viewed by anyone — including you.
        </p>
        <button className="justify-self-start self-center px-4 py-2 rounded-lg bg-brand dark:bg-brand-dark text-white text-sm font-medium">
          Hire employee
        </button>
      </form>
      {error && <p className="text-sm" style={{ color: 'var(--status-critical)' }}>{error}</p>}

      <div className="card p-5 overflow-x-auto">
        <h2 className="font-medium mb-3">Team</h2>
        {employees === null ? (
          <div className="skeleton w-full" style={{ height: 160 }} />
        ) : employees.length === 0 ? (
          <p className="text-sm" style={{ color: 'var(--muted)' }}>
            No employees yet — hire your first team member above.
          </p>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left" style={{ color: 'var(--muted)' }}>
                <th className="py-1.5 font-medium">Name</th>
                <th className="py-1.5 font-medium">Position</th>
                <th className="py-1.5 font-medium">Branch</th>
                <th className="py-1.5 font-medium">Status</th>
                <th className="py-1.5 font-medium text-right">Duty</th>
              </tr>
            </thead>
            <tbody>
              {employees.map((emp) => (
                <tr key={emp.id} className="border-t border-black/5 dark:border-white/5">
                  <td className="py-2.5 font-medium">{emp.full_name}</td>
                  <td className="py-2.5" style={{ color: 'var(--text-secondary)' }}>
                    {emp.position ?? '—'}
                  </td>
                  <td className="py-2.5">{shopName(emp.shop_id)}</td>
                  <td className="py-2.5">
                    {emp.on_duty ? (
                      <span className="px-2 py-0.5 rounded-full text-xs"
                            style={{ background: 'rgba(12,163,12,0.12)', color: 'var(--delta-good)' }}>
                        ● on duty
                      </span>
                    ) : (
                      <span className="px-2 py-0.5 rounded-full text-xs"
                            style={{ background: 'var(--grid)', color: 'var(--text-secondary)' }}>
                        ○ off duty
                      </span>
                    )}
                  </td>
                  <td className="py-2.5 text-right">
                    <button onClick={() => setDuty(emp, !emp.on_duty)}
                            className="px-3 py-1 rounded-lg text-xs border border-black/15 dark:border-white/15 hover:bg-black/5 dark:hover:bg-white/5">
                      {emp.on_duty ? 'Clock out' : 'Clock in'}
                    </button>
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
