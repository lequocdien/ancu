// Edge Function send-push: Database Webhook (INSERT public.notifications) → APNs.
//
// Gọi từ trigger `notifications_send_push` (migration 20261107000010) qua pg_net.
// - Bảo vệ bằng header `x-webhook-secret` == env PUSH_WEBHOOK_SECRET (verify_jwt = false trong config.toml).
// - Dedupe ≤ 1 thông báo/ngày/dự án/người đã nằm ở trigger fan-out → function KHÔNG dedupe lại.
// - Thiếu APNS_KEY_P8 → dry-run: không gọi APNs, chỉ log và trả số token sẽ gửi.
//
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (runtime cấp sẵn), PUSH_WEBHOOK_SECRET,
//      APNS_KEY_P8, APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID (mặc định vn.ancu.app). Host sandbox/production theo cột push_tokens.environment.

import {
  type ApnsEnv,
  apnsHost,
  buildApnsHeaders,
  buildApnsPayload,
  classifyApnsResponse,
  createApnsJwt,
  importApnsKey,
  maskToken,
  type NotificationRecord,
  parseWebhookPayload,
  timingSafeEqual,
} from "./apns.ts";

// Gọi thẳng PostgREST bằng service role thay vì supabase-js: chỉ cần 2 truy vấn, không phụ thuộc
// tải package từ jsr/npm lúc boot worker (cold start nhanh hơn, không gãy khi registry lỗi).
const REST_URL = `${Deno.env.get("SUPABASE_URL")}/rest/v1`;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

async function rest(method: "GET" | "DELETE", path: string): Promise<unknown> {
  const res = await fetch(`${REST_URL}/${path}`, {
    method,
    headers: { apikey: SERVICE_KEY, authorization: `Bearer ${SERVICE_KEY}` },
  });
  if (!res.ok) throw new Error(`PostgREST ${method} ${path.split("?")[0]} → ${res.status}: ${await res.text()}`);
  return method === "GET" ? res.json() : (await res.body?.cancel(), null);
}

interface DeviceToken {
  token: string;
  environment: ApnsEnv;
}

// Mỗi token tự mang môi trường (app ghi lúc đăng ký: Debug → sandbox, TestFlight/App Store → production).
async function iosTokens(userId: string): Promise<DeviceToken[]> {
  const rows = await rest(
    "GET",
    `push_tokens?select=token,environment&platform=eq.ios&user_id=eq.${encodeURIComponent(userId)}`,
  );
  return (rows as { token: string; environment: string }[]).map((r) => ({
    token: r.token,
    environment: r.environment === "sandbox" ? "sandbox" : "production",
  }));
}

function deleteToken(userId: string, token: string): Promise<unknown> {
  return rest("DELETE", `push_tokens?user_id=eq.${encodeURIComponent(userId)}&token=eq.${encodeURIComponent(token)}`);
}

interface ApnsConfig {
  keyP8: string;
  keyId: string;
  teamId: string;
  bundleId: string;
}

function readApnsConfig(): ApnsConfig | null {
  const keyP8 = Deno.env.get("APNS_KEY_P8");
  if (!keyP8) return null; // → dry-run
  const keyId = Deno.env.get("APNS_KEY_ID");
  const teamId = Deno.env.get("APNS_TEAM_ID");
  if (!keyId || !teamId) throw new Error("Có APNS_KEY_P8 nhưng thiếu APNS_KEY_ID / APNS_TEAM_ID");
  return {
    keyP8,
    keyId,
    teamId,
    bundleId: Deno.env.get("APNS_BUNDLE_ID") || "vn.ancu.app",
  };
}

// APNs: không làm mới JWT quá 1 lần / 20 phút, JWT hết hạn sau 60 phút → cache 50 phút theo worker.
const JWT_TTL_MS = 50 * 60 * 1000;
let cachedKey: CryptoKey | null = null;
let cachedJwt: { token: string; createdAt: number } | null = null;

async function providerToken(cfg: ApnsConfig, forceRefresh = false): Promise<string> {
  if (!forceRefresh && cachedJwt && Date.now() - cachedJwt.createdAt < JWT_TTL_MS) return cachedJwt.token;
  cachedKey ??= await importApnsKey(cfg.keyP8);
  cachedJwt = { token: await createApnsJwt(cachedKey, cfg.keyId, cfg.teamId), createdAt: Date.now() };
  return cachedJwt.token;
}

interface SendResult {
  token: string; // đã che
  status: number;
  reason?: string;
  outcome: ReturnType<typeof classifyApnsResponse>;
}

async function sendOne(cfg: ApnsConfig, n: NotificationRecord, device: DeviceToken): Promise<SendResult> {
  const { token } = device;
  const body = JSON.stringify(buildApnsPayload(n));
  const post = async (jwt: string) => {
    // fetch của Deno thương lượng HTTP/2 qua ALPN — APNs chỉ nhận HTTP/2.
    const res = await fetch(`${apnsHost(device.environment)}/3/device/${token}`, {
      method: "POST",
      headers: { ...buildApnsHeaders(n, cfg.bundleId), authorization: `bearer ${jwt}` },
      body,
    });
    let reason: string | undefined;
    if (res.status !== 200) {
      reason = await res.json().then((j) => j?.reason as string | undefined).catch(() => undefined);
    } else {
      await res.body?.cancel();
    }
    return { status: res.status, reason };
  };

  let r = await post(await providerToken(cfg));
  let outcome = classifyApnsResponse(r.status, r.reason);
  if (outcome === "refresh_jwt") {
    r = await post(await providerToken(cfg, true));
    outcome = classifyApnsResponse(r.status, r.reason);
    if (outcome === "refresh_jwt") outcome = "failed"; // key/team sai — không lặp vô hạn
  }

  if (outcome === "remove_token") {
    await deleteToken(n.user_id, token).catch((e) => console.error("send-push: xóa token lỗi", maskToken(token), String(e)));
  }
  return { token: maskToken(token), status: r.status, reason: r.reason, outcome };
}

function json(status: number, data: unknown): Response {
  return new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method not allowed" });

  const expected = Deno.env.get("PUSH_WEBHOOK_SECRET");
  const given = req.headers.get("x-webhook-secret") ?? "";
  // Không cấu hình secret → từ chối hết (fail closed), tránh endpoint mở khi quên set.
  if (!expected || !timingSafeEqual(given, expected)) return json(401, { error: "unauthorized" });

  let parsed;
  try {
    parsed = parseWebhookPayload(await req.json());
  } catch {
    return json(400, { error: "body không phải JSON" });
  }
  if (!parsed.ok) return json(400, { error: parsed.error });
  const n = parsed.record;

  try {
    const tokens = await iosTokens(n.user_id);

    const cfg = readApnsConfig();
    if (!cfg) {
      console.log(`send-push [dry-run] notification=${n.id} user=${n.user_id} tokens=${tokens.length}`, buildApnsPayload(n));
      return json(200, { dry_run: true, notification_id: n.id, would_send: tokens.length, payload: buildApnsPayload(n) });
    }
    if (tokens.length === 0) return json(200, { notification_id: n.id, sent: 0, results: [] });

    const results = await Promise.all(tokens.map((t) => sendOne(cfg, n, t)));
    const sent = results.filter((r) => r.outcome === "sent").length;
    const failed = results.filter((r) => r.outcome !== "sent" && r.outcome !== "remove_token");
    if (failed.length > 0) console.error(`send-push: notification=${n.id} lỗi`, failed);
    // pg_net không retry → luôn 200 kèm tóm tắt; lỗi chi tiết nằm ở log + net._http_response.
    return json(200, { notification_id: n.id, sent, results });
  } catch (e) {
    console.error("send-push:", e);
    return json(500, { error: e instanceof Error ? e.message : String(e) });
  }
});
