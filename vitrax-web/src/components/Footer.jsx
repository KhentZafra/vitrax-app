import { SCHOOL } from '../data/content.jsx'
import { Wordmark } from './Logo.jsx'
import './Footer.css'

export default function Footer() {
  return (
    <footer className="footer">
      <div className="wrap footer__inner">
        <div>
          <a href="#top" aria-label="Back to top"><Wordmark /></a>
          <p>Offline activity tracking and community hazard alerts for cyclists and runners in Bohol.</p>
        </div>
        <div className="footer__meta">
          <span>Built at {SCHOOL}</span>
          <a href="./privacy.html">Privacy Policy</a>
          <span>© {new Date().getFullYear()} VITRAX</span>
        </div>
      </div>
    </footer>
  )
}
