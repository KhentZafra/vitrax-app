// Small inline icons. Kept as components so they inherit size from CSS.

export const WarnIcon = (props) => (
  <svg viewBox="0 0 30 30" aria-hidden="true" {...props}>
    <path d="M15 4l12 21H3z" fill="#FFB020" />
    <path d="M15 12v6" stroke="#050A16" strokeWidth="2.4" strokeLinecap="round" />
    <circle cx="15" cy="21.5" r="1.4" fill="#050A16" />
  </svg>
)

export const OkIcon = (props) => (
  <svg viewBox="0 0 30 30" aria-hidden="true" {...props}>
    <circle cx="15" cy="15" r="12" fill="#3DDC97" />
    <path d="M9.5 15.5l3.6 3.5 7-7.5" fill="none" stroke="#050A16" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round" />
  </svg>
)

export const DownloadIcon = (props) => (
  <span className="dl-ico">
    <svg viewBox="0 0 18 18" aria-hidden="true" {...props}>
      <path d="M9 2v10m0 0l-4-4m4 4l4-4M3 15h12" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  </span>
)

export const TickIcon = (props) => (
  <svg viewBox="0 0 12 12" aria-hidden="true" {...props}>
    <path d="M2.5 6.3l2.3 2.3 4.7-5" fill="none" stroke="#3DDC97" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
  </svg>
)

export const ChevronIcon = (props) => (
  <svg viewBox="0 0 22 22" aria-hidden="true" {...props}>
    <path d="M8 5l6 6-6 6" fill="none" stroke="#fff" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" />
  </svg>
)

export const CheckIcon = (props) => (
  <svg viewBox="0 0 22 22" aria-hidden="true" {...props}>
    <path d="M5 11.5l4 4 8-9" fill="none" stroke="#fff" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" />
  </svg>
)
