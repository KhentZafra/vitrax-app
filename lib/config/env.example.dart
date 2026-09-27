// Template for env.dart — env.dart itself is gitignored (it holds the
// real project keys), so this checked-in copy is what anyone cloning the
// repo actually sees. To run this project:
//
//   1. Copy this file and rename the copy to `env.dart`, in this same
//      lib/config/ folder.
//   2. Replace the two placeholder values below with your own Supabase
//      project's URL and anon/public key (Supabase Dashboard -> Project
//      Settings -> API).
//   3. Never edit THIS file (env.example.dart) to add real keys — it is
//      the one that gets uploaded to GitHub for everyone to see.
class Env {
  static const supabaseUrl = 'https://YOUR_PROJECT_REF.supabase.co';
  static const supabaseAnonKey = 'YOUR_ANON_PUBLIC_KEY';
  static const orsApiKey = 'YOUR_OPENROUTESERVICE_API_KEY';
}
