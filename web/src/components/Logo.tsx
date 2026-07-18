/** SIMS AI brand mark: ascending bars (growth) + a spark (the AI insight). */
export function LogoMark({ size = 36 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 64 64" aria-hidden>
      <defs>
        <linearGradient id="sims-g" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#2a78d6" />
          <stop offset="1" stopColor="#1baf7a" />
        </linearGradient>
      </defs>
      <rect width="64" height="64" rx="14" fill="url(#sims-g)" />
      <g fill="#fff">
        <rect x="14" y="34" width="8" height="16" rx="2" />
        <rect x="28" y="26" width="8" height="24" rx="2" />
        <rect x="42" y="16" width="8" height="34" rx="2" />
        <circle cx="46" cy="10" r="4" fill="#ffd75e" />
      </g>
    </svg>
  )
}

export function LogoWordmark({ size = 36 }: { size?: number }) {
  return (
    <div className="flex items-center gap-2.5">
      <LogoMark size={size} />
      <div>
        <div className="font-semibold leading-tight tracking-tight">SIMS AI</div>
        <div className="text-xs" style={{ color: 'var(--muted)' }}>
          Business Ecosystem
        </div>
      </div>
    </div>
  )
}
