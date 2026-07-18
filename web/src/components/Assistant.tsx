import { FormEvent, useState } from 'react'
import { api } from '../api'

interface Turn {
  role: 'user' | 'assistant'
  text: string
}

const SUGGESTIONS = [
  'How is my profit this month?',
  'What should I reorder?',
  'What are my top products?',
  'Forecast my revenue for next week',
  'Any suspicious activity?',
]

export default function Assistant() {
  const [turns, setTurns] = useState<Turn[]>([])
  const [question, setQuestion] = useState('')
  const [busy, setBusy] = useState(false)

  async function ask(q: string) {
    if (!q.trim() || busy) return
    setTurns((t) => [...t, { role: 'user', text: q }])
    setQuestion('')
    setBusy(true)
    try {
      const resp = await api.post<{ answer: string }>('/assistant/ask', { question: q })
      setTurns((t) => [...t, { role: 'assistant', text: resp.answer }])
    } catch (e) {
      setTurns((t) => [...t, { role: 'assistant', text: `Error: ${(e as Error).message}` }])
    } finally {
      setBusy(false)
    }
  }

  function submit(e: FormEvent) {
    e.preventDefault()
    ask(question)
  }

  return (
    <div className="max-w-2xl flex flex-col gap-4 h-[calc(100vh-3rem)]">
      <div>
        <h1 className="text-2xl font-semibold">AI Business Assistant</h1>
        <p className="text-sm mt-1" style={{ color: 'var(--text-secondary)' }}>
          Answers are grounded in your own sales, stock and finance records.
        </p>
      </div>

      <div className="card flex-1 p-5 overflow-y-auto flex flex-col gap-3">
        {turns.length === 0 && (
          <div className="flex flex-wrap gap-2">
            {SUGGESTIONS.map((s) => (
              <button key={s} onClick={() => ask(s)}
                      className="px-3 py-1.5 rounded-full border border-black/15 dark:border-white/15 text-sm hover:bg-black/5 dark:hover:bg-white/5">
                {s}
              </button>
            ))}
          </div>
        )}
        {turns.map((t, i) => (
          <div key={i}
               className={`max-w-[85%] px-4 py-2.5 rounded-2xl text-sm leading-relaxed ${
                 t.role === 'user'
                   ? 'self-end bg-brand dark:bg-brand-dark text-white'
                   : 'self-start border border-black/10 dark:border-white/10'
               }`}>
            {t.text}
          </div>
        ))}
        {busy && <p className="text-sm" style={{ color: 'var(--muted)' }}>Thinking…</p>}
      </div>

      <form onSubmit={submit} className="flex gap-2">
        <input
          className="flex-1 px-4 py-2.5 rounded-xl border border-black/15 dark:border-white/15 bg-transparent outline-none focus:border-brand dark:focus:border-brand-dark"
          placeholder="Ask about profit, stock, forecasts…"
          value={question}
          onChange={(e) => setQuestion(e.target.value)}
        />
        <button disabled={busy}
                className="px-5 rounded-xl bg-brand dark:bg-brand-dark text-white font-medium disabled:opacity-50">
          Ask
        </button>
      </form>
    </div>
  )
}
