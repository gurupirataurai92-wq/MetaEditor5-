import { useEffect, useState } from 'react'
import { api, Shop } from '../api'

/** Shared branch picker. `value` of '' means "All branches". */
export function useShops() {
  const [shops, setShops] = useState<Shop[]>([])
  useEffect(() => {
    api.get<Shop[]>('/shops').then(setShops).catch(() => setShops([]))
  }, [])
  return shops
}

export default function BranchSelect({
  shops, value, onChange, allowAll = true,
}: {
  shops: Shop[]
  value: string
  onChange: (v: string) => void
  allowAll?: boolean
}) {
  if (shops.length <= 1 && allowAll) return null
  return (
    <div className="flex items-center gap-2">
      <span className="text-sm hidden sm:inline" style={{ color: 'var(--muted)' }}>🏬</span>
      <select value={value} onChange={(e) => onChange(e.target.value)}
        className="px-3 py-1.5 rounded-lg text-sm border border-black/15 dark:border-white/15 bg-transparent outline-none focus:border-brand dark:focus:border-brand-dark">
        {allowAll && <option value="">All branches</option>}
        {shops.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
      </select>
    </div>
  )
}
