import { useRef, useState } from 'react'
import { motion, useMotionValueEvent, useScroll } from 'framer-motion'
import { APP, INSTALL_STEPS } from '../data/content.jsx'
import Reveal from './Reveal.jsx'
import { DownloadIcon } from './Icons.jsx'
import './Install.css'

/** The progress line fills with scroll and lights each step as it passes. */
export default function Install() {
  const gridRef = useRef(null)
  const [lit, setLit] = useState(0)
  const { scrollYProgress } = useScroll({ target: gridRef, offset: ['start 85%', 'end 55%'] })

  useMotionValueEvent(scrollYProgress, 'change', (p) => {
    setLit(Math.ceil(p * INSTALL_STEPS.length - 0.05))
  })

  return (
    <section className="sec sec--deck" id="how">
      <div className="wrap">
        <Reveal className="sec-head">
          <span className="eyebrow">How it works · get the app</span>
          <h2 className="h2">Install in four steps.</h2>
          <p className="lede">VITRAX is shared as a direct download, so Android will ask you to allow it once.</p>
        </Reveal>

        <div className="install-wrap" ref={gridRef}>
          <div className="install__line" aria-hidden="true"><motion.i style={{ scaleX: scrollYProgress }} /></div>
          <ol className="install">
          {INSTALL_STEPS.map((s, i) => (
            <li key={s.title} className={`install__step ${i < lit ? 'is-lit' : ''}`}>
              <span className="install__dot">{i + 1}</span>
              <h3>{s.title}</h3>
              <p>{s.body}</p>
            </li>
          ))}
          </ol>
        </div>

        <div className="install__cta">
          <a href="#download" className="btn btn--primary"><DownloadIcon />Download VITRAX {APP.version}</a>
        </div>
      </div>
    </section>
  )
}
