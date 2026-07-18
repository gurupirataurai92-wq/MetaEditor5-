const BASE = '/api/v1'

let accessToken: string | null = localStorage.getItem('sims_token')

export function setToken(token: string | null) {
  accessToken = token
  if (token) localStorage.setItem('sims_token', token)
  else localStorage.removeItem('sims_token')
}

export function hasToken(): boolean {
  return accessToken !== null
}

async function request<T>(method: string, path: string, body?: unknown): Promise<T> {
  const resp = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  })
  if (resp.status === 401) {
    setToken(null)
    window.location.reload()
  }
  if (!resp.ok) {
    const detail = await resp.json().catch(() => ({ detail: resp.statusText }))
    throw new Error(typeof detail.detail === 'string' ? detail.detail : resp.statusText)
  }
  return resp.json()
}

export const api = {
  get: <T>(path: string) => request<T>('GET', path),
  post: <T>(path: string, body: unknown) => request<T>('POST', path, body),
}

// ---- shared response shapes -------------------------------------------------
export interface Product {
  id: string
  name: string
  sku: string
  barcode: string | null
  sell_price: string
  currency: string
}

export interface StockLevel {
  product_id: string
  name: string
  on_hand: number
  reorder_level: number
  below_reorder: boolean
}

export interface Pnl {
  revenue_net: string
  gross_profit: string
  net_profit: string
  expenses: string
  vat_collected: string
}

export interface SalesSummary {
  revenue: string
  sales_count: number
  by_day: { date: string; revenue: string }[]
  top_products: { name: string; qty: number; revenue: string }[]
}

export interface Forecast {
  history: { date: string; revenue: number; qty: number }[]
  forecast: { date: string; value: number; low: number; high: number }[]
}

export interface Anomaly {
  type: string
  severity: string
  detail: string
}
