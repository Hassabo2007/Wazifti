import webpush from "npm:web-push@3.6.7";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "apikey, authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}
function equalConstantTime(a: string, b: string) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
function serverSecrets(): string[] {
  try {
    const values = Object.values(JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") || "{}"));
    return values.filter((v): v is string => typeof v === "string" && v.length > 0);
  } catch { return []; }
}
async function authorized(req: Request, base: string, serviceKey: string): Promise<boolean> {
  // Scheduled calls use a random token stored in Supabase Vault; never log or expose it.
  const cronToken = req.headers.get("x-wazifti-cron-token") || "";
  if (cronToken) {
    try {
      const verifyResponse = await fetch(`${base}/rest/v1/rpc/verify_job_alert_cron_token`, {
        method: "POST",
        headers: restHeaders(serviceKey),
        body: JSON.stringify({ p_token: cronToken }),
      });
      if (verifyResponse.ok && await verifyResponse.json() === true) return true;
    } catch {
      // Fall through to the existing secret-key / authenticated-admin checks.
    }
  }
  const apiKey = req.headers.get("apikey") || "";
  const auth = req.headers.get("authorization") || "";
  const bearer = auth.toLowerCase().startsWith("bearer ") ? auth.slice(7).trim() : "";
  const candidates = [...serverSecrets(), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || ""].filter(Boolean);
  if (candidates.some(secret => equalConstantTime(apiKey, secret) && equalConstantTime(bearer, secret))) return true;

  // Browser invocation is allowed only for a currently authenticated Wazifti admin.
  // The publishable key is not a credential; the user's JWT and admin_users membership are both verified.
  let publishableKeys: string[] = [];
  try {
    publishableKeys = Object.values(JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") || "{}"))
      .filter((v): v is string => typeof v === "string" && v.length > 0);
  } catch { publishableKeys = []; }
  const legacyAnon = Deno.env.get("SUPABASE_ANON_KEY") || "";
  if (legacyAnon) publishableKeys.push(legacyAnon);
  if (!bearer || !publishableKeys.some(key => equalConstantTime(apiKey, key))) return false;

  const userResponse = await fetch(`${base}/auth/v1/user`, {
    headers: { apikey: apiKey, Authorization: `Bearer ${bearer}` },
  });
  if (!userResponse.ok) return false;
  const user = await userResponse.json();
  if (!user?.id) return false;

  const adminResponse = await fetch(
    `${base}/rest/v1/admin_users?user_id=eq.${encodeURIComponent(user.id)}&select=user_id`,
    { headers: restHeaders(serviceKey) },
  );
  if (!adminResponse.ok) return false;
  const admins = await adminResponse.json();
  return Array.isArray(admins) && admins.some((row: { user_id?: string }) => row.user_id === user.id);
}
function restHeaders(key: string) {
  return { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const url = Deno.env.get("SUPABASE_URL");
  const key = serverSecrets()[0] || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) return json({ error: "Worker configuration is incomplete" }, 500);
  const base = url.replace(/\/$/, "");
  if (!(await authorized(req, base, key))) return json({ error: "Unauthorized" }, 401);

  let limit = 10;
  try {
    const body = await req.json().catch(() => ({}));
    if (typeof body?.limit === "number") limit = Math.min(25, Math.max(1, Math.trunc(body.limit)));
  } catch { return json({ error: "Invalid JSON body" }, 400); }

  const headers = restHeaders(key);
  try {
    const processResponse = await fetch(`${base}/rest/v1/rpc/process_job_alert_outbox`, {
      method: "POST", headers, body: JSON.stringify({ p_limit: limit }),
    });
    if (!processResponse.ok) {
      console.error("Job alert outbox RPC failed", processResponse.status, (await processResponse.text()).slice(0, 400));
      return json({ error: "Job alert processing failed" }, 502);
    }
    const processing = await processResponse.json();

    const vaultConfigResponse = await fetch(`${base}/rest/v1/rpc/get_job_alert_vapid_config`, {
      method: "POST", headers, body: "{}",
    });
    const vaultConfig = vaultConfigResponse.ok ? await vaultConfigResponse.json() : {};
    const publicKey = Deno.env.get("VAPID_PUBLIC_KEY") || vaultConfig?.public_key;
    const privateKey = Deno.env.get("VAPID_PRIVATE_KEY") || vaultConfig?.private_key;
    const subject = Deno.env.get("VAPID_SUBJECT") || vaultConfig?.subject;
    if (!publicKey || !privateKey || !subject) {
      return json({ ok: true, processing, push: { queued: processing?.push_deliveries_queued || 0, sent: 0, configuration_missing: true } });
    }
    webpush.setVapidDetails(subject, publicKey, privateKey);

    const claimResponse = await fetch(`${base}/rest/v1/rpc/claim_job_alert_push_deliveries`, {
      method: "POST", headers, body: JSON.stringify({ p_limit: Math.min(limit * 2, 50) }),
    });
    if (!claimResponse.ok) {
      console.error("Push delivery claim failed", claimResponse.status, (await claimResponse.text()).slice(0, 400));
      return json({ ok: true, processing, push: { error: "Could not claim push deliveries" } }, 207);
    }
    const deliveries = await claimResponse.json() as Array<{
      delivery_id: string; notification_id: string; user_id: string; job_title: string; job_location: string | null; job_id: string | null;
    }>;

    let sent = 0, failed = 0, skipped = 0;
    for (const item of deliveries || []) {
      try {
        const subResponse = await fetch(
          `${base}/rest/v1/push_subscriptions?user_id=eq.${encodeURIComponent(item.user_id)}&select=id,subscription`,
          { headers },
        );
        if (!subResponse.ok) throw new Error("Could not load push subscriptions");
        const subscriptions = await subResponse.json() as Array<{ id: string; subscription: webpush.PushSubscription }>;
        if (!subscriptions.length) {
          await fetch(`${base}/rest/v1/job_alert_deliveries?id=eq.${item.delivery_id}`, {
            method: "PATCH", headers: { ...headers, Prefer: "return=minimal" },
            body: JSON.stringify({ status: "skipped", last_error: "No active device subscription" }),
          });
          skipped++;
          continue;
        }
        const payload = JSON.stringify({
          title: "فرصة عمل جديدة على وظيفتي",
          body: ` ${String(item.job_title || "وظيفة جديدة").slice(0, 100)}${item.job_location ? " • " + String(item.job_location).slice(0, 60) : ""}`,
          url: item.job_id ? `/#job-${item.job_id}` : "/",
          tag: `wazifti-job-alert-${item.notification_id}`,
        });
        let deviceSent = 0;
        for (const sub of subscriptions) {
          try {
            await webpush.sendNotification(sub.subscription, payload, { TTL: 3600 });
            deviceSent++;
          } catch (error) {
            const code = (error as { statusCode?: number }).statusCode;
            if (code === 404 || code === 410) {
              await fetch(`${base}/rest/v1/push_subscriptions?id=eq.${sub.id}`, {
                method: "DELETE", headers: { ...headers, Prefer: "return=minimal" },
              });
            }
            console.error("Job alert push failed", code || "unknown");
          }
        }
        const status = deviceSent ? "sent" : "failed";
        await fetch(`${base}/rest/v1/job_alert_deliveries?id=eq.${item.delivery_id}`, {
          method: "PATCH", headers: { ...headers, Prefer: "return=minimal" },
          body: JSON.stringify({ status, sent_at: deviceSent ? new Date().toISOString() : null, last_error: deviceSent ? null : "Push delivery failed" }),
        });
        if (deviceSent) sent++; else failed++;
      } catch (error) {
        console.error("Push delivery processing failed", error);
        await fetch(`${base}/rest/v1/job_alert_deliveries?id=eq.${item.delivery_id}`, {
          method: "PATCH", headers: { ...headers, Prefer: "return=minimal" },
          body: JSON.stringify({ status: "failed", last_error: String((error as Error).message || "Delivery failed").slice(0, 500) }),
        });
        failed++;
      }
    }
    return json({ ok: true, processing, push: { claimed: deliveries?.length || 0, sent, failed, skipped } });
  } catch (error) {
    console.error("process-job-alerts failed", error);
    return json({ error: "Worker could not complete the job alert run" }, 502);
  }
});
