import { useLayoutEffect, useRef, useState } from 'react'
import { motion } from 'framer-motion'

/**
 * Fades content up as it scrolls into view.
 * Anything already on screen when the page loads renders immediately,
 * so the first frame is never half-empty.
 */
export default function Reveal({ as = 'div', delay = 0, children, ...rest }) {
  const ref = useRef(null)
  const [hidden, setHidden] = useState(false)
  const Tag = motion[as]

  useLayoutEffect(() => {
    const top = ref.current?.getBoundingClientRect().top ?? 0
    if (top > window.innerHeight) setHidden(true)
  }, [])

  return (
    <Tag
      ref={ref}
      initial={false}
      animate={hidden ? { opacity: 0, y: 24, transition: { duration: 0 } } : undefined}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: '0px 0px -8% 0px' }}
      transition={{ duration: 0.8, ease: [0.2, 0.7, 0.2, 1], delay }}
      {...rest}
    >
      {children}
    </Tag>
  )
}
