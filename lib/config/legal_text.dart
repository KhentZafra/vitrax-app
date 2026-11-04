// GENERATED from the same text as legal/privacy-policy.html.
// If you change the wording, change it in both places and bump
// kPolicyVersion so existing users are asked to accept it again.

/// Shown to users and stored on their profile when they accept.
const String kPolicyVersion = '2026-10-16';

class LegalSection {
  final String heading;
  final List<String> paragraphs;
  const LegalSection(this.heading, this.paragraphs);
}

const List<LegalSection> kPrivacyPolicy = [
  LegalSection('Who we are', [
    'VITRAX is a mobile application for cyclists and runners, built as a capstone project by Khent A. Zafra, John Aaron L. Barril, and Trisha Mae D. Caiyas of Cristal e-College. In this policy, "we" and "us" mean these researchers.',
    'For questions about your data, contact us at paseo0396@gmail.com.',
  ]),
  LegalSection('What we collect', [
    'Account details: your name, email address, activity type (cyclist or runner), and profile photo.',
    'Activity data: GPS routes, distance, speed, duration, start time, and the activity type you recorded.',
    'Hazard reports: the hazard type, its location, the time, and any photos you attach.',
    'Community content: posts, comments, reactions, shared routes, and chat messages.',
    'Challenge data: the challenges you join or create, your progress, and, if you upload one, your GCash QR code image and payment status.',
    'Safety data: users you block, reports you make or receive, and warnings or suspensions.',
    'Technical data: a device token so we can send you push notifications, and badges you have earned.',
  ]),
  LegalSection('Why we collect it', [
    'To run the features you ask for: recording activities, showing routes and hazards, challenges, the community feed, chat, and notifications.',
    'To keep the community safe: reviewing reports, removing false hazards or harmful content, and suspending abusive accounts.',
    'To evaluate the system for our academic study. Results are reported in summary form and do not name you.',
  ]),
  LegalSection('Your location', [
    'We collect your location only while you record an activity, plan a route, or report a hazard.',
    'When you share an activity, other users see its route with the first and last part removed. You choose how much to hide (200 m by default) in Edit Profile > Route privacy. Your full route stays available to you and to administrators.',
    'A hazard you report shows its location to the community, because that is the purpose of the report.',
  ]),
  LegalSection('Who can see your information', [
    'Other users: your name, profile photo, posts, comments, shared activities (with route privacy applied), badges, and hazard reports.',
    'Administrators: they can review users, posts, hazards, activities, and reports in order to moderate the community. Every administrator action is recorded in an audit log.',
    'Service providers that process data for the app: Supabase (database, sign-in, and file storage), Firebase Cloud Messaging (push notifications), OpenStreetMap (map tiles), and OpenRouteService (route planning, which receives the start and end points you ask it to route).',
    'We do not sell your data or use it for advertising.',
  ]),
  LegalSection('How long we keep it', [
    'We keep your data while your account exists. You can delete your account in the app at Edit Profile > Account > Delete my account. This removes your profile, activities, posts, comments, hazard reports, and messages.',
    'A minimal moderation record (for example, that a hazard was removed) may be kept for safety and accountability.',
  ]),
  LegalSection('Your rights', [
    'Under the Data Privacy Act of 2012 (Republic Act 10173) you have the right to be informed, to access your data, to correct it (you can edit your profile in the app), to object or withdraw your consent, to have your data deleted, and to file a complaint with the National Privacy Commission.',
    'To use a right that the app does not cover, contact us at paseo0396@gmail.com.',
  ]),
  LegalSection('Security', [
    'Data travels over encrypted connections, and the database uses access rules so users can only see and change what they are allowed to. No system is perfectly secure, so please use a strong password and keep it private.',
  ]),
  LegalSection('Children', [
    'VITRAX is not meant for children under 13. If you are under 18, please use the app with the knowledge and permission of a parent or guardian.',
  ]),
  LegalSection('Changes to this policy', [
    'If we make an important change, we will ask you to review and accept the updated policy in the app. This version is dated 2026-10-16.',
  ]),
];

const List<LegalSection> kTermsOfUse = [
  LegalSection('Using VITRAX', [
    'By creating an account you agree to these terms and to the Privacy Policy. You must give accurate information and keep your password private.',
    'VITRAX is a capstone project provided as is. We do our best to keep it working but cannot promise it will always be available or error-free.',
  ]),
  LegalSection('Stay safe', [
    'Road and trail conditions change quickly. Hazard reports come from other users and may be wrong or out of date, so always watch the road yourself.',
    'Do not use your phone while riding or running in a way that puts you or others at risk. Follow traffic laws.',
    'VITRAX does not give medical advice or fitness coaching.',
  ]),
  LegalSection('What you must not do', [
    'Post false hazards, fake your location, or cheat in challenges.',
    'Harass, threaten, or impersonate others, or post hateful, sexual, or illegal content.',
    'Share other people\'s private information or try to find where someone lives or works.',
    'Try to break, overload, or get around the app\'s security.',
  ]),
  LegalSection('Your content', [
    'You keep ownership of what you post. By posting, you let VITRAX show it to other users as part of the app.',
    'We may remove content or hazards that break these terms.',
  ]),
  LegalSection('Challenges and payments', [
    'Challenge organizers set their own rules and fees. Registration payments are made directly between participants and organizers through GCash QR code. VITRAX does not process payments and is not responsible for disputes between them.',
  ]),
  LegalSection('Reports, warnings, and suspension', [
    'Users can block and report others. Administrators may warn, suspend, or remove accounts that break these terms or put others at risk.',
  ]),
  LegalSection('Ending your account', [
    'You can delete your account at any time in Edit Profile > Account > Delete my account.',
  ]),
  LegalSection('Limits of responsibility', [
    'To the extent allowed by law, the researchers are not liable for injuries, losses, or damages from using the app or relying on user-submitted information.',
  ]),
  LegalSection('Contact', [
    'Questions about these terms: paseo0396@gmail.com.',
  ]),
];
