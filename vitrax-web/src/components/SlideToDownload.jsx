import { useEffect, useRef, useState } from 'react'
import { animate, motion, useInView, useMotionValue, useReducedMotion, useTransform } from 'framer-motion'
import { APP } from '../data/content.jsx'
import { CheckIcon, ChevronIcon, DownloadIcon } from './Icons.jsx'

const KNOB = 56
const INSET = 6
const SPRING = { type: 'spring', stiffness: 420, damping: 34 }

/**
 * "Slide to download", modelled on the app's own start-recording control.
 * Drag past 85% (or press Enter / Space / →) to unlock the download button.
 */
export default function SlideToDownload() {
  const trackRef = useRef(null)
  const inView = useInView(trackRef, { once: true, amount: 1 })
  const reduce = useReducedMotion()
  const [max, setMax] = useState(300)
  const [done, setDone] = useState(false)
  const x = useMotionValue(0)
  const fill = useTransform(x, (v) => v + KNOB + INSET)
  const labelOpacity = useTransform(x, (v) => Math.max(0, 1 - v / ((trackRef.current?.clientWidth ?? 400) * 0.5)))

  useEffect(() => {
    const measure = () => setMax(trackRef.current.clientWidth - KNOB - INSET * 2)
    measure()
    window.addEventListener('resize', measure)
    return () => window.removeEventListener('resize', measure)
  }, [])

  useEffect(() => { if (done) x.set(max) }, [max, done, x])

  // One small nudge the first time it's fully on screen, so people see it moves.
  useEffect(() => {
    if (!inView || done || reduce) return
    const t = setTimeout(async () => {
      await animate(x, 46, SPRING)
      animate(x, 0, { ...SPRING, delay: 0.15 })
    }, 600)
    return () => clearTimeout(t)
  }, [inView, done, reduce, x])

  const unlock = () => {
    setDone(true)
    animate(x, max, SPRING)
  }

  const onDragEnd = () => {
    if (x.get() > max * 0.85) unlock()
    else animate(x, 0, SPRING)
  }

  const onKeyDown = (e) => {
    if (!done && ['Enter', ' ', 'ArrowRight'].includes(e.key)) {
      e.preventDefault()
      unlock()
    }
  }

  return (
    <div className="slide">
      <div ref={trackRef} className={`slide__track ${done ? 'is-done' : ''}`}>
        <motion.div className="slide__fill" style={{ width: fill }} />
        <motion.span className="slide__label" style={{ opacity: done ? 1 : labelOpacity }}>
          {done ? 'Unlocked' : 'Slide to download'}
        </motion.span>
        <motion.button
          className="slide__knob"
          aria-label={done ? 'Download unlocked' : 'Slide, or press Enter, to unlock the download'}
          drag={done ? false : 'x'}
          dragConstraints={{ left: 0, right: max }}
          dragElastic={0.06}
          dragMomentum={false}
          onDragEnd={onDragEnd}
          onKeyDown={onKeyDown}
          onClick={(e) => e.detail === 0 && !done && unlock()}
          whileTap={done ? undefined : { scale: 0.94 }}
          style={{ x }}
        >
          {done ? <CheckIcon /> : <ChevronIcon />}
        </motion.button>
      </div>

      <motion.div
        className="slide__unlock"
        initial={false}
        animate={done ? { opacity: 1, y: 0, pointerEvents: 'auto' } : { opacity: 0, y: 10, pointerEvents: 'none' }}
        transition={{ duration: 0.5, ease: [0.2, 0.7, 0.2, 1], delay: done ? 0.25 : 0 }}
      >
        <a className="btn btn--primary slide__btn" href={APP.apkUrl} tabIndex={done ? 0 : -1}>
          <DownloadIcon />Download VITRAX {APP.version} APK
        </a>
        <small>After it downloads, follow the four install steps above.</small>
      </motion.div>
    </div>
  )
}
