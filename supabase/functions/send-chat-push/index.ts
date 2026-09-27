// Supabase Edge Function: sends a real push notification (via Firebase
// Cloud Messaging) to the OTHER person in a conversation whenever a new
// chat message is inserted. Never called by the app directly — it's
// triggered by the Postgres trigger in 021_chat_push.sql the instant a
// row lands in `messages`.
//
// Guarded by a shared secret header (x-webhook-secret) so nobody else on
// the internet can call this URL to spam pushes to your users — the
// trigger sends the same secret you set below as a function secret.
import admin from "npm:firebase-admin@12";

const serviceAccountJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
const webhookSecret = Deno.env.get("CHAT_PUSH_WEBHOOK_SECRET");
const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

if (!admin.apps.length && serviceAccountJson) {
  admin.initializeApp({
    credential: admin.credential.cert(JSON.parse(serviceAccountJson)),
  });
}

Deno.serve(async (req) => {
  if (req.headers.get("x-webhook-secret") !== webhookSecret) {
    return new Response("Unauthorized", { status: 401 });
  }

  const payload = await req.json();
  const { conversation_id, sender_id, body } = payload;

  // Everyone else in this conversation (not the sender) plus their FCM
  // token, via Supabase's REST API using the service role key — this
  // runs server-side and is trusted, so it deliberately bypasses RLS
  // rather than trying to act as any particular user.
  const participantsRes = await fetch(
    `${supabaseUrl}/rest/v1/conversation_participants?conversation_id=eq.${conversation_id}&user_id=neq.${sender_id}&select=user_id,profiles(fcm_token)`,
    { headers: { apikey: supabaseServiceRoleKey, Authorization: `Bearer ${supabaseServiceRoleKey}` } },
  );
  const participants = await participantsRes.json();

  const senderRes = await fetch(
    `${supabaseUrl}/rest/v1/profiles?id=eq.${sender_id}&select=first_name,last_name`,
    { headers: { apikey: supabaseServiceRoleKey, Authorization: `Bearer ${supabaseServiceRoleKey}` } },
  );
  const [sender] = await senderRes.json();
  const senderName = [sender?.first_name, sender?.last_name].filter(Boolean).join(" ").trim() || "A Vitrax user";

  const results = [];
  for (const p of participants) {
    const token = p.profiles?.fcm_token;
    if (!token) continue; // that person has no registered device — nothing to push to
    try {
      const messageId = await admin.messaging().send({
        token,
        notification: { title: senderName, body: String(body).slice(0, 200) },
        data: { type: "chat_message", conversation_id: String(conversation_id) },
      });
      results.push({ user_id: p.user_id, messageId });
    } catch (e) {
      results.push({ user_id: p.user_id, error: String(e) });
    }
  }

  return new Response(JSON.stringify({ results }), { headers: { "Content-Type": "application/json" } });
});