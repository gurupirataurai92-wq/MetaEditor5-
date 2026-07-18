import { useEffect, useState } from 'react'
import {
  Area, CartesianGrid, ComposedChart, Line,
  ResponsiveContainer, Tooltip, XAxis, YAxis,
} from 'recharts'
import { Anomaly, api, Forecast, Pnl, SalesSummary } from '../api'

function StatTile({ label, value, delta }: { label: string; value: string; delta?: string }) {
  return (
    <div className="card p-5">
      <div className="text-sm" style={{ color: 'var(--text-secondary)' }}>{label}</div>
      <div className="text-3xl font-semibold mt-1">{value}</div>
      {delta && (
        <div className="text-sm mt-1" style={{ color: 'var(--delta-good)' }}>{delta}</div>
      )}
    </div>
  )
}

export default function Dashboard() {
  const [pnl, setPnl] = useState<Pnl | null>(null)
  const [summary, setSummary] = useState<SalesSummary | null>(null)
  const [forecast, setForecast] = useState<Forecast | null>(null)
  const [anomalies, setAnomalies] = useState<Anomaly[]>([])
  const [error, setError] = useState('')

  useEffect(() => {
    Promise.all([
      api.get<Pnl>('/reports/pnl'),
      api.get<SalesSummary>('/reports/sales-summary'),
      api.get<Forecast>('/analytics/forecast?days_ahead=7&window=30'),
      api.get<Anomaly[]>('/analytics/anomalies'),
    ])
      .then(([p, s, f, a]) => { setPnl(p); setSummary(s); setForecast(f); setAnomalies(a) })
      .catch((e) => setError((e as Error).message))
  }, [])

  if (error) return <p style={{ color: 'var(--status-critical)' }}>{error}</p>
  if (!pnl || !summary || !forecast) {
    return <p style={{ color: 'var(--muted)' }}>Loading dashboard…</p>
  }

  // One continuous series: history then forecast. The confidence band is a
  // stacked pair: an invisible base up to `low`, then the `high - low` delta.
  const chartData = [
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

  const axisStyle = { fontSize: 11, fill: 'var(--muted)' }

  return (
    <div className="flex flex-col gap-4 max-w-6xl">
      <h1 className="text-2xl font-semibold">Business overview</h1>

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <StatTile label="Net revenue (month)" value={`$${pnl.revenue_net}`} />
        <StatTile label="Net profit (month)" value={`$${pnl.net_profit}`} />
        <StatTile label="Sales" value={String(summary.sales_count)} />
        <StatTile label="VAT collected" value={`$${pnl.vat_collected}`} />
      </div>

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
                    legendType="none" tooltipType="none" />
              <Area dataKey="bandDelta" stackId="band" stroke="none"
                    fill="var(--series-1-soft)" fillOpacity={0.35}
                    activeDot={false} connectNulls={false} legendType="none" />
              <Line dataKey="actual" stroke="var(--series-1)" strokeWidth={2}
                    dot={false} connectNulls={false} />
              <Line dataKey="predicted" stroke="var(--series-1)" strokeWidth={2}
                    strokeDasharray="5 4" dot={false} connectNulls={false} />
            </ComposedChart>
          </ResponsiveContainer>
        </div>
      </div>

      <div className="grid lg:grid-cols-2 gap-4">
        <div className="card p-5">
          <h2 className="font-medium mb-3">Top products (month)</h2>
          {summary.top_products.length === 0 && (
            <p className="text-sm" style={{ color: 'var(--muted)' }}>No sales yet.</p>
          )}
          <div className="flex flex-col gap-2">
            {summary.top_products.map((p) => {
              const max = Number(summary.top_products[0].revenue) || 1
              return (
                <div key={p.name} className="text-sm">
                  <div className="flex justify-between mb-0.5">
                    <span>{p.name}</span>
                    <span style={{ color: 'var(--text-secondary)' }}>
                      ${p.revenue} · {p.qty} sold
                    </span>
                  </div>
                  <div className="h-2 rounded" style={{ background: 'var(--grid)' }}>
                    <div className="h-2 rounded" style={{
                      width: `${(Number(p.revenue) / max) * 100}%`,
                      background: 'var(--series-1)',
                    }} />
                  </div>
                </div>
              )
            })}
          </div>
        </div>

        <div className="card p-5">
          <h2 className="font-medium mb-3">Alerts & anomalies</h2>
          {anomalies.length === 0 && (
            <p className="text-sm" style={{ color: 'var(--muted)' }}>
              ✓ No unusual patterns detected.
            </p>
          )}
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
        </div>
      </div>
    </div>
  )
}
