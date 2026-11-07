// Chạy: cd src/supabase/functions/send-push && deno test apns_test.ts
// Không dùng thư viện assert ngoài (không thêm dependency) — assert tự viết bên dưới.
import {
  buildApnsHeaders,
  buildApnsPayload,
  classifyApnsResponse,
  createApnsJwt,
  importApnsKey,
  maskToken,
  type NotificationRecord,
  parseWebhookPayload,
  pemToDer,
  timingSafeEqual,
} from "./apns.ts";

function assert(cond: unknown, msg = "assertion failed"): asserts cond {
  if (!cond) throw new Error(msg);
}
function assertEquals(actual: unknown, expected: unknown) {
  const a = JSON.stringify(actual), e = JSON.stringify(expected);
  if (a !== e) throw new Error(`expected ${e}, got ${a}`);
}

const record: NotificationRecord = {
  id: "11111111-1111-1111-1111-111111111111",
  user_id: "22222222-2222-2222-2222-222222222222",
  project_id: "33333333-3333-3333-3333-333333333333",
  type: "doi_gia",
  title: "Dự án A thay đổi giá",
  body: "Giá tham khảo mới: 20–25 triệu/m².",
};

function b64urlDecode(s: string): Uint8Array {
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4);
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

/** Sinh cặp khóa P-256 → PEM PKCS#8 giống file .p8 Apple cấp. */
async function makeP8(): Promise<{ pem: string; publicKey: CryptoKey }> {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  const b64 = btoa(String.fromCharCode(...der)).replace(/(.{64})/g, "$1\n");
  return { pem: `-----BEGIN PRIVATE KEY-----\n${b64}\n-----END PRIVATE KEY-----\n`, publicKey: pair.publicKey };
}

Deno.test("parseWebhookPayload: nhận INSERT notifications", () => {
  const r = parseWebhookPayload({ type: "INSERT", table: "notifications", schema: "public", record, old_record: null });
  assert(r.ok);
  assertEquals(r.record.id, record.id);
});

Deno.test("parseWebhookPayload: từ chối sai type/table/record", () => {
  assert(!parseWebhookPayload({ type: "UPDATE", table: "notifications", record }).ok);
  assert(!parseWebhookPayload({ type: "INSERT", table: "projects", record }).ok);
  assert(!parseWebhookPayload({ type: "INSERT", table: "notifications", record: null }).ok);
  assert(!parseWebhookPayload({ type: "INSERT", table: "notifications", record: { ...record, user_id: "" } }).ok);
  assert(!parseWebhookPayload("chuỗi").ok);
});

Deno.test("buildApnsPayload: alert, sound, thread-id + custom keys", () => {
  assertEquals(buildApnsPayload(record), {
    aps: { alert: { title: record.title, body: record.body }, sound: "default", "thread-id": record.project_id },
    notification_id: record.id,
    project_id: record.project_id,
    type: record.type,
  });
});

Deno.test("buildApnsHeaders: topic, push-type, collapse-id", () => {
  const h = buildApnsHeaders(record, "vn.ancu.app");
  assertEquals(h["apns-topic"], "vn.ancu.app");
  assertEquals(h["apns-push-type"], "alert");
  assertEquals(h["apns-collapse-id"], record.project_id);
});

Deno.test("createApnsJwt: header/claims đúng, chữ ký raw r||s 64 byte verify được", async () => {
  const { pem, publicKey } = await makeP8();
  const key = await importApnsKey(pem);
  const jwt = await createApnsJwt(key, "KEYID12345", "TEAMID1234", 1_700_000_000);
  const [h, c, s] = jwt.split(".");
  assertEquals(JSON.parse(new TextDecoder().decode(b64urlDecode(h))), { alg: "ES256", kid: "KEYID12345" });
  assertEquals(JSON.parse(new TextDecoder().decode(b64urlDecode(c))), { iss: "TEAMID1234", iat: 1_700_000_000 });
  const sig = b64urlDecode(s);
  assertEquals(sig.length, 64);
  const ok = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    publicKey,
    sig,
    new TextEncoder().encode(`${h}.${c}`),
  );
  assert(ok, "chữ ký không verify được");
});

Deno.test("pemToDer: chấp nhận PEM một dòng với \\n dạng chữ", async () => {
  const { pem } = await makeP8();
  const oneLine = pem.replace(/\n/g, "\\n");
  assertEquals(Array.from(pemToDer(oneLine)), Array.from(pemToDer(pem)));
  await importApnsKey(oneLine);
});

Deno.test("classifyApnsResponse", () => {
  assertEquals(classifyApnsResponse(200), "sent");
  assertEquals(classifyApnsResponse(410, "Unregistered"), "remove_token");
  assertEquals(classifyApnsResponse(400, "BadDeviceToken"), "remove_token");
  assertEquals(classifyApnsResponse(400, "Unregistered"), "remove_token");
  assertEquals(classifyApnsResponse(400, "DeviceTokenNotForTopic"), "failed");
  assertEquals(classifyApnsResponse(400, "BadCollapseId"), "failed");
  assertEquals(classifyApnsResponse(403, "ExpiredProviderToken"), "refresh_jwt");
  assertEquals(classifyApnsResponse(403, "InvalidProviderToken"), "refresh_jwt");
  assertEquals(classifyApnsResponse(429, "TooManyRequests"), "retryable");
  assertEquals(classifyApnsResponse(503), "retryable");
});

Deno.test("timingSafeEqual / maskToken", () => {
  assert(timingSafeEqual("abc", "abc"));
  assert(!timingSafeEqual("abc", "abd"));
  assert(!timingSafeEqual("abc", "abcd"));
  assert(!timingSafeEqual("", "x"));
  assertEquals(maskToken("0123456789abcdef"), "0123…cdef");
});
