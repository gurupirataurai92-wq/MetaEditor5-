import { FormEvent, useState } from 'react'
import { api, setToken } from '../api'

interface TokenPair {
  access_token: string
}

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
    'w-full px-3 py-2 rounded-lg border border-black/15 dark:border-white/15 ' +
    'bg-transparent outline-none focus:border-brand dark:focus:border-brand-dark'

  return (
    <div className="min-h-screen grid place-items-center p-4">
      <form onSubmit={submit} className="card w-full max-w-sm p-8 flex flex-col gap-3">
        <div className="text-center mb-2">
          <div className="w-12 h-12 mx-auto rounded-xl bg-brand dark:bg-brand-dark text-white grid place-items-center text-xl font-bold mb-2">S</div>
          <h1 className="text-xl font-semibold">SIMS AI</h1>
          <p className="text-sm" style={{ color: 'var(--text-secondary)' }}>
            Smart Informal Business Management
          </p>
        </div>
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
        {error && <p className="text-sm" style={{ color: 'var(--status-critical)' }}>{error}</p>}
        <button disabled={busy}
          className="mt-1 py-2 rounded-lg bg-brand dark:bg-brand-dark text-white font-medium disabled:opacity-50">
          {busy ? 'Please wait…' : mode === 'login' ? 'Sign in' : 'Create business'}
        </button>
        <button type="button" className="text-sm underline"
                style={{ color: 'var(--text-secondary)' }}
                onClick={() => setMode(mode === 'login' ? 'register' : 'login')}>
          {mode === 'login' ? 'New here? Register your business' : 'Already registered? Sign in'}
        </button>
      </form>
    </div>
  )
}
