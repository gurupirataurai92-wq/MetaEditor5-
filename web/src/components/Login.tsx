import { FormEvent, useState } from 'react'
import { api, setToken } from '../api'
import { LogoMark } from './Logo'

interface TokenPair {
  access_token: string
}

const FEATURES = [
  ['🛒', 'Offline-first POS', 'Sell even when the network is down — everything syncs later.'],
  ['💱', 'ZiG & USD together', 'Every sale keeps its exchange rate, so history stays true.'],
  ['✨', 'AI that knows your shop', 'Forecasts, reorder alerts and advice from your own numbers.'],
] as const

export default function Login({ onLogin }: { onLogin: () => void }) {
  const [mode, setMode] = useState<'login' | 'register'>('login')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [business, setBusiness] = useState('')
  const [fullName, setFullName] = useState('')
  const [totp, setTotp] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  async function submit(e: FormEvent) {
    e.preventDefault()
    setBusy(true)
    setError('')
    try {
      const tokens =
        mode === 'login'
          ? await api.post<TokenPair>('/auth/login', {
              email, password, ...(totp ? { totp_code: totp } : {}) })
          : await api.post<TokenPair>('/auth/register-business', {
              business_name: business, full_name: fullName, email, password })
      setToken(tokens.access_token)
      onLogin()
    } catch (err) {
      setError((err as Error).message)
    } finally {
      setBusy(false)
    }
  }

  const input =
    'w-full px-3.5 py-2.5 rounded-lg border border-black/15 dark:border-white/15 ' +
    'bg-transparent outline-none focus:border-brand dark:focus:border-brand-dark ' +
    'transition-colors'

  return (
    <div className="min-h-screen flex">
      {/* Brand panel */}
      <div className="hidden lg:flex flex-col justify-between w-[44%] p-12 text-white"
           style={{ background: 'linear-gradient(135deg, #1c5cab 0%, #2a78d6 55%, #1baf7a 130%)' }}>
        <div className="flex items-center gap-3">
          <LogoMark size={44} />
          <div>
            <div className="text-xl font-semibold tracking-tight">SIMS AI</div>
            <div className="text-sm text-white/70">Smart Informal Business Management</div>
          </div>
        </div>
        <div className="flex flex-col gap-7 max-w-md">
          <h1 className="text-3xl font-semibold leading-snug">
            Run your business like the big ones do.
          </h1>
          {FEATURES.map(([icon, title, body]) => (
            <div key={title} className="flex gap-3.5">
              <div className="text-2xl">{icon}</div>
              <div>
                <div className="font-medium">{title}</div>
                <div className="text-sm text-white/75">{body}</div>
              </div>
            </div>
          ))}
        </div>
        <div className="text-xs text-white/60">
          Built for Zimbabwe · EcoCash · ZIPIT · PayNow · ZIMRA-ready VAT
        </div>
      </div>

      {/* Form panel */}
      <div className="flex-1 grid place-items-center p-6">
        <form onSubmit={submit} className="w-full max-w-sm flex flex-col gap-3 fade-in">
          <div className="lg:hidden flex justify-center mb-2"><LogoMark size={52} /></div>
          <h2 className="text-2xl font-semibold">
            {mode === 'login' ? 'Welcome back' : 'Set up your business'}
          </h2>
          <p className="text-sm -mt-2 mb-1" style={{ color: 'var(--text-secondary)' }}>
            {mode === 'login'
              ? 'Sign in to your dashboard.'
              : 'Free to start — takes less than a minute.'}
          </p>
          {mode === 'register' && (
            <>
              <input className={input} placeholder="Business name" value={business}
                     onChange={(e) => setBusiness(e.target.value)} required />
              <input className={input} placeholder="Your full name" value={fullName}
                     onChange={(e) => setFullName(e.target.value)} required />
            </>
          )}
          <input className={input} type="email" placeholder="Email" value={email}
                 onChange={(e) => setEmail(e.target.value)} required />
          <input className={input} type="password" placeholder="Password" value={password}
                 onChange={(e) => setPassword(e.target.value)} required minLength={8} />
          {mode === 'login' && (
            <input className={input} placeholder="2FA code (if enabled)" value={totp}
                   onChange={(e) => setTotp(e.target.value)} />
          )}
          {error && (
            <p className="text-sm" style={{ color: 'var(--status-critical)' }}>{error}</p>
          )}
          <button disabled={busy}
            className="mt-1 py-2.5 rounded-lg bg-brand dark:bg-brand-dark text-white font-medium disabled:opacity-50 hover:opacity-90 transition-opacity">
            {busy ? 'Please wait…' : mode === 'login' ? 'Sign in' : 'Create business'}
          </button>
          <button type="button" className="text-sm underline underline-offset-2"
                  style={{ color: 'var(--text-secondary)' }}
                  onClick={() => setMode(mode === 'login' ? 'register' : 'login')}>
            {mode === 'login' ? 'New here? Register your business' : 'Already registered? Sign in'}
          </button>
        </form>
      </div>
    </div>
  )
}
