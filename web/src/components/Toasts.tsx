import { useEffect, useState } from 'react'
import { onToast, ToastMsg } from '../toast'

export default function Toasts() {
  const [toasts, setToasts] = useState<ToastMsg[]>([])

  useEffect(() =>
    onToast((msg) => {
      setToasts((t) => [...t, msg])
      setTimeout(() => setToasts((t) => t.filter((x) => x.id !== msg.id)), 3200)
    }), [])

  return (
    <div className="fixed bottom-5 right-5 z-50 flex flex-col gap-2 items-end">
      {toasts.map((t) => (
        <div key={t.id}
             className="card px-4 py-2.5 text-sm shadow-lg fade-in flex items-center gap-2">
          <span>{t.kind === 'success' ? '✓' : '⚠'}</span>
          <span>{t.text}</span>
        </div>
      ))}
    </div>
  )
}
