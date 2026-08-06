import { useEffect, useMemo, useState } from 'react'
import {
  Area, CartesianGrid, ComposedChart, Line,
  ResponsiveContainer, Tooltip, XAxis, YAxis,
} from 'recharts'
import { Anomaly, api, BranchRow, Forecast, Pnl, SalesSummary } from '../api'
import BranchSelect, { useShops } from './BranchSelect'

const RANGES = [
  { id: '7d', label: 'Last 7 days', days: 7 },
  { id: '30d', label: 'Last 30 days', days: 30 },
  { id: '90d', label: 'Last 90 days', days: 90 },
  { id: 'mtd', label: 'Month to date', days: 0 },
] as const
type RangeId = (typeof RANGES)[number]['id']

interface CashFlow {
  inflows_by_method: { method: string; amount: string }[]
  inflows: string
  outflows: string
  net_cash_flow: string
}
interface PnlFull extends Pnl {
  expenses_by_category: { category: string; amount: string }[]
}

function fmtMoney(v: string): string {
  const n = Number(v)
  return `${n < 0 ? '\u2212' : ''}$${Math.abs(n).toFixed(2)}`
}

function rangeDates(id: RangeId): { from: Date; to: Date } {
  const to = new Date()
  const from = new Date()
  if (id === 'mtd') {
    from.setDate(1)
    from.setHours(0, 0, 0, 0)
  } else {
    from.setDate(to.getDate() - RANGES.find((r) => r.id === id)!.days)
  }
  return { from, to }
}

function previousPeriod(from: Date, to: Date): { from: Date; to: Date } {
  const span = to.getTime() - from.getTime()
  return { from: new Date(from.getTime() - span), to: from }
}

function delta(current: string, previous: string): { text: string; up: boolean } | null {
  const c = Number(current)
  const p = Number(previous)
  if (!isFinite(c) || !isFinite(p) || p === 0) return null
  const pct = ((c - p) / Math.abs(p)) * 100
  return { text: `${pct >= 0 ? '▲' : '▼'} ${Math.abs(pct).toFixed(0)}% vs prev period`, up: pct >= 0 }
}

function StatTile({ label, value, deltaInfo, accent }: {
  label: string
  value: string
  deltaInfo?: { text: string; up: boolean } | null
  accent?: string
}) {
  return (
    <div className="card stat-accent p-5" style={accent ? { ['--accent' as string]: accent } : undefined}>
      <div className="text-sm" style={{ color: 'var(--text-secondary)' }}>{label}</div>
      <div className="text-3xl font-semibold mt-1">{value}</div>
      {deltaInfo && (
        <div className="text-xs mt-1.5"
             style={{ color: deltaInfo.up ? 'var(--delta-good)' : 'var(--status-critical)' }}>
          {deltaInfo.text}
        </div>
      )}
    </div>
  )
}

function BarList({ items, max }: { items: { label: string; value: string }[]; max: number }) {
  return (
    <div className="flex flex-col gap-2">
      {items.map((item) => (
        <div key={item.label} className="text-sm">
          <div className="flex justify-between mb-0.5">
            <span className="capitalize">{item.label}</span>
            <span style={{ color: 'var(--text-secondary)', fontVariantNumeric: 'tabular-nums' }}>
              ${item.value}
            </span>
          </div>
          <div className="h-2 rounded" style={{ background: 'var(--grid)' }}>
            <div className="h-2 rounded" style={{
              width: `${Math.min(100, (Number(item.value) / (max || 1)) * 100)}%`,
              background: 'var(--series-1)',
            }} />
          </div>
        </div>
      ))}
    </div>
  )
}

function Skeleton({ h }: { h: string }) {
  return <div className="skeleton w-full" style={{ height: h }} />
}

export default function Dashboard({ onGoToPos }: { onGoToPos?: () => void }) {
  const shops = useShops()
  const [shopId, setShopId] = useState('')
  const [range, setRange] = useState<RangeId>('30d')
  const [pnl, setPnl] = useState<PnlFull | null>(null)
  const [prevPnl, setPrevPnl] = useState<PnlFull | null>(null)
  const [summary, setSummary] = useState<SalesSummary | null>(null)
  const [cash, setCash] = useState<CashFlow | null>(null)
  const [forecast, setForecast] = useState<Forecast | null>(null)
  const [branches, setBranches] = useState<BranchRow[]>([])
  const [anomalies, setAnomalies] = useState<Anomaly[]>([])
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const { from, to } = rangeDates(range)
    const prev = previousPeriod(from, to)
    const shop = shopId ? `&shop_id=${shopId}` : ''
    const q = `date_from=${from.toISOString()}&date_to=${to.toISOString()}${shop}`
    const qPrev = `date_from=${prev.from.toISOString()}&date_to=${prev.to.toISOString()}${shop}`
    setLoading(true)
    Promise.all([
      api.get<PnlFull>(`/reports/pnl?${q}`),
      api.get<PnlFull>(`/reports/pnl?${qPrev}`),
      api.get<SalesSummary>(`/reports/sales-summary?${q}`),
      api.get<CashFlow>(`/reports/cashflow?${q}`),
      api.get<Forecast>('/analytics/forecast?days_ahead=7&window=30'),
      api.get<Anomaly[]>('/analytics/anomalies'),
      shopId ? Promise.resolve([]) : api.get<BranchRow[]>(
        `/reports/branches?date_from=${from.toISOString()}&date_to=${to.toISOString()}`),
    ])
      .then(([p, pp, s, c, f, a, b]) => {
        setPnl(p); setPrevPnl(pp); setSummary(s); setCash(c)
        setForecast(f); setAnomalies(a); setBranches(b as BranchRow[]); setError('')
      })
      .catch((e) => setError((e as Error).message))
      .finally(() => setLoading(false))
  }, [range, shopId])

  const chartData = useMemo(() => {
    if (!forecast) return []
    return [
      ...forecast.history.map((h) => ({
        date: h.date.slice(5), actual: h.revenue,
        predicted: null as number | null, bandBase: null as number | null,
        bandDelta: null as number | null,
      })),
      ...forecast.forecast.map((f) => ({
        date: f.date.slice(5), actual: null as number | null,
        predicted: f.value, bandBase: f.low, bandDelta: f.high - f.low,
      })),
    ]
  }, [forecast])

  const axisStyle = { fontSize: 11, fill: 'var(--muted)' }
  const hasSales = (summary?.sales_count ?? 0) > 0

  if (error) return <p style={{ color: 'var(--status-critical)' }}>{error}</p>

  return (
    <div className="flex flex-col gap-4 max-w-6xl">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold">Business overview</h1>
          <p className="text-sm" style={{ color: 'var(--muted)' }}>
            {shopId
              ? shops.find((s) => s.id === shopId)?.name ?? 'Branch'
              : shops.length > 1 ? 'All branches combined' : 'Your business'}
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-3">
          <BranchSelect shops={shops} value={shopId} onChange={setShopId} />
          <div className="flex gap-1 card p-1">
          {RANGES.map((r) => (
            <button key={r.id} onClick={() => setRange(r.id)}
              className={`px-3 py-1.5 rounded-lg text-sm transition-colors ${
                range === r.id
                  ? 'bg-brand/10 dark:bg-brand-dark/20 font-medium'
                  : 'hover:bg-black/5 dark:hover:bg-white/5'
              }`}>
              {r.label}
            </button>
          ))}
          </div>
        </div>
      </div>

      {loading || !pnl || !summary || !cash || !forecast ? (
        <>
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
            {[0, 1, 2, 3].map((i) => <Skeleton key={i} h="106px" />)}
          </div>
          <Skeleton h="320px" />
          <div className="grid lg:grid-cols-2 gap-4">
            <Skeleton h="220px" /><Skeleton h="220px" />
          </div>
        </>
      ) : !hasSales ? (
        <div className="card p-12 text-center flex flex-col items-center gap-3">
          <div className="text-5xl">🛒</div>
          <h2 className="text-lg font-medium">No sales in this period yet</h2>
          <p className="text-sm max-w-sm" style={{ color: 'var(--text-secondary)' }}>
            Once you make your first sale, revenue, profit, forecasts and AI
            insights will appear here automatically.
          </p>
          {onGoToPos && (
            <button onClick={onGoToPos}
              className="mt-1 px-5 py-2.5 rounded-lg bg-brand dark:bg-brand-dark text-white font-medium hover:opacity-90 transition-opacity">
              Make your first sale
            </button>
          )}
        </div>
      ) : (
        <>
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
            <StatTile label="Net revenue" value={fmtMoney(pnl.revenue_net)} accent="var(--series-1)"
                      deltaInfo={prevPnl && delta(pnl.revenue_net, prevPnl.revenue_net)} />
            <StatTile label="Net profit" value={fmtMoney(pnl.net_profit)} accent="var(--series-5)"
                      deltaInfo={prevPnl && delta(pnl.net_profit, prevPnl.net_profit)} />
            <StatTile label="Sales" value={String(summary.sales_count)} accent="var(--series-7)" />
            <StatTile label="VAT collected" value={fmtMoney(pnl.vat_collected)} accent="var(--series-4)" />
          </div>

          {!shopId && branches.length > 1 && (
            <div className="card p-5">
              <h2 className="font-medium mb-3">Performance by branch</h2>
              <div className="overflow-x-auto">
                <table className="w-full text-sm" style={{ fontVariantNumeric: 'tabular-nums' }}>
                  <thead>
                    <tr className="text-left" style={{ color: 'var(--muted)' }}>
                      <th className="py-1.5 font-medium">Branch</th>
                      <th className="py-1.5 font-medium text-right">Sales</th>
                      <th className="py-1.5 font-medium text-right">Revenue</th>
                      <th className="py-1.5 font-medium text-right">Net profit</th>
                      <th className="py-1.5 font-medium text-right"></th>
                    </tr>
                  </thead>
                  <tbody>
                    {branches.map((b) => (
                      <tr key={b.shop_id} className="border-t border-black/5 dark:border-white/5">
                        <td className="py-2.5 font-medium">🏬 {b.name}</td>
                        <td className="py-2.5 text-right">{b.sales_count}</td>
                        <td className="py-2.5 text-right">{fmtMoney(b.revenue)}</td>
                        <td className="py-2.5 text-right"
                            style={{ color: Number(b.net_profit) >= 0 ? 'var(--delta-good)' : 'var(--status-critical)' }}>
                          {fmtMoney(b.net_profit)}
                        </td>
                        <td className="py-2.5 text-right">
                          <button onClick={() => setShopId(b.shop_id)}
                                  className="text-xs underline underline-offset-2"
                                  style={{ color: 'var(--series-1)' }}>
                            View branch →
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          <div className="card p-5">
            <h2 className="font-medium mb-1">Revenue — last 30 days & 7-day forecast</h2>
            <p className="text-xs mb-3" style={{ color: 'var(--muted)' }}>
              Solid: actual daily revenue. Dashed: model forecast with 95% band.
            </p>
            <div className="h-64">
              <ResponsiveContainer>
                <ComposedChart data={chartData} margin={{ top: 4, right: 8, left: 0, bottom: 0 }}>
                  <CartesianGrid stroke="var(--grid)" vertical={false} />
                  <XAxis dataKey="date" tick={axisStyle} stroke="var(--baseline)"
                         tickLine={false} interval="preserveStartEnd" minTickGap={24} />
                  <YAxis tick={axisStyle} stroke="var(--baseline)" tickLine={false}
                         axisLine={false} width={44} />
                  <Tooltip
                    contentStyle={{
                      background: 'var(--surface-1)', border: '1px solid var(--grid)',
                      borderRadius: 8, color: 'var(--text-primary)', fontSize: 12,
                    }}
                  />
                  <Area dataKey="bandBase" stackId="band" stroke="none" fill="none"
                        fillOpacity={0} activeDot={false} connectNulls={false}
                        legendType="none" tooltipType="none" isAnimationActive={false} />
                  <Area dataKey="bandDelta" stackId="band" stroke="none"
                        fill="var(--series-1-soft)" fillOpacity={0.35}
                        activeDot={false} connectNulls={false} legendType="none"
                        isAnimationActive={false} />
                  <Line dataKey="actual" stroke="var(--series-1)" strokeWidth={2}
                        dot={false} connectNulls={false} isAnimationActive={false} />
                  <Line dataKey="predicted" stroke="var(--series-1)" strokeWidth={2}
                        strokeDasharray="5 4" dot={false} connectNulls={false}
                        isAnimationActive={false} />
                </ComposedChart>
              </ResponsiveContainer>
            </div>
          </div>

          <div className="grid lg:grid-cols-2 gap-4">
            <div className="card p-5">
              <h2 className="font-medium mb-3">Top products</h2>
              <BarList
                max={Number(summary.top_products[0]?.revenue ?? 0)}
                items={summary.top_products.map((p) => ({
                  label: `${p.name} · ${p.qty} sold`, value: p.revenue }))}
              />
            </div>

            <div className="card p-5">
              <h2 className="font-medium mb-3">Money in, by payment method</h2>
              <BarList
                max={Math.max(...cash.inflows_by_method.map((i) => Number(i.amount)), 0)}
                items={cash.inflows_by_method.map((i) => ({
                  label: i.method, value: i.amount }))}
              />
              <div className="border-t border-black/10 dark:border-white/10 mt-4 pt-3 text-sm flex flex-col gap-1"
                   style={{ fontVariantNumeric: 'tabular-nums' }}>
                <div className="flex justify-between">
                  <span style={{ color: 'var(--text-secondary)' }}>Inflows</span>
                  <span>${cash.inflows}</span>
                </div>
                <div className="flex justify-between">
                  <span style={{ color: 'var(--text-secondary)' }}>Outflows</span>
                  <span>−${cash.outflows}</span>
                </div>
                <div className="flex justify-between font-medium">
                  <span>Net cash flow</span>
                  <span>${cash.net_cash_flow}</span>
                </div>
              </div>
            </div>

            <div className="card p-5">
              <h2 className="font-medium mb-3">Expenses by category</h2>
              {pnl.expenses_by_category.length === 0 ? (
                <p className="text-sm" style={{ color: 'var(--muted)' }}>
                  No expenses recorded in this period.
                </p>
              ) : (
                <BarList
                  max={Math.max(...pnl.expenses_by_category.map((e) => Number(e.amount)))}
                  items={pnl.expenses_by_category.map((e) => ({
                    label: e.category, value: e.amount }))}
                />
              )}
            </div>

            <div className="card p-5">
              <h2 className="font-medium mb-3">Alerts & anomalies</h2>
              {anomalies.length === 0 ? (
                <p className="text-sm" style={{ color: 'var(--muted)' }}>
                  ✓ No unusual patterns detected.
                </p>
              ) : (
                <ul className="flex flex-col gap-2">
                  {anomalies.slice(0, 8).map((a, i) => (
                    <li key={i} className="text-sm flex gap-2 items-start">
                      <span aria-hidden>
                        {a.severity === 'high' ? '⛔' : a.severity === 'medium' ? '⚠️' : 'ℹ️'}
                      </span>
                      <span>
                        <span className="font-medium">{a.type.replace(/_/g, ' ')}</span>
                        {' — '}
                        <span style={{ color: 'var(--text-secondary)' }}>{a.detail}</span>
                      </span>
                    </li>
                  ))}
                </ul>
              )}
            </div>
          </div>
        </>
      )}
    </div>
  )
}
