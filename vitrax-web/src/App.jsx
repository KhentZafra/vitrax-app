import { MotionConfig } from 'framer-motion'
import Nav from './components/Nav.jsx'
import Hero from './components/Hero.jsx'
import Ticker from './components/Ticker.jsx'
import Features from './components/Features.jsx'
import Install from './components/Install.jsx'
import Team from './components/Team.jsx'
import Faq from './components/Faq.jsx'
import Download from './components/Download.jsx'
import Contact from './components/Contact.jsx'
import Footer from './components/Footer.jsx'

export default function App() {
  // reducedMotion="user" makes every Framer Motion animation respect the
  // visitor's "reduce motion" setting without extra checks in each component.
  return (
    <MotionConfig reducedMotion="user">
      <Nav />
      <main>
        <Hero />
        <Ticker />
        <Features />
        <Install />
        <Team />
        <Faq />
        <Download />
        <Contact />
      </main>
      <Footer />
    </MotionConfig>
  )
}
