/** Tiny toast bus: `toast('Saved')` from anywhere; <Toasts/> renders them. */
export interface ToastMsg {
  id: number
  text: string
  kind: 'success' | 'error'
}

type Listener = (msg: ToastMsg) => void
const listeners = new Set<Listener>()
let nextId = 1

export function toast(text: string, kind: ToastMsg['kind'] = 'success') {
  const msg = { id: nextId++, text, kind }
  listeners.forEach((fn) => fn(msg))
}

export function onToast(fn: Listener): () => void {
  listeners.add(fn)
  return () => listeners.delete(fn)
}
