// Helper thuần cho send-push: không I/O, không đọc env → test được bằng `deno test`.
// Chỉ dùng Web Crypto + TextEncoder (có sẵn trong Deno / Supabase Edge runtime).

/** Bản ghi `public.notifications` trong payload Database Webhook. */
export interface NotificationRecord {
  id: string;
  user_id: string;
  project_id: string;
  type: string;
  title: string;
  body: string;
  created_at?: string;
  read_at?: string | null;
}

/** Payload Database Webhook (cùng shape với `supabase_functions.http_request`). */
export interface WebhookPayload {
  type: "INSERT" | "UPDATE" | "DELETE";
  table: string;
  schema?: string;
  record: NotificationRecord | null;
  old_record?: unknown;
}

export type ApnsEnv = "sandbox" | "production";

export function apnsHost(env: ApnsEnv): string {
  return env === "production" ? "https://api.push.apple.com" : "https://api.sandbox.push.apple.com";
}

/** Kiểm tra payload webhook; trả về record hợp lệ hoặc thông báo lỗi. */
export function parseWebhookPayload(
  input: unknown,
): { ok: true; record: NotificationRecord } | { ok: false; error: string } {
  if (typeof input !== "object" || input === null) return { ok: false, error: "body không phải JSON object" };
  const p = input as Partial<WebhookPayload>;
  if (p.type !== "INSERT") return { ok: false, error: `type không hỗ trợ: ${String(p.type)}` };
  if (p.table !== "notifications") return { ok: false, error: `table không hỗ trợ: ${String(p.table)}` };
  const r = p.record as Partial<NotificationRecord> | null | undefined;
  if (!r) return { ok: false, error: "thiếu record" };
  for (const key of ["id", "user_id", "project_id", "title", "body"] as const) {
    if (typeof r[key] !== "string" || r[key] === "") return { ok: false, error: `record.${key} không hợp lệ` };
  }
  return { ok: true, record: r as NotificationRecord };
}

/** Payload APNs: alert + custom key để app mở đúng dự án / đánh dấu đã đọc. */
export function buildApnsPayload(n: NotificationRecord): Record<string, unknown> {
  return {
    aps: {
      alert: { title: n.title, body: n.body },
      sound: "default",
      "thread-id": n.project_id,
    },
    notification_id: n.id,
    project_id: n.project_id,
    type: n.type,
  };
}

/** Header APNs cho một thông báo (chưa gồm authorization). */
export function buildApnsHeaders(n: NotificationRecord, bundleId: string): Record<string, string> {
  return {
    "apns-topic": bundleId,
    "apns-push-type": "alert",
    "apns-priority": "10",
    // Gộp các push cùng dự án trên máy: chỉ hiện bản mới nhất (≤ 64 byte, uuid = 36).
    "apns-collapse-id": n.project_id,
    "content-type": "application/json",
  };
}

// ───── JWT ES256 (token-based auth) ─────

function base64UrlEncode(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64UrlEncodeJson(value: unknown): string {
  return base64UrlEncode(new TextEncoder().encode(JSON.stringify(value)));
}

/**
 * Nội dung file .p8 (PEM PKCS#8) → DER. Chấp nhận cả khi secret bị lưu một dòng
 * với `\n` dạng chữ (thường gặp khi `supabase secrets set`).
 */
export function pemToDer(pem: string): Uint8Array {
  const b64 = pem
    .replace(/\\n/g, "\n")
    .replace(/-----BEGIN [^-]+-----/, "")
    .replace(/-----END [^-]+-----/, "")
    .replace(/[^A-Za-z0-9+/=]/g, "");
  if (b64.length === 0) throw new Error("APNS_KEY_P8 rỗng hoặc sai định dạng PEM");
  const bin = atob(b64);
  const der = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) der[i] = bin.charCodeAt(i);
  return der;
}

export function importApnsKey(pem: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "pkcs8",
    pemToDer(pem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

/**
 * JWT provider token cho APNs. WebCrypto trả chữ ký ECDSA dạng raw r||s (64 byte)
 * — đúng định dạng JWS yêu cầu, không phải DER như OpenSSL.
 */
export async function createApnsJwt(
  key: CryptoKey,
  keyId: string,
  teamId: string,
  issuedAtSeconds: number = Math.floor(Date.now() / 1000),
): Promise<string> {
  const signingInput = `${base64UrlEncodeJson({ alg: "ES256", kid: keyId })}.${
    base64UrlEncodeJson({ iss: teamId, iat: issuedAtSeconds })
  }`;
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64UrlEncode(new Uint8Array(sig))}`;
}

// ───── Phân loại phản hồi APNs ─────

export type ApnsOutcome =
  /** Đã gửi. */
  | "sent"
  /** Token chết/không hợp lệ → xóa khỏi push_tokens. */
  | "remove_token"
  /** JWT hết hạn / sai → làm mới JWT và thử lại một lần. */
  | "refresh_jwt"
  /** Lỗi tạm thời (429, 5xx) — có thể thử lại sau. */
  | "retryable"
  /** Lỗi khác (payload, cấu hình topic…) — log, không xóa token. */
  | "failed";

/** https://developer.apple.com/documentation/usernotifications/handling-notification-responses-from-apns */
export function classifyApnsResponse(status: number, reason?: string | null): ApnsOutcome {
  if (status === 200) return "sent";
  if (status === 410) return "remove_token"; // Unregistered / ExpiredToken
  if (status === 400 && (reason === "BadDeviceToken" || reason === "Unregistered")) return "remove_token";
  if (status === 403 && (reason === "ExpiredProviderToken" || reason === "InvalidProviderToken")) return "refresh_jwt";
  if (status === 429 || status >= 500) return "retryable";
  return "failed";
}

// ───── Tiện ích ─────

/** So sánh chuỗi thời gian hằng (tránh timing attack khi kiểm tra webhook secret). */
export function timingSafeEqual(a: string, b: string): boolean {
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  let diff = ea.length ^ eb.length;
  const len = Math.max(ea.length, eb.length);
  for (let i = 0; i < len; i++) diff |= (ea[i] ?? 0) ^ (eb[i] ?? 0);
  return diff === 0;
}

/** Che token khi log (dữ liệu định danh thiết bị). */
export function maskToken(token: string): string {
  return token.length <= 8 ? "****" : `${token.slice(0, 4)}…${token.slice(-4)}`;
}
