# VITRAX website

Landing page for the VITRAX Android app. Built with **React 18**, **Vite** and **Framer Motion**.

## Run it

You need Node.js 18 or newer.

```bash
npm install
npm run dev        # opens a local dev server, usually http://localhost:5173
```

Build for hosting:

```bash
npm run build      # output goes to dist/
npm run preview    # check the built site locally
```

> Opening `index.html` by double-clicking will not work with a React/Vite project.
> Use `npm run dev` while working, and upload the `dist/` folder when you host it.

## Set the APK download link

1. Put your APK in `public/downloads/vitrax-1.0.0.apk`
2. Copy `.env.example` to `.env`
3. Run `npm run build` again

If the APK is hosted somewhere else (Google Drive, GitHub Releases), put that full link in `VITE_APK_URL`.

## Edit text

All copy (features, install steps, team, FAQ, contact) is in **`src/data/content.jsx`**.
You don't need to touch the components to change wording.

## Project structure

```
src/
  data/content.jsx          all site text
  components/
    Nav.jsx                 sticky nav, highlights the section you're in
    Hero.jsx                headline + phone (tilts toward cursor, drifts on scroll)
    HeroPhone.jsx           live demo: splash with logo, then a ride recording loop
    Ticker.jsx              scrolling strip of hazard reports
    Features.jsx            scroll story: text scrolls, phone stays and changes screen
    FeatureScreens.jsx      the 7 phone screens, one per feature
    Install.jsx             4 steps, progress line follows scroll
    Team.jsx, Faq.jsx, Contact.jsx, Footer.jsx
    Download.jsx            "Ready to ride?" panel
    SlideToDownload.jsx     drag-to-unlock control (spring physics, keyboard works too)
    Reveal.jsx              fade-in on scroll helper
    Contours.jsx            canvas topo lines in the background
    Logo.jsx                wordmark + app icon
  hooks/useActiveSection.js
  styles/global.css         colour/type tokens and shared styles
```

## Animation notes

- Every animation respects the visitor's **Reduce motion** setting (`MotionConfig reducedMotion="user"`).
- The hero ride loop pauses when the phone is off screen, and only re-renders React when the
  displayed text changes (signal state, hazard distance); everything else runs on motion values.
- Content that is already on screen at page load is never hidden waiting for an animation.

## Hosting

Any static host works: Netlify, Vercel, GitHub Pages, Firebase Hosting. Upload `dist/` or connect the repo
and use `npm run build` as the build command with `dist` as the output folder.
