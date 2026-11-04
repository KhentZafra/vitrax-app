import { useRef, useState } from 'react'
import { AnimatePresence, motion, useMotionValueEvent, useScroll, useSpring } from 'framer-motion'
import { FEATURES } from '../data/content.jsx'
import Reveal from './Reveal.jsx'
import { SCREENS } from './FeatureScreens.jsx'
import './Features.css'

const pad = (n) => String(n).padStart(2, '0')

/**
 * Scroll story: the text column scrolls, the phone stays put and switches screens.
 * Progress is read from the scroll position itself (not just "is this visible"),
 * so the rail fills continuously and the active step is always exact.
 */
export default function Features() {
  const stepsRef = useRef(null)
  const [active, setActive] = useState(0)
  const { scrollYProgress } = useScroll({ target: stepsRef, offset: ['start center', 'end center'] })
  const rail = useSpring(scrollYProgress, { stiffness: 140, damping: 26, restDelta: 0.001 })

  useMotionValueEvent(scrollYProgress, 'change', (p) => {
    const i = Math.min(FEATURES.length - 1, Math.max(0, Math.floor(p * FEATURES.length)))
    setActive(i)
  })

  const Screen = SCREENS[FEATURES[active].screen]

  return (
    <section className="sec" id="features">
      <div className="wrap">
        <Reveal className="sec-head">
          <span className="eyebrow">Features</span>
          <h2 className="h2">Everything for the road in one app.</h2>
          <p className="lede">Built around how people actually ride and run in Bohol, where signal comes and goes. Scroll to see each feature on the phone.</p>
        </Reveal>

        <div className="story">
          <div className="story__steps" ref={stepsRef}>
            <div className="story__rail" aria-hidden="true"><motion.i style={{ scaleY: rail }} /></div>
            {FEATURES.map((f, i) => (
              <article key={f.screen} className={`step ${i === active ? 'is-active' : ''}`}>
                <span className="step__n">{pad(i + 1)} — {f.label}</span>
                <h3 className="step__title">{f.title}</h3>
                <p className="step__body">{f.body}</p>
                <ul className="step__points">{f.points.map((p) => <li key={p}>{p}</li>)}</ul>
              </article>
            ))}
          </div>

          <div className="story__phone-col">
            <div className="story__phone">
              <div className="phone">
                <div className="phone__screen">
                  <div className="phone__island" />
                  <AnimatePresence initial={false}>
                    <motion.div
                      key={active}
                      className="app"
                      initial={{ opacity: 0, y: 18 }}
                      animate={{ opacity: 1, y: 0 }}
                      exit={{ opacity: 0, y: -12 }}
                      transition={{ duration: 0.45, ease: [0.2, 0.7, 0.2, 1] }}
                    >
                      <Screen />
                    </motion.div>
                  </AnimatePresence>
                </div>
              </div>
              <div className="story__dots" aria-hidden="true">
                {FEATURES.map((f, i) => <i key={f.screen} className={i === active ? 'on' : ''} />)}
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}
