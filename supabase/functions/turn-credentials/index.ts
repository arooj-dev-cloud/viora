const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authorization = request.headers.get("Authorization");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!authorization?.startsWith("Bearer ") || !supabaseUrl || !anonKey) {
    return json({ error: "Authentication required" }, 401);
  }

  // Validate the caller through Supabase Auth; never trust decoded JWT claims.
  const identity = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: { Authorization: authorization, apikey: anonKey },
  });
  if (!identity.ok) return json({ error: "Authentication required" }, 401);
  const user = await identity.json();
  if (typeof user.id !== "string") return json({ error: "Authentication required" }, 401);

  const urls = (Deno.env.get("TURN_URLS") ?? "")
    .split(",")
    .map((url) => url.trim())
    .filter(Boolean);
  const secret = Deno.env.get("TURN_SECRET");
  if (urls.length === 0 || !secret) {
    return json({ error: "TURN service is not configured" }, 503);
  }

  const configuredTtl = Number(Deno.env.get("TURN_TTL_SECONDS") ?? "3600");
  const ttl = Number.isFinite(configuredTtl)
    ? Math.min(Math.max(configuredTtl, 300), 86400)
    : 3600;
  const username = `${Math.floor(Date.now() / 1000) + ttl}:${user.id}`;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-1" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(username));
  const credential = btoa(String.fromCharCode(...new Uint8Array(signature)));

  return json({
    iceServers: [
      { urls: "stun:stun.l.google.com:19302" },
      { urls, username, credential },
    ],
  });
});
