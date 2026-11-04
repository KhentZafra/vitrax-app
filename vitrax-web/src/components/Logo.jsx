import { motion } from 'framer-motion'
import mark from '../assets/vitrax-mark-200.png'
import full from '../assets/vitrax-logo-960.webp'
import './Logo.css'

/** Runner mark + wordmark used in the nav and footer. */
export function Wordmark({ animate = false }) {
  return (
    <span className="wordmark">
      {/* The mark wipes in left-to-right, the same direction the runner moves. */}
      <motion.img
        src={mark}
        alt=""
        className="wordmark__mark"
        initial={animate ? { clipPath: 'inset(0 100% 0 0)' } : false}
        animate={{ clipPath: 'inset(0 0% 0 0)' }}
        transition={{ duration: 0.9, ease: [0.2, 0.7, 0.2, 1], delay: 0.1 }}
      />
      <span className="wordmark__text">VITRAX</span>
    </span>
  )
}

/** The app icon tile: logo on the dark rounded square used on the phone. */
export function AppIcon({ size = 112, className = '' }) {
  return (
    <span className={`app-icon ${className}`} style={{ '--s': `${size}px` }}>
      <img src={full} alt="VITRAX app icon" />
    </span>
  )
}
