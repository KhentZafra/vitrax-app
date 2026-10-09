// Supabase Edge Function: sends a push notification (Firebase Cloud
// Messaging) to the owner of a feed post when someone likes, comments on,
// replies to, or reshares it. Called by the Postgres trigger in
// 016_feed_push.sql each time a row lands in `feed_notifications`.
// Reuses FIREBASE_SERVICE_ACCOUNT from send-chat-push; has its own
// FEED_PUSH_WEBHOOK_SECRET so chat push is untouched.
import admin from "npm:firebase-admin@12";

const serviceAccountJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
const webhookSecret = Deno.env.get("FEED_PUSH_WEBHOOK_SECRET");
const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

if (!admin.apps.length && serviceAccountJson) {
  admin.initializeApp({ credential: admin.credential.cert(JSON.parse(serviceAccountJson)) });
}

const headers = { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` };

const ACTIONS: Record<string, string> = {
  like: "liked your post",
  comment: "commented on your post",
  reply: "replied to your comment",
  reshare: "reshared your post",
};

Deno.serve(async (req) => {
  if (req.headers.get("x-webhook-secret") !== webhookSecret) {
    return new Response("Unauthorized", { status: 401 });
  }

  const { user_id, actor_id, type, post_kind, post_id, body } = await req.json();

  const [recipientRes, actorRes] = await Promise.all([
    fetch(`${supabaseUrl}/rest/v1/profiles?id=eq.${user_id}&select=fcm_token`, { headers }),
    fetch(`${supabaseUrl}/rest/v1/profiles?id=eq.${actor_id}&select=first_name,last_name`, { headers }),
  ]);
  const [recipient] = await recipientRes.json();
  const [actor] = await actorRes.json();

  const token = recipient?.fcm_token;
  if (!token) return new Response(JSON.stringify({ skipped: "no device token" }), { headers: { "Content-Type": "application/json" } });

  const actorName = [actor?.first_name, actor?.last_name].filter(Boolean).join(" ").trim() || "Someone";
  const action = ACTIONS[type] ?? "interacted with your post";
  const text = body ? `${actorName} ${action}: "${String(body).slice(0, 120)}"` : `${actorName} ${action}.`;

  try {
    const messageId = await admin.messaging().send({
      token,
      notification: { title: "Vitrax Community", body: text },
      data: { type: "feed_notification", notification_type: String(type), post_kind: String(post_kind), post_id: String(post_id) },
    });
    return new Response(JSON.stringify({ messageId }), { headers: { "Content-Type": "application/json" } });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
});
