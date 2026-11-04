import { useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { FAQ } from '../data/content.jsx'
import Reveal from './Reveal.jsx'
import './Faq.css'

export default function Faq() {
  const [open, setOpen] = useState(0)

  return (
    <section className="sec sec--deck" id="faq">
      <div className="wrap faq">
        <Reveal className="sec-head faq__head">
          <span className="eyebrow">FAQ</span>
          <h2 className="h2">Common questions.</h2>
          <p className="lede">Something else? Reach the team from the contact section below.</p>
        </Reveal>

        <div>
          {FAQ.map((item, i) => {
            const isOpen = open === i
            return (
              <div key={item.q} className="qa">
                <button
                  className="qa__q"
                  aria-expanded={isOpen}
                  aria-controls={`faq-${i}`}
                  onClick={() => setOpen(isOpen ? -1 : i)}
                >
                  {item.q}
                  <span className={`qa__pm ${isOpen ? 'is-open' : ''}`} aria-hidden="true" />
                </button>
                <AnimatePresence initial={false}>
                  {isOpen && (
                    <motion.div
                      id={`faq-${i}`}
                      className="qa__a"
                      initial={{ height: 0, opacity: 0 }}
                      animate={{ height: 'auto', opacity: 1 }}
                      exit={{ height: 0, opacity: 0 }}
                      transition={{ duration: 0.35, ease: [0.2, 0.7, 0.2, 1] }}
                    >
                      <p>{item.a}</p>
                    </motion.div>
                  )}
                </AnimatePresence>
              </div>
            )
          })}
        </div>
      </div>
    </section>
  )
}
