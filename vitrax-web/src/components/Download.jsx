import { useRef } from 'react'
import { motion, useScroll, useTransform } from 'framer-motion'
import { APP } from '../data/content.jsx'
import Contours from './Contours.jsx'
import { AppIcon } from './Logo.jsx'
import Reveal from './Reveal.jsx'
import SlideToDownload from './SlideToDownload.jsx'
import './Download.css'

const HILLS = [[0.85, 0.3, 180, 2], [0.2, 1, 150, 4]]

const SPECS = [
  ['Version', APP.version],
  ['Requires', `${APP.minAndroid}+`],
  ['Price', 'Free'],
  ['Works offline', 'Yes'],
  ['Made for', 'Bohol roads'],
]

export default function Download() {
  const ref = useRef(null)
  // The app icon rises and straightens as the panel scrolls into place.
  const { scrollYProgress } = useScroll({ target: ref, offset: ['start end', 'center center'] })
  const iconY = useTransform(scrollYProgress, [0, 1], [60, 0])
  const iconRotate = useTransform(scrollYProgress, [0, 1], [-10, 0])

  return (
    <section className="dl" id="download" ref={ref}>
      <div className="wrap">
        <Reveal className="dl__box">
          <Contours hills={HILLS} alpha={0.04} step={0.012} className="dl__contours" />
          <div className="dl__main">
            <motion.div style={{ y: iconY, rotate: iconRotate }} className="dl__icon">
              <AppIcon size={92} />
            </motion.div>
            <span className="eyebrow">Download</span>
            <h2 className="h2">Ready to ride?</h2>
            <p className="lede">Slide to get VITRAX, the same way you start a recording in the app.</p>
            <SlideToDownload />
          </div>
          <ul className="dl__specs">
            {SPECS.map(([k, v]) => <li key={k}><span>{k}</span><b className="mono">{v}</b></li>)}
          </ul>
        </Reveal>
      </div>
    </section>
  )
}
