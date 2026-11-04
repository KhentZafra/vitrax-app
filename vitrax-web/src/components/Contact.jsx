import { useState } from 'react'
import { CONTACT } from '../data/content.jsx'
import Reveal from './Reveal.jsx'
import './Contact.css'

export default function Contact() {
  const [copied, setCopied] = useState('Copy')

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(CONTACT.email)
      setCopied('Copied')
    } catch {
      setCopied('Press Ctrl+C')
    }
    setTimeout(() => setCopied('Copy'), 1600)
  }

  return (
    <section className="sec contact" id="contact">
      <div className="wrap contact__grid">
        <Reveal className="sec-head contact__head">
          <span className="eyebrow">Contact</span>
          <h2 className="h2">Get in touch.</h2>
          <p className="lede">Questions, feedback or bug reports? Reach out to the team.</p>
        </Reveal>

        <div className="contact__cards">
          <Reveal className="c-card">
            <svg className="c-card__ico" viewBox="0 0 40 40" aria-hidden="true">
              <path d="M20 4c-6.6 0-12 5.2-12 11.7C8 24 20 36 20 36s12-12 12-20.3C32 9.2 26.6 4 20 4z" />
              <circle cx="20" cy="15.5" r="4.5" className="hi" />
            </svg>
            <span className="eyebrow c-card__k">Address</span>
            <p>{CONTACT.address}</p>
          </Reveal>
          <Reveal className="c-card" delay={0.08}>
            <svg className="c-card__ico" viewBox="0 0 40 40" aria-hidden="true">
              <rect x="5" y="9" width="30" height="22" rx="4" />
              <path d="M7 12l13 10 13-10" className="hi-s" />
            </svg>
            <span className="eyebrow c-card__k">Email</span>
            <span className="c-card__mail">
              <a href={`mailto:${CONTACT.email}`}>{CONTACT.email}</a>
              <button onClick={copy}>{copied}</button>
            </span>
          </Reveal>
        </div>
      </div>
    </section>
  )
}
