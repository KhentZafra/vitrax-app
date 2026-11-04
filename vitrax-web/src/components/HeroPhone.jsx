import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import {
  AnimatePresence, motion, useAnimationFrame, useInView,
  useMotionValue, useMotionValueEvent, useReducedMotion, useTransform,
} from 'framer-motion'
import { AppIcon } from './Logo.jsx'
import { OkIcon, WarnIcon } from './Icons.jsx'

const ROUTE = 'M16 172 C46 150 62 126 92 120 S132 124 152 104 S176 58 202 50 S240 34 258 24'
const RIDE = { km: 14.8, seconds: 44 * 60 + 10, duration: 15000, hold: 1800 }
const POTHOLE_AT = 0.64 // position of the pothole along the route (0–1)
const WARN_RANGE = 0.2  // start warning this far before the pothole

const pad = (n) => String(n).padStart(2, '0')

/** Decide what the screen shows for a given ride progress. Pure, so easy to test. */
export function ridePhase(p) {
  const signal = p < 0.28 ? 'ready' : p < 0.88 ? 'offline' : 'online'
  const toPothole = POTHOLE_AT - p
  let hazard = null
  if (toPothole > 0 && toPothole < WARN_RANGE) {
    hazard = { kind: 'warn', metres: Math.max(10, Math.round(((toPothole / WARN_RANGE) * 300) / 10) * 10) }
  } else if (toPothole <= 0 && toPothole > -0.1) {
    hazard = { kind: 'passed' }
  }
  return { signal, hazard }
}

const SIGNAL_TEXT = { ready: 'GPS · Ready', offline: 'No signal · saving', online: 'Online · synced' }

export default function HeroPhone() {
  const reduce = useReducedMotion()
  const rootRef = useRef(null)
  const pathRef = useRef(null)
  const lengthRef = useRef(1)
  const [, setMeasured] = useState(false)
  const inView = useInView(rootRef)
  const [booted, setBooted] = useState(reduce)
  const [phase, setPhase] = useState(ridePhase(0))

  const progress = useMotionValue(reduce ? 0.52 : 0)
  const speed = useMotionValue(0)
  const startRef = useRef(null)

  useLayoutEffect(() => {
    lengthRef.current = pathRef.current.getTotalLength()
    setMeasured(true) // re-render so the pothole marker is placed on the real path
  }, [])

  // Splash screen: the app "opens" with the logo, then switches to recording.
  useEffect(() => {
    if (reduce) return
    const t = setTimeout(() => setBooted(true), 1700)
    return () => clearTimeout(t)
  }, [reduce])

  useAnimationFrame((time) => {
    if (reduce || !booted || !inView) return
    if (startRef.current === null) startRef.current = time
    const elapsed = (time - startRef.current) % (RIDE.duration + RIDE.hold)
    const p = Math.min(elapsed / RIDE.duration, 1)
    progress.set(p)
    speed.set(p === 0 ? 0 : 19.6 + 2.4 * Math.sin(time / 900) + 1.1 * Math.sin(time / 370))
  })

  // Only re-render React when what the screen says actually changes.
  useMotionValueEvent(progress, 'change', (p) => {
    const next = ridePhase(p)
    setPhase((prev) =>
      prev.signal === next.signal &&
      prev.hazard?.kind === next.hazard?.kind &&
      prev.hazard?.metres === next.hazard?.metres ? prev : next)
  })

  const point = (p) => pathRef.current?.getPointAtLength(lengthRef.current * p) ?? { x: 16, y: 172 }
  const riderX = useTransform(progress, (p) => point(p).x)
  const riderY = useTransform(progress, (p) => point(p).y)
  const elevX = useTransform(progress, (p) => 272 * p)
  const km = useTransform(progress, (p) => (RIDE.km * p).toFixed(1))
  const time = useTransform(progress, (p) => {
    const s = Math.round(RIDE.seconds * p)
    return `${pad(Math.floor(s / 60))}:${pad(s % 60)}`
  })
  const kmh = useTransform(speed, (v) => v.toFixed(1))
  const pot = point(POTHOLE_AT)

  return (
    <div className="phone" ref={rootRef} aria-label="VITRAX app recording a ride">
      <div className="phone__screen">
        <div className="phone__island" />

        <AnimatePresence initial={false}>
          {!booted && (
            <motion.div
              key="splash"
              className="splash"
              exit={{ opacity: 0, scale: 1.04 }}
              transition={{ duration: 0.45, ease: [0.2, 0.7, 0.2, 1] }}
            >
              <motion.div initial={{ scale: 0.8, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} transition={{ type: 'spring', stiffness: 220, damping: 18, delay: 0.3 }}>
                <AppIcon size={96} />
              </motion.div>
              <span className="splash__name">VITRAX</span>
              <span className="splash__status mono">Getting GPS fix…</span>
              <span className="splash__bar"><i /></span>
            </motion.div>
          )}
        </AnimatePresence>

        <motion.div
          className="app"
          initial={false}
          animate={{ opacity: booted ? 1 : 0, y: booted ? 0 : 14 }}
          transition={{ duration: 0.5, ease: [0.2, 0.7, 0.2, 1], delay: booted && !reduce ? 0.15 : 0 }}
        >
          <div className="row">
            <span className="phone-brand">VITRAX</span>
            <span className={`signal signal--${phase.signal}`}>
              <span className="signal__bars"><i /><i /><i /></span>
              {SIGNAL_TEXT[phase.signal]}
            </span>
          </div>

          <div className="map">
            <svg viewBox="0 0 272 200" preserveAspectRatio="none" aria-hidden="true">
              <defs>
                <pattern id="grid" width="34" height="34" patternUnits="userSpaceOnUse">
                  <path d="M34 0H0V34" fill="none" stroke="#12203a" strokeWidth="1" />
                </pattern>
              </defs>
              <rect width="272" height="200" fill="url(#grid)" />
              <path d="M0 150 Q60 120 120 160 T272 140" fill="none" stroke="#0f2a4a" strokeWidth="10" />
              <path ref={pathRef} d={ROUTE} fill="none" stroke="#1b2c4d" strokeWidth="4" strokeLinecap="round" />
              <motion.path
                d={ROUTE} fill="none" stroke="#2B8CFF" strokeWidth="4" strokeLinecap="round"
                style={{ pathLength: progress }}
              />
              <g transform={`translate(${pot.x} ${pot.y})`}>
                <circle r="9" fill="rgba(255,176,32,.18)" />
                <circle r="4.5" fill="#FFB020" />
              </g>
              <motion.g style={{ x: riderX, y: riderY }}>
                <circle r="12" fill="rgba(91,193,255,.18)" className="rider-pulse" />
                <circle r="6" fill="#5BC1FF" stroke="#060c19" strokeWidth="2" />
              </motion.g>
            </svg>
            <span className="map__lbl" style={{ left: 10, top: 8 }}>LOBOC</span>
            <span className="map__lbl" style={{ right: 10, bottom: 8 }}>LOAY INTERIOR RD</span>
          </div>

          <div className="hazard-slot">
            <AnimatePresence mode="wait">
              {phase.hazard && (
                <motion.div
                  key={phase.hazard.kind}
                  className={`hazard ${phase.hazard.kind === 'passed' ? 'hazard--ok' : ''}`}
                  initial={{ opacity: 0, y: 10, scale: 0.97 }}
                  animate={{ opacity: 1, y: 0, scale: 1 }}
                  exit={{ opacity: 0, y: -6 }}
                  transition={{ duration: 0.35, ease: [0.2, 0.7, 0.2, 1] }}
                >
                  {phase.hazard.kind === 'warn' ? <WarnIcon /> : <OkIcon />}
                  <div>
                    <b>{phase.hazard.kind === 'warn' ? 'Pothole ahead' : 'Hazard passed'}</b>
                    <small>
                      {phase.hazard.kind === 'warn'
                        ? <><span className="mono">{phase.hazard.metres} m</span> · confirmed by 3 riders</>
                        : 'Still there? Tap to confirm'}
                    </small>
                  </div>
                </motion.div>
              )}
            </AnimatePresence>
          </div>

          <div className="stats">
            <div className="stat"><motion.b className="mono">{km}</motion.b><small>km</small></div>
            <div className="stat"><motion.b className="mono">{time}</motion.b><small>time</small></div>
            <div className="stat"><motion.b className="mono">{kmh}</motion.b><small>km/h</small></div>
          </div>

          <div className="elev">
            <svg viewBox="0 0 272 40" preserveAspectRatio="none" aria-hidden="true">
              <path d="M0 34 L30 30 60 32 90 24 120 26 150 18 180 12 210 14 240 8 272 6 V40 H0Z" fill="rgba(43,140,255,.12)" />
              <path d="M0 34 L30 30 60 32 90 24 120 26 150 18 180 12 210 14 240 8 272 6" fill="none" stroke="#2B8CFF" strokeWidth="1.5" />
              <motion.line x1={elevX} x2={elevX} y1="0" y2="40" stroke="#5BC1FF" strokeWidth="1" strokeDasharray="2 2" />
            </svg>
          </div>

          <div className="app-btn"><i className="rec-dot" />RECORDING</div>
        </motion.div>
      </div>
    </div>
  )
}
