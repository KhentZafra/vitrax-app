import { useEffect, useRef } from 'react'

/**
 * Faint topographic contour lines, a nod to the Chocolate Hills.
 * Drawn once to a canvas (and again on resize), so it costs nothing while scrolling.
 * hills: [xFraction, yFraction, radiusPx, seed]
 */
export default function Contours({ hills, alpha = 0.035, step = 0.009, className = '' }) {
  const ref = useRef(null)

  useEffect(() => {
    const canvas = ref.current
    const ctx = canvas.getContext('2d')
    let timer

    const draw = () => {
      const { width, height } = canvas.getBoundingClientRect()
      const dpr = Math.min(window.devicePixelRatio || 1, 2)
      canvas.width = width * dpr
      canvas.height = height * dpr
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
      ctx.clearRect(0, 0, width, height)
      ctx.lineWidth = 1

      for (const [fx, fy, size, seed] of hills) {
        const cx = fx * width
        const cy = fy * height
        for (let k = 1; k <= 9; k++) {
          const r = (size * k) / 9
          ctx.beginPath()
          for (let a = 0; a <= Math.PI * 2 + 0.01; a += Math.PI / 40) {
            const wobble = 1 + 0.12 * Math.sin(a * 3 + seed + k * 0.4) + 0.07 * Math.sin(a * 5 - seed)
            const x = cx + Math.cos(a) * r * wobble * 1.35
            const y = cy + Math.sin(a) * r * wobble * 0.8
            a === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y)
          }
          ctx.strokeStyle = `rgba(91, 150, 230, ${alpha + k * step})`
          ctx.stroke()
        }
      }
    }

    const onResize = () => { clearTimeout(timer); timer = setTimeout(draw, 150) }
    draw()
    window.addEventListener('resize', onResize)
    return () => { window.removeEventListener('resize', onResize); clearTimeout(timer) }
  }, [hills, alpha, step])

  return <canvas ref={ref} className={className} aria-hidden="true" />
}
