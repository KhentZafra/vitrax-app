import { HAZARD_TICKER } from '../data/content.jsx'
import './Ticker.css'

const Item = ({ h, hidden }) => (
  <div className="tick" aria-hidden={hidden || undefined}>
    <span className={`tick__type ${h.tone === 'blue' ? 'tick__type--blue' : ''}`}>{h.type}</span>
    <b>{h.road}</b>· {h.confirms} confirmation{h.confirms > 1 ? 's' : ''} · {h.ago}
  </div>
)

/** Endless strip of recent hazard reports. The list is rendered twice so the loop is seamless. */
export default function Ticker() {
  return (
    <div className="ticker" aria-label="Recent hazard reports (example data)">
      <div className="ticker__track">
        {HAZARD_TICKER.map((h, i) => <Item key={`a${i}`} h={h} />)}
        {HAZARD_TICKER.map((h, i) => <Item key={`b${i}`} h={h} hidden />)}
      </div>
    </div>
  )
}
