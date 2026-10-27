// Supabase Edge Function: sends a push notification (Firebase Cloud
// Messaging) to one or more users about a challenge: someone joined, a prize
// was marked paid, a challenge is about to start, or a challenge has ended.
// Called by the database functions in 031_push_triggers.sql; never by the app.
// Reuses FIREBASE_SERVICE_ACCOUNT from send-chat-push and has its own
// CHALLENGE_PUSH_WEBHOOK_SECRET.
import admin from "npm:firebase-admin@12";

const serviceAccountJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
const webhookSecret = Deno.env.get("CHALLENGE_PUSH_WEBHOOK_SECRET");
const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

if (!admin.apps.length && serviceAccountJson) {
  admin.initializeApp({ credential: admin.credential.cert(JSON.parse(serviceAccountJson)) });
}

const headers = { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const json = { "Content-Type": "application/json" };

Deno.serve(async (req) => {
  if (!webhookSecret || req.headers.get("x-webhook-secret") !== webhookSecret) {
    return new Response("Unauthorized", { status: 401 });
  }

  const { user_ids, title, body, challenge_id } = await req.json();
  const ids: string[] = (Array.isArray(user_ids) ? user_ids : []).map(String).filter((id) => UUID.test(id));
  if (ids.length === 0) return new Response(JSON.stringify({ skipped: "no recipients" }), { headers: json });

  const res = await fetch(`${supabaseUrl}/rest/v1/profiles?id=in.(${ids.join(",")})&select=id,fcm_token`, { headers });
  const rows: { id: string; fcm_token: string | null }[] = await res.json();

  const messages = rows
    .filter((r) => r.fcm_token)
    .map((r) => ({
      token: r.fcm_token as string,
      notification: { title: String(title ?? "Vitrax Challenges").slice(0, 80), body: String(body ?? "").slice(0, 200) },
      data: { type: "challenge", challenge_id: String(challenge_id ?? "") },
      android: { priority: "high" as const, notification: { channelId: "vitrax_push", sound: "default" } },
    }));
  if (messages.length === 0) return new Response(JSON.stringify({ skipped: "no device tokens" }), { headers: json });

  try {
    const result = await admin.messaging().sendEach(messages);
    return new Response(JSON.stringify({ sent: result.successCount, failed: result.failureCount }), { headers: json });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: json });
  }
});
