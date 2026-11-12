import { useRef } from 'react'
import { motion, useMotionValue, useReducedMotion, useScroll, useSpring, useTransform } from 'framer-motion'
import { APP } from '../data/content.jsx'
import Contours from './Contours.jsx'
import HeroVideo from './HeroVideo.jsx'
import { DownloadIcon } from './Icons.jsx'
import './Hero.css'

const HILLS = [[0.08, 0.2, 190, 1], [0.32, 0.92, 160, 2.4], [0.62, 0.1, 130, 4], [0.9, 0.75, 240, 5.2], [0.5, 0.55, 90, 3]]
const EASE = [0.2, 0.7, 0.2, 1]

const line = (i) => ({
  initial: { y: '105%' },
  animate: { y: 0 },
  transition: { duration: 1, ease: EASE, delay: 0.08 * i },
})
const fade = (delay) => ({
  initial: { opacity: 0, y: 14 },
  animate: { opacity: 1, y: 0 },
  transition: { duration: 0.9, ease: EASE, delay },
})

export default function Hero() {
  const ref = useRef(null)
  const reduce = useReducedMotion()

  // Phone leans slightly toward the cursor, with spring physics so it settles naturally.
  const px = useMotionValue(0)
  const py = useMotionValue(0)
  const rotateY = useSpring(useTransform(px, [-0.5, 0.5], [-9, 9]), { stiffness: 120, damping: 18 })
  const rotateX = useSpring(useTransform(py, [-0.5, 0.5], [7, -7]), { stiffness: 120, damping: 18 })

  // And drifts up a little as you scroll past the hero.
  const { scrollYProgress } = useScroll({ target: ref, offset: ['start start', 'end start'] })
  const phoneY = useTransform(scrollYProgress, [0, 1], [0, -70])

  const onMove = (e) => {
    if (reduce || e.pointerType !== 'mouse') return
    const r = ref.current.getBoundingClientRect()
    px.set((e.clientX - r.left) / r.width - 0.5)
    py.set((e.clientY - r.top) / r.height - 0.5)
  }
  const onLeave = () => { px.set(0); py.set(0) }

  return (
    <header className="hero" id="top" ref={ref} onPointerMove={onMove} onPointerLeave={onLeave}>
      <Contours hills={HILLS} className="hero__contours" />
      <div className="wrap hero__inner">
        <div className="hero__copy">
          <motion.span className="hero__tag" {...fade(0.3)}>
            <b>BOHOL</b>Made for cyclists and runners on Bohol roads
          </motion.span>

          <h1 className="hero__title">
            <span className="hero__line"><motion.span {...line(0)}>Ride and run</motion.span></span>
            <span className="hero__line"><motion.span {...line(1)}><em>smarter</em>, even</motion.span></span>
            <span className="hero__line">
              <motion.span {...line(2)}>
                without{' '}
                <span className="hero__strike">
                  signal
                  <motion.i initial={{ scaleX: 0 }} animate={{ scaleX: 1 }} transition={{ duration: 0.6, ease: EASE, delay: 0.95 }} />
                </span>.
              </motion.span>
            </span>
          </h1>

          <motion.p className="lede" {...fade(0.4)}>
            VITRAX records your activity offline and warns you about potholes, floods and stray dogs
            reported by local riders, before you reach them.
          </motion.p>

          <motion.div className="hero__ctas" {...fade(0.5)}>
            <a href="#download" className="btn btn--primary"><DownloadIcon />Download for Android</a>
            <a href="#how" className="btn btn--ghost">How to install</a>
          </motion.div>

          <motion.div className="hero__meta" {...fade(0.6)}>
            <span><i /> <b>Version {APP.version}</b></span>
            <span>{APP.minAndroid} or newer</span>
            <span>Free</span>
            <span>APK</span>
          </motion.div>
        </div>

        <motion.div
          className="hero__stage"
          initial={{ opacity: 0, y: 40 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 1.1, ease: EASE, delay: 0.15 }}
        >
          <motion.div style={{ rotateX, rotateY, y: phoneY, transformPerspective: 1200 }}>
            <HeroVideo />
          </motion.div>
        </motion.div>
      </div>
    </header>
  )
}
