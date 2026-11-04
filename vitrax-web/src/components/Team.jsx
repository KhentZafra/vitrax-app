import { SCHOOL, TEAM } from '../data/content.jsx'
import Reveal from './Reveal.jsx'
import './Team.css'

export default function Team() {
  return (
    <section className="sec" id="team">
      <div className="wrap">
        <Reveal className="sec-head">
          <span className="eyebrow">The team</span>
          <h2 className="h2">Meet the developers.</h2>
          <p className="lede">VITRAX is built by students of {SCHOOL}.</p>
        </Reveal>
        <div className="team">
          {TEAM.map((m, i) => (
            <Reveal key={m.name} className="mate" delay={i * 0.08}>
              <span className="mate__av">{m.photo ? <img src={m.photo} alt={m.name} loading="lazy" /> : m.initials}</span>
              <b>{m.name}</b>
              <span className="mate__role">{m.role}</span>
              {m.note && <span className="mate__note">{m.note}</span>}
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  )
}
