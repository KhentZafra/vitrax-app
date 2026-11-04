import { useEffect, useState } from 'react'
import { animate, motion, useMotionValue, useTransform } from 'framer-motion'
import { TickIcon, WarnIcon } from './Icons.jsx'

// One component per feature. Content on these screens is example data.
// Each mounts fresh when its step becomes active, so its entrance animation replays.

function Offline() {
  return (
    <>
      <h4>Recording</h4>
      <div className="card no-signal">
        <svg viewBox="0 0 64 64" aria-hidden="true">
          <path d="M14 48v-6M26 48V34M38 48V26M50 48V16" stroke="#2a3a5c" strokeWidth="5" strokeLinecap="round" />
          <path d="M10 12l44 40" stroke="#FFB020" strokeWidth="4" strokeLinecap="round" className="draw-line" />
        </svg>
        <b>No mobile signal</b>
        <small>GPS is still tracking. Points are saved on this phone.</small>
      </div>
      <div className="card stack">
        <div className="row"><span>GPS points saved</span><Counter to={3412} className="mono" /></div>
        <div className="row"><span>Accuracy</span><b className="mono">± 4 m</b></div>
        <div className="bar" style={{ '--w': '34%' }}><i /></div>
        <div className="row"><span>Offline storage used</span><b className="mono">2.1 MB</b></div>
      </div>
      <div className="app-btn"><i className="rec-dot" />18.2 KM · 51:07</div>
    </>
  )
}

const HAZARD_TYPES = ['Pothole', 'Flood', 'Stray dog', 'Traffic']

function Report() {
  const [sel, setSel] = useState(0)
  useEffect(() => {
    const t = setInterval(() => setSel((s) => (s + 1) % HAZARD_TYPES.length), 1400)
    return () => clearInterval(t)
  }, [])
  return (
    <>
      <h4>What's on the road?</h4>
      <div className="chips">
        {HAZARD_TYPES.map((t, i) => (
          <div key={t} className={`chip ${i === sel ? 'is-sel' : ''}`}>
            {i === sel && <motion.span layoutId="chip-ring" className="chip__ring" transition={{ type: 'spring', stiffness: 380, damping: 30 }} />}
            <WarnIcon />{t}
          </div>
        ))}
      </div>
      <div className="card stack">
        <div className="row"><span>Location</span><b className="mono">9.583° N, 123.754° E</b></div>
        <div className="row"><span>Road</span><b>Dauis–Panglao Rd</b></div>
      </div>
      <div className="app-btn app-btn--amber">REPORT {HAZARD_TYPES[sel].toUpperCase()}</div>
    </>
  )
}

function Alert() {
  const metres = useMotionValue(300)
  const label = useTransform(metres, (m) => (m < 5 ? 'Now' : String(Math.round(m / 10) * 10)))
  const offset = useTransform(metres, [300, 0], [0, 377])
  useEffect(() => {
    const controls = animate(metres, 0, { duration: 4.2, ease: 'linear' })
    return () => controls.stop()
  }, [metres])
  return (
    <>
      <h4>"Flood ahead, 300 metres"</h4>
      <div className="ring">
        <svg viewBox="0 0 140 140" aria-hidden="true">
          <circle cx="70" cy="70" r="60" fill="none" stroke="#13203a" strokeWidth="8" />
          <motion.circle cx="70" cy="70" r="60" fill="none" stroke="#FFB020" strokeWidth="8" strokeLinecap="round" strokeDasharray="377" style={{ strokeDashoffset: offset }} />
        </svg>
        <div className="ring__v"><motion.b className="mono">{label}</motion.b><small>metres</small></div>
        <span className="ring__wave" /><span className="ring__wave ring__wave--2" />
      </div>
      <div className="hazard">
        <WarnIcon />
        <div><b>Flood · Loboc River Rd</b><small>Confirmed by 5 riders · 40 min ago</small></div>
      </div>
      <div className="card row"><span>Alert</span><b>Voice + vibration</b></div>
    </>
  )
}

function Sync() {
  const items = [
    ['Activity uploaded', 'Tagbilaran → Loboc · 24.6 km · 1:18:40'],
    ['2 hazards you reported', 'Pothole, stray dog'],
    ['11 new hazards near you', 'Updated from other riders'],
    ['Data used', '184 KB'],
  ]
  return (
    <>
      <h4>Back online</h4>
      <div className="sync">
        {items.map(([t, s], i) => (
          <motion.div key={t} className="card sync__item"
            initial={{ opacity: 0, x: 14 }} animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.15 + i * 0.15, duration: 0.45, ease: [0.2, 0.7, 0.2, 1] }}>
            <span className="sync__chk"><TickIcon /></span>
            <div><b>{t}</b><small>{s}</small></div>
          </motion.div>
        ))}
      </div>
      <div className="app-btn app-btn--quiet" style={{ color: 'var(--go)' }}>ALL SYNCED</div>
    </>
  )
}

const BADGES = [['Bronze', '#CD7F32'], ['Silver', '#B0B4BB'], ['Gold', '#FFC94A', 'new'], ['Platinum', '#4FC3E8', 'lock'], ['Diamond', '#A77BFF', 'lock'], ['Elite', '#E91E8C', 'lock']]

function Challenges() {
  return (
    <>
      <h4>Panglao Loop</h4>
      <div className="card stack">
        <div className="row"><span>Your distance</span><b className="mono">86 / 120 km</b></div>
        <div className="bar" style={{ '--w': '72%' }}><i /></div>
        <div className="row"><span>November challenge · ends in</span><b className="mono">26 days</b></div>
      </div>
      <div className="podium">
        {[['@aaron.rides', 2, 64], ['@loboc_runner', 1, 86], ['You', 3, 46]].map(([who, rank, h], i) => (
          <div key={who} className={`podium__col ${who === 'You' ? 'is-you' : ''}`}>
            <small>{who}</small>
            <motion.span initial={{ height: 0 }} animate={{ height: h }}
              transition={{ type: 'spring', stiffness: 160, damping: 18, delay: 0.15 + i * 0.12 }}>{rank}</motion.span>
          </div>
        ))}
      </div>
      <div className="badges">
        {BADGES.map(([n, c, state]) => (
          <span key={n} className={state ? `is-${state}` : ''} style={{ '--c': c }}>{n}</span>
        ))}
      </div>
      <div className="app-btn">JOIN CHALLENGE</div>
    </>
  )
}

function Community() {
  const msgs = [['Anyone riding to Anda on Sunday?'], ["I'm in. Meet at Tagbilaran port, 5:30", 'me'], ['Same. Bringing a spare tube']]
  return (
    <>
      <h4>Feed</h4>
      <div className="card post">
        <div className="row"><b>@trisha.c</b><span>2 h ago</span></div>
        <small className="post__meta">Morning ride · Tagbilaran → Baclayon</small>
        <svg viewBox="0 0 240 50" aria-hidden="true">
          <motion.path d="M8 40 C50 10 90 44 130 24 S200 12 232 18" fill="none" stroke="#2B8CFF" strokeWidth="3" strokeLinecap="round"
            initial={{ pathLength: 0 }} animate={{ pathLength: 1 }} transition={{ duration: 1.3, ease: [0.2, 0.7, 0.2, 1], delay: 0.2 }} />
        </svg>
        <div className="row"><span className="mono">18.4 km · 52:10</span><Like /></div>
      </div>
      <div className="chat">
        {msgs.map(([t, who], i) => (
          <motion.span key={t} className={who === 'me' ? 'is-me' : ''}
            initial={{ opacity: 0, y: 8, scale: 0.96 }} animate={{ opacity: 1, y: 0, scale: 1 }}
            transition={{ delay: 0.6 + i * 0.6, duration: 0.35 }}>{t}</motion.span>
        ))}
      </div>
      <div className="app-btn app-btn--quiet">MESSAGE</div>
    </>
  )
}

function Like() {
  const [liked, setLiked] = useState(false)
  useEffect(() => { const t = setTimeout(() => setLiked(true), 1300); return () => clearTimeout(t) }, [])
  return (
    <b className={`like ${liked ? 'is-liked' : ''}`}>
      <motion.svg viewBox="0 0 16 16" aria-hidden="true" animate={liked ? { scale: [1, 1.35, 1] } : {}} transition={{ duration: 0.4 }}>
        <path d="M8 14S2 10 2 5.8A3 3 0 018 4a3 3 0 016 1.8C14 10 8 14 8 14z" />
      </motion.svg>
      <span className="mono">{liked ? 25 : 24}</span>
    </b>
  )
}

function Privacy() {
  const [on, setOn] = useState(false)
  useEffect(() => { const t = setTimeout(() => setOn(true), 500); return () => clearTimeout(t) }, [])
  const route = 'M30 150 C70 100 100 140 140 90 S210 50 244 34'
  return (
    <>
      <h4>Privacy</h4>
      <div className="map" style={{ height: 180 }}>
        <svg viewBox="0 0 272 180" preserveAspectRatio="none" aria-hidden="true">
          <rect width="272" height="180" fill="url(#grid)" />
          <path d={route} fill="none" stroke="#1b2c4d" strokeWidth="4" strokeLinecap="round" strokeDasharray="3 6" />
          <motion.path d={route} fill="none" stroke="#2B8CFF" strokeWidth="4" strokeLinecap="round"
            initial={false} animate={{ pathLength: on ? 0.78 : 1, pathOffset: on ? 0.11 : 0 }}
            transition={{ duration: 0.7, ease: [0.2, 0.7, 0.2, 1] }} />
          {[[30, 150], [244, 34]].map(([cx, cy]) => (
            <motion.circle key={cx} cx={cx} cy={cy} r="26" className="zone"
              initial={{ scale: 0 }} animate={{ scale: on ? 1 : 0 }}
              transition={{ type: 'spring', stiffness: 200, damping: 16 }} />
          ))}
        </svg>
        <span className="map__lbl" style={{ left: 10, top: 8 }}>START HIDDEN</span>
        <span className="map__lbl" style={{ right: 10, bottom: 8 }}>END HIDDEN</span>
      </div>
      <div className="card stack">
        <div className="row"><span>Hide start and end of routes</span><span className={`toggle ${on ? 'is-on' : ''}`}><i /></span></div>
        <div className="row"><span>Hidden distance</span><b className="mono">200 m</b></div>
      </div>
      <div className="app-btn app-btn--danger">DELETE ACCOUNT &amp; DATA</div>
    </>
  )
}

/** Counts up from 0 when it mounts. */
function Counter({ to, className }) {
  const v = useMotionValue(0)
  const text = useTransform(v, (n) => Math.round(n).toLocaleString('en-US'))
  useEffect(() => { const c = animate(v, to, { duration: 1.4, ease: [0.2, 0.7, 0.2, 1] }); return () => c.stop() }, [v, to])
  return <motion.b className={className}>{text}</motion.b>
}

export const SCREENS = {
  offline: Offline,
  report: Report,
  alert: Alert,
  sync: Sync,
  challenges: Challenges,
  community: Community,
  privacy: Privacy,
}
