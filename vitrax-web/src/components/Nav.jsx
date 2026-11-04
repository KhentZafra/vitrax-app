import { useEffect, useState } from 'react'
import { NAV_LINKS } from '../data/content.jsx'
import useActiveSection from '../hooks/useActiveSection.js'
import { Wordmark } from './Logo.jsx'
import { DownloadIcon } from './Icons.jsx'
import './Nav.css'

const SECTION_IDS = NAV_LINKS.map((l) => l.id)

export default function Nav() {
  const active = useActiveSection(SECTION_IDS)
  const [scrolled, setScrolled] = useState(false)

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 8)
    onScroll()
    window.addEventListener('scroll', onScroll, { passive: true })
    return () => window.removeEventListener('scroll', onScroll)
  }, [])

  return (
    <nav className={`nav ${scrolled ? 'nav--scrolled' : ''}`}>
      <div className="wrap nav__inner">
        <a href="#top" aria-label="VITRAX home"><Wordmark animate /></a>
        <ul className="nav__links">
          {NAV_LINKS.map((l) => (
            <li key={l.id}>
              <a href={`#${l.id}`} className={active === l.id ? 'is-active' : ''}>{l.label}</a>
            </li>
          ))}
        </ul>
        <a href="#download" className="btn btn--primary btn--sm nav__cta"><DownloadIcon />Download</a>
      </div>
    </nav>
  )
}
