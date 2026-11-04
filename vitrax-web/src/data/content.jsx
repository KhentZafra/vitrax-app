// All site copy lives here so the team can edit text without touching components.

export const APP = {
  name: 'VITRAX',
  version: '1.0.0',
  minAndroid: 'Android 10',
  apkUrl: import.meta.env.VITE_APK_URL || '#download',
}

export const NAV_LINKS = [
  { id: 'features', label: 'Features' },
  { id: 'how', label: 'How it works' },
  { id: 'team', label: 'Team' },
  { id: 'faq', label: 'FAQ' },
  { id: 'contact', label: 'Contact' },
]

// Example reports for the scrolling strip under the hero.
export const HAZARD_TICKER = [
  { type: 'Pothole', road: 'Loay Interior Rd', confirms: 3, ago: '12 min ago' },
  { type: 'Flood', road: 'Loboc River Rd, km 2.4', confirms: 5, ago: '40 min ago', tone: 'blue' },
  { type: 'Stray dog', road: 'Carmen–Bilar Rd', confirms: 2, ago: '1 h ago' },
  { type: 'Traffic', road: 'CPG Ave, Tagbilaran', confirms: 6, ago: '2 h ago' },
  { type: 'Pothole', road: 'Dauis–Panglao Rd, km 15', confirms: 4, ago: '3 h ago' },
  { type: 'Flood', road: 'Corella, Sikatuna junction', confirms: 1, ago: '5 h ago', tone: 'blue' },
]

// Each feature has a matching phone screen in FeatureScreens.jsx (same `screen` key).
export const FEATURES = [
  {
    screen: 'offline',
    label: 'Offline recording',
    title: 'Record your route with zero signal.',
    body: 'GPS tracking keeps working with no signal. Your activity saves on the phone, so a dead zone in the hills never breaks your ride.',
    points: ['Distance, time, pace and elevation', 'Saved on your phone until you are back online'],
  },
  {
    screen: 'report',
    label: 'Hazard reports',
    title: 'Report a hazard in one tap.',
    body: 'Report potholes, floods, stray dogs and traffic. Other users confirm them, and they clear once the road is safe again.',
    points: ['Pinned to your exact location', 'Large buttons you can hit with gloves on'],
  },
  {
    screen: 'alert',
    label: 'Voice and vibration alerts',
    title: 'Get warned before you reach it.',
    body: 'Get a spoken warning and a buzz as you approach a reported hazard, without looking at the screen.',
    points: ['Distance counts down as you get closer', 'Keep your eyes on the road'],
  },
  {
    screen: 'sync',
    label: 'Sync',
    title: 'Everything syncs when you are back online.',
    body: 'Your activity and reports upload when you get signal again, and you pull down what other riders reported while you were out.',
    points: ['Activity history kept on your phone', 'Uses very little mobile data'],
  },
  {
    screen: 'challenges',
    label: 'Challenges and badges',
    title: 'Climb the podium on local challenges.',
    body: 'Create or join local challenges, climb the podium and earn badges from Bronze all the way to Elite.',
    points: ['Monthly distance and route challenges', 'Six badge levels: Bronze, Silver, Gold, Platinum, Diamond, Elite'],
  },
  {
    screen: 'community',
    label: 'Community and chat',
    title: 'Ride with people near you.',
    body: 'Share routes, post to the feed, like and comment, and message other riders and runners directly.',
    points: ['Post your activities to the feed', 'Plan group rides in direct messages'],
  },
  {
    screen: 'privacy',
    label: 'Private by design',
    title: 'Your home stays off the map.',
    body: 'The start and end of your routes stay hidden. You can delete your account and data at any time.',
    points: ['Hidden zones where you start and stop', 'Delete your account and data from settings'],
  },
]

export const INSTALL_STEPS = [
  { title: 'Download', body: <>Tap <b>Download for Android</b> and wait for the file to finish.</> },
  { title: 'Allow install', body: <>If asked, allow <b>Install unknown apps</b> for your browser. This is normal outside the Play Store.</> },
  { title: 'Install', body: <>Open the file and tap <b>Install</b>. If Play Protect warns you, choose <b>Install anyway</b>.</> },
  { title: 'Sign up', body: <>Open VITRAX, create an account and enter the code we email you.</> },
]

export const TEAM = [
  { name: 'Khent Zafra', role: 'Senior Developer', note: 'Lead Developer', initials: 'KZ', photo: 'team/khent.jpg' },
  { name: 'John Aaron Barril', role: 'Junior Developer', note: 'Frontend Developer', initials: 'JB', photo: 'team/aaron.jpg' },
  { name: 'Trisha Mae Caiyas', role: 'Documentary & Multimedia', note: 'Documentation & Multimedia', initials: 'TC', photo: 'team/trisha.jpg' },
]

export const SCHOOL = 'Cristal e-College, Panglao, Bohol'

export const FAQ = [
  {
    q: 'Is VITRAX free?',
    a: 'Yes. VITRAX 1.0.0 is free to download and use.',
  },
  {
    q: 'Why does my phone warn me when installing?',
    a: 'Android shows that warning for every app installed outside the Play Store. Allow "Install unknown apps" for your browser, and if Play Protect appears, choose "Install anyway". Only download VITRAX from this website.',
  },
  {
    q: 'Does it work without internet?',
    a: 'Yes. GPS works without mobile data, so VITRAX keeps recording your activity and saves it on your phone. It syncs your activity and hazard reports when you are back online.',
  },
  {
    q: 'Which phones are supported?',
    a: 'Android phones running Android 10 or newer with GPS. An iPhone version is not available yet.',
  },
  {
    q: 'How is my location used?',
    a: 'Your location is used to record your activities and to warn you about hazards near you. The start and end of your routes stay hidden from other users, and you can delete your account and data at any time.',
  },
]

export const CONTACT = {
  address: 'KM 15, Dauis-Panglao Road, Tawala, Panglao, Bohol, Philippines',
  email: 'paseo0396@gmail.com',
}
