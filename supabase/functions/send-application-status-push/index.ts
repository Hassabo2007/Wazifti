import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://wazifti.vercel.app",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};

const allowedStatuses = new Set(["submitted", "reviewing", "shortlisted", "rejected", "accepted"]);
const labels: Record<string, string> = {
  submitted: "تم استلام الطلب",
  reviewing: "قيد المراجعة",
  shortlisted: "ضمن القائمة المختصرة",
  rejected: "لم يتم الاختيار",
  accepted: "تم القبول",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const authHeader = req.headers.get("Authorization") || "";
    const token = authHeader.replace(/^Bearer\s+/i, "");
    if (!token) return json({ error: "Authentication required" }, 401);

    const url = Deno.env.get("SUPABASE_URL");
    const publishableKeys = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") || "{}");
    const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") || "{}");
    const publishableKey = publishableKeys.default || Deno.env.get("SUPABASE_ANON_KEY");
    const secretKey = secretKeys.default || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !publishableKey || !secretKey) throw new Error("Supabase server configuration is incomplete");

    const userClient = createClient(url, publishableKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: authData, error: authError } = await userClient.auth.getUser(token);
    if (authError || !authData.user) return json({ error: "Invalid session" }, 401);

    const body = await req.json();
    const applicationId = typeof body.applicationId === "string" ? body.applicationId : "";
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(applicationId)) {
      return json({ error: "Invalid application ID" }, 400);
    }

    const admin = createClient(url, secretKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: app, error: appError } = await admin
      .from("applications")
      .select("id, candidate_id, job_id, status")
      .eq("id", applicationId)
      .maybeSingle();
    if (appError) throw appError;
    if (!app) return json({ error: "Application not found" }, 404);
    if (!allowedStatuses.has(app.status)) return json({ error: "Unsupported status" }, 400);

    const { data: job, error: jobError } = await admin
      .from("jobs")
      .select("id, title, company_id")
      .eq("id", app.job_id)
      .maybeSingle();
    if (jobError) throw jobError;
    if (!job) return json({ error: "Job not found" }, 404);

    const { data: company, error: companyError } = await admin
      .from("companies")
      .select("owner_id")
      .eq("id", job.company_id)
      .maybeSingle();
    if (companyError) throw companyError;
    if (!company || company.owner_id !== authData.user.id) {
      return json({ error: "Not authorized to notify this applicant" }, 403);
    }

    const { data: subscriptions, error: subscriptionsError } = await admin
      .from("push_subscriptions")
      .select("id, subscription")
      .eq("user_id", app.candidate_id);
    if (subscriptionsError) throw subscriptionsError;
    if (!subscriptions?.length) return json({ sent: 0, reason: "No active subscriptions" });

    const publicKey = Deno.env.get("VAPID_PUBLIC_KEY");
    const privateKey = Deno.env.get("VAPID_PRIVATE_KEY");
    const subject = Deno.env.get("VAPID_SUBJECT");
    if (!publicKey || !privateKey || !subject) throw new Error("VAPID secrets are not configured");
    webpush.setVapidDetails(subject, publicKey, privateKey);

    const { data: claim, error: claimError } = await admin
      .from("push_notification_events")
      .insert({ application_id: app.id, status: app.status })
      .select("id")
      .maybeSingle();
    if (claimError?.code === "23505") return json({ sent: 0, reason: "Already notified for this status" });
    if (claimError) throw claimError;
    if (!claim) return json({ sent: 0, reason: "Notification already processed" });

    const payload = JSON.stringify({
      title: "تحديث على طلب التقديم",
      body: `تم تحديث حالة طلبك لوظيفة «${String(job.title || "وظيفة").slice(0, 100)}»: ${labels[app.status]}.`,
      url: "/",
      tag: `wazifti-application-${app.id}-${app.status}`,
    });

    let sent = 0;
    const results = await Promise.all(subscriptions.map(async (row: { id: string; subscription: unknown }) => {
      try {
        await webpush.sendNotification(row.subscription as webpush.PushSubscription, payload, { TTL: 3600 });
        sent++;
      } catch (error) {
        const statusCode = (error as { statusCode?: number }).statusCode;
        if (statusCode === 404 || statusCode === 410) {
          await admin.from("push_subscriptions").delete().eq("id", row.id);
        }
        console.error("Push delivery failed:", statusCode || "unknown", (error as Error).message);
      }
    }));

    if (sent === 0) {
      await admin.from("push_notification_events").delete().eq("id", claim.id);
      return json({ sent: 0, reason: "Delivery failed" }, 502);
    }
    return json({ sent, total: subscriptions.length });
  } catch (error) {
    console.error("send-application-status-push failed:", error);
    return json({ error: (error as Error).message || "Internal server error" }, 500);
  }
});
