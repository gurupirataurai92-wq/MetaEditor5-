import { useEffect, useRef, useState } from 'react'

// Camera barcode reader. Uses the browser's native BarcodeDetector where
// available (Chrome / Android / Chromium) to read a code from the live camera;
// everywhere else it falls back to manual entry, which is always offered so a
// USB/Bluetooth hardware scanner (which types the code) or hand entry works too.
//
// Requires a secure context (HTTPS or localhost) for camera access.
const FORMATS = ['ean_13', 'ean_8', 'upc_a', 'upc_e', 'code_128', 'code_39', 'qr_code']

export default function BarcodeScanner({
  onDetect, onClose, title = 'Scan barcode',
}: {
  onDetect: (code: string) => void
  onClose: () => void
  title?: string
}) {
  const videoRef = useRef<HTMLVideoElement | null>(null)
  const [manual, setManual] = useState('')
  const [status, setStatus] = useState<'starting' | 'scanning' | 'unsupported' | 'error'>('starting')
  const [errorMsg, setErrorMsg] = useState('')

  useEffect(() => {
    let stream: MediaStream | null = null
    let raf = 0
    let stopped = false
    const Detector = (window as unknown as { BarcodeDetector?: any }).BarcodeDetector

    async function start() {
      if (!Detector || !navigator.mediaDevices?.getUserMedia) {
        setStatus('unsupported')
        return
      }
      try {
        const detector = new Detector({ formats: FORMATS })
        stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: 'environment' },
        })
        if (stopped) return
        if (videoRef.current) {
          videoRef.current.srcObject = stream
          await videoRef.current.play()
        }
        setStatus('scanning')
        const tick = async () => {
          if (stopped || !videoRef.current) return
          try {
            const codes = await detector.detect(videoRef.current)
            if (codes.length > 0 && codes[0].rawValue) {
              finish(codes[0].rawValue)
              return
            }
          } catch {
            /* transient detect errors are ignored between frames */
          }
          raf = requestAnimationFrame(tick)
        }
        raf = requestAnimationFrame(tick)
      } catch (e) {
        setErrorMsg((e as Error).message || 'Could not access the camera')
        setStatus('error')
      }
    }

    function finish(code: string) {
      stopped = true
      cancelAnimationFrame(raf)
      stream?.getTracks().forEach((t) => t.stop())
      onDetect(code.trim())
    }

    start()
    return () => {
      stopped = true
      cancelAnimationFrame(raf)
      stream?.getTracks().forEach((t) => t.stop())
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return (
    <div className="fixed inset-0 z-50 grid place-items-center p-4"
         style={{ background: 'rgba(0,0,0,0.6)' }} onClick={onClose}>
      <div className="card p-5 w-full max-w-sm fade-in" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between mb-3">
          <h3 className="font-medium">📷 {title}</h3>
          <button onClick={onClose} className="text-sm" style={{ color: 'var(--muted)' }}>✕</button>
        </div>

        {(status === 'starting' || status === 'scanning') && (
          <div className="relative rounded-lg overflow-hidden"
               style={{ background: '#000', aspectRatio: '4 / 3' }}>
            <video ref={videoRef} className="w-full h-full object-cover" muted playsInline />
            {/* scanning reticle */}
            <div className="absolute inset-0 grid place-items-center pointer-events-none">
              <div className="w-3/4 h-1/3 rounded-lg"
                   style={{ border: '2px solid rgba(255,255,255,0.9)', boxShadow: '0 0 0 9999px rgba(0,0,0,0.25)' }} />
            </div>
            <div className="absolute bottom-2 inset-x-0 text-center text-xs text-white/90">
              {status === 'scanning' ? 'Point the camera at a barcode' : 'Starting camera…'}
            </div>
          </div>
        )}

        {status === 'unsupported' && (
          <p className="text-sm mb-2" style={{ color: 'var(--text-secondary)' }}>
            Live camera scanning isn't available in this browser. Use a
            USB/Bluetooth scanner (it types the code) or enter it below.
          </p>
        )}
        {status === 'error' && (
          <p className="text-sm mb-2" style={{ color: 'var(--status-critical)' }}>
            {errorMsg}. You can still enter the code manually below.
          </p>
        )}

        <div className="mt-3">
          <label className="text-sm">Or enter the code
            <div className="flex gap-2 mt-1">
              <input autoFocus value={manual} onChange={(e) => setManual(e.target.value)}
                     onKeyDown={(e) => { if (e.key === 'Enter' && manual.trim()) onDetect(manual.trim()) }}
                     placeholder="type or scan into this box"
                     className="flex-1 px-3 py-2 rounded-lg border border-black/15 dark:border-white/15 bg-transparent outline-none" />
              <button onClick={() => manual.trim() && onDetect(manual.trim())}
                      disabled={!manual.trim()}
                      className="px-4 rounded-lg bg-brand dark:bg-brand-dark text-white text-sm font-medium disabled:opacity-40">
                Use
              </button>
            </div>
          </label>
        </div>
      </div>
    </div>
  )
}
