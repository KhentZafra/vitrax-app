import { useEffect, useRef, useState } from 'react'
import { useReducedMotion } from 'framer-motion'

const SRC = '/vitrax_guide.mp4'
const POSTER = '/vitrax_guide_poster.jpg'

const SoundOn = () => (
  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <path d="M11 5 6 9H2v6h4l5 4V5z" /><path d="M15.5 8.5a5 5 0 0 1 0 7" /><path d="M18.5 5.5a9 9 0 0 1 0 13" />
  </svg>
)
const SoundOff = () => (
  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <path d="M11 5 6 9H2v6h4l5 4V5z" /><path d="m22 9-6 6" /><path d="m16 9 6 6" />
  </svg>
)

/** The how-to video, framed like a phone. Plays muted and looped while it is on screen. */
export default function HeroVideo() {
  const reduce = useReducedMotion()
  const ref = useRef(null)
  const [muted, setMuted] = useState(true)
  const [playing, setPlaying] = useState(false)

  // Only play while the video is actually visible (saves data and battery).
  useEffect(() => {
    const v = ref.current
    if (!v || typeof IntersectionObserver === 'undefined') return undefined
    const io = new IntersectionObserver(([entry]) => {
      if (entry.isIntersecting && !reduce) v.play().catch(() => {})
      else v.pause()
    }, { threshold: 0.35 })
    io.observe(v)
    return () => io.disconnect()
  }, [reduce])

  const togglePlay = () => {
    const v = ref.current
    if (!v) return
    if (v.paused) v.play().catch(() => {})
    else v.pause()
  }

  const toggleSound = (e) => {
    e.stopPropagation()
    const v = ref.current
    if (!v) return
    if (v.muted) {
      v.muted = false
      v.currentTime = 0 // start the guide over, this time with sound
      v.play().catch(() => {})
      setMuted(false)
    } else {
      v.muted = true
      setMuted(true)
    }
  }

  return (
    <div className="phone phone--video" aria-label="How to use VITRAX: video guide">
      <div className="phone__screen phone__screen--video">
        <video
          ref={ref}
          className="hero-video"
          src={SRC}
          poster={POSTER}
          muted
          loop
          playsInline
          preload="metadata"
          onClick={togglePlay}
          onPlay={() => setPlaying(true)}
          onPause={() => setPlaying(false)}
        />
        {!playing && (
          <button type="button" className="hero-video__play" onClick={togglePlay} aria-label="Play the video guide">
            <svg width="26" height="26" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M8 5v14l11-7z" /></svg>
          </button>
        )}
        <button type="button" className="hero-video__sound" onClick={toggleSound} aria-label={muted ? 'Turn sound on' : 'Mute the video'}>
          {muted ? <SoundOff /> : <SoundOn />}
          <span>{muted ? 'Tap for sound' : 'Mute'}</span>
        </button>
      </div>
    </div>
  )
}
