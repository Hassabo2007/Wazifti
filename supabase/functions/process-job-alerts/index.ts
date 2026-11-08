const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "apikey, authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) {
    mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return mismatch === 0;
}

function getSecretKeys(): string[] {
  const raw = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw) as Record<string, unknown>;
    return Object.values(parsed).filter(
      (value): value is string => typeof value === "string" && value.length > 0,
    );
  } catch {
    return [];
  }
}

function authorize(req: Request):
  | { ok: true; apiKey: string; authorization?: string }
  | { ok: false } {
  const incomingApiKey = req.headers.get("apikey") ?? "";
  const bearer = req.headers.get("authorization") ?? "";
  const legacyServiceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  for (const secret of getSecretKeys()) {
    if (constantTimeEqual(incomingApiKey, secret)) {
      return { ok: true, apiKey: secret };
    }
  }

  if (
    legacyServiceRole &&
    bearer.toLowerCase().startsWith("bearer ") &&
    constantTimeEqual(bearer.slice(7).trim(), legacyServiceRole)
  ) {
    return {
      ok: true,
      apiKey: legacyServiceRole,
      authorization: `Bearer ${legacyServiceRole}`,
    };
  }

  return { ok: false };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const credentials = authorize(req);
  if (!credentials.ok) {
    return json({ error: "Unauthorized" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  if (!supabaseUrl) {
    return json({ error: "Worker configuration is incomplete" }, 500);
  }

  let requestedLimit = 10;
  try {
    const body = await req.json().catch(() => ({}));
    if (body && typeof body.limit === "number") {
      requestedLimit = Math.trunc(body.limit);
    }
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }
  const limit = Math.min(25, Math.max(1, requestedLimit));

  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    apikey: credentials.apiKey,
  };
  if (credentials.authorization) {
    headers.Authorization = credentials.authorization;
  }

  try {
    const response = await fetch(
      `${supabaseUrl.replace(/\/$/, "")}/rest/v1/rpc/process_job_alert_outbox`,
      {
        method: "POST",
        headers,
        body: JSON.stringify({ p_limit: limit }),
      },
    );

    const responseText = await response.text();
    if (!response.ok) {
      console.error("Job alert RPC failed", response.status, responseText.slice(0, 500));
      return json({ error: "Job alert processing failed" }, 502);
    }

    let result: unknown;
    try {
      result = JSON.parse(responseText);
    } catch {
      result = { message: "Worker completed; response was not JSON" };
    }
    return json({ ok: true, result });
  } catch (error) {
    console.error("Job alert worker request failed", error);
    return json({ error: "Worker could not reach the database" }, 502);
  }
});
