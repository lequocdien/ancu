# An Cư — Supabase

Schema PostGIS, RLS, RPC và trigger cho backend. Trạng thái: **chạy local 2026-11-07** (Supabase CLI 3.0.0, Postgres 17) — 11 migration + 2 seed, `db reset` sạch, pgTAP 64/64 (4 file), lint `public` sạch. App iOS nối toàn bộ (integration test gọi PostgREST thật). Rà soát bảo mật: `docs/02-specs/security-review.md`.

Quyết định 2026-11-07: ở lại Supabase lâu dài; logic nghiệp vụ ưu tiên SQL function/trigger để giảm lock-in (`docs/02-specs/architecture.md` mục 5.0).

## Cấu trúc

| File | Nội dung |
| --- | --- |
| `migrations/…01_extensions_lookup.sql` | PostGIS, unaccent, `normalize_search`, `lookup_items`, `administrative_units` |
| `migrations/…02_core_tables.sql` | projects, routes, nodes, nearest infra, bookmarks, project_updates, notifications, push_tokens, data_reports, eligibility_rules, app_config |
| `migrations/…03_rls.sql` | RLS: khách đọc dữ liệu công khai; người dùng chỉ dữ liệu của mình |
| `migrations/…04_functions.sql` | RPC (contract với app) + trigger (profile, lịch sử, fan-out thông báo, ga gần nhất) |
| `migrations/…05_administrative_units_rpc.sql` | RPC `administrative_units_all()` |
| `migrations/…06_client_config.sql` | RPC `client_config(platform)` — `min_supported_version` (force update) |
| `migrations/…07_user_rpcs.sql` | Bookmark RPC, `report_data` có giới hạn 10/24h (mã `AC429`), push token + cột `environment` |
| `migrations/…08_analytics.sql` | `analytics_events` (chỉ ghi qua `track_events`), view retention tuần + phễu 28 ngày |
| `migrations/…09_notification_prefs.sql` | `profiles.notification_prefs`, RPC đọc/ghi, fan-out bỏ loại người dùng đã tắt |
| `migrations/…12_service_area_boundaries.sql` | Bảng `service_area_boundaries` (MultiPolygon), RPC `service_area_boundary(code, tolerance_degrees)` |
| `migrations/…13_saved_places.sql` | Địa điểm riêng `saved_places` (chỉ vùng MVP ± 3 km, ≤ 200/người, ghi chỉ qua RPC), `bookmarks.note`, `data_reports.kind` (đề xuất thêm dự án), danh mục `place_kinds` (chèn ngay trong migration — cloud không chạy seed). Mã lỗi `AC403` ngoài vùng, `AC409` vượt số lượng |
| `migrations/…14_saved_place_icons.sql` | Danh mục `place_icons` (16 icon, mã + `sf_symbol`, chèn trong migration), cột `saved_places.icon` (FK danh mục, null = icon theo loại). `create_saved_place` / `update_saved_place` thêm tham số `icon` (bỏ chữ ký cũ để PostgREST không mơ hồ) |
| `migrations/…15_route_type_colors.sql` | Màu tuyến theo loại trong `route_types`: Metro `#2563EB`, Cao tốc `#DB2777` (Vành đai, Quốc lộ giữ nguyên). App vẽ mọi tuyến cùng loại một màu |
| `migrations/…11_security_hardening.sql` | Chặn ghi thẳng `data_reports` (né rate limit); trần 2.000 sự kiện analytics/24h/install |
| `templates/otp.html` | Email mã đăng nhập 6 số (`{{ .Token }}`) |
| `seed.sql` | **Sinh tự động** — tuyến/nút/dự án gốc từ `src/data/geojson/` (xem bên dưới) |
| `tests/database/ancu.test.sql` | pgTAP: RLS, RPC, trigger (27 test) |
| `tests/database/user_rpcs.test.sql` | pgTAP: bookmark, báo sai + rate limit, push token, tùy chọn thông báo (19 test) |
| `tests/database/analytics.test.sql` | pgTAP: analytics chỉ ghi, đầu vào xấu bị bỏ cả lô (9 test) |
| `migrations/…10_push_webhook.sql` | Trigger `notifications_send_push`: INSERT `notifications` → `net.http_post` tới Edge Function `send-push` (URL + secret đọc từ Vault) |
| `functions/send-push/` | Edge Function → APNs (HTTP/2, JWT ES256). `apns.ts` = helper thuần, `apns_test.ts` = Deno test |
| `seeds/push_webhook_local.sql` | **Chỉ local**: Vault `send_push_url` / `send_push_webhook_secret` (nạp khi `db reset`) |
| `tests/database/push.test.sql` | pgTAP: trigger push không bao giờ làm hỏng INSERT |

**Nguồn seed**: `src/data/geojson/*.geojson` → `python3 -I src/data/scripts/build_data.py` (validate, ghi mock JSON của app, rồi gọi `scripts/generate_seed.py`) → `seed.sql`. Sửa dữ liệu tuyến/nút/dự án ở GeoJSON, không sửa mock JSON hay `seed.sql`; danh mục vẫn ở `Lookup/*.json` của app. Contract GeoJSON: `src/data/README.md`.

Danh mục là bảng `lookup_items` (không phải Postgres enum): thêm trạng thái mới = insert, không migration. FK tới danh mục qua cột generated hằng số (`status_category`).

## Contract RPC ↔ app

RPC trả JSON **đúng shape mock JSON** (`location: {lat, lng}`, ngày `YYYY-MM-DD`, snake_case) → `Supabase*Repository` dùng lại DTO/mapper của `Data/Mock`.

| Protocol (app) | RPC |
| --- | --- |
| `ProjectRepository.projects(in:filter:)` | `projects_in_bbox(min_lng, min_lat, max_lng, max_lat, statuses, service_areas)` |
| `ProjectRepository.projects(ids:)` | `projects_by_ids(ids)` |
| `ProjectRepository.project(id:)` | `project_detail(project_id)` — không có → P0002 (404 → `.notFound`) |
| `ProjectRepository.search(_:)` | `search_places(q)` → `{projects, places}` |
| `InfrastructureRepository.routes(types:)` / `nodes(routeID:)` | `routes(types, tolerance_degrees)` / `route_nodes(route)` |
| `LookupRepository.catalog()` / `administrativeUnits()` / `boundary(of:)` | `lookup_catalog()` / `administrative_units_all()` / `service_area_boundary(code, tolerance_degrees)` |
| `BookmarkRepository` | `my_bookmarks()` (kèm `note`), `toggle_bookmark(project_id)`, `set_bookmark_notify(project_id, enabled)`, `set_bookmark_note(project_id, note)`, `merge_guest_bookmarks(project_ids)` — khách lưu trên máy |
| `SavedPlaceRepository` | `my_saved_places()`, `create_saved_place(name, lat, lng, kind, address, note, external_ref, icon)` → `AC403`/`AC409`, `update_saved_place(id, name, kind, note, icon)`, `delete_saved_place(id)` — bắt buộc đăng nhập |
| `NotificationRepository` | `inbox()`, `mark_notification_read(notification_id)`, `my_notification_prefs()`, `set_notification_prefs(prefs)` |
| `EligibilityRepository.currentRules()` | `eligibility_rules_current()` |
| `DataReportRepository` | `report_data(project_id, note)`, `suggest_project(name, lat, lng, address)` — chung giới hạn 10/24h |
| `AuthService` | Supabase Auth (email OTP, Apple id token, Google/Facebook OAuth) + `current_profile()` / `delete_my_account()` |
| `ConfigRepository` | `client_config(platform)` |
| `PushTokenRepository` | `register_push_token(token, environment)`, `unregister_push_token(token)` |
| `AnalyticsSink` | `track_events(install_id, app_version, os_version, events)` |

## Chạy local

Cần Docker Desktop + Supabase CLI (`brew install supabase/tap/supabase`).

```bash
cd src
supabase init          # lần đầu: chỉ tạo supabase/config.toml, không đụng migrations
supabase start         # chạy migrations + seed.sql
supabase test db       # pgTAP
supabase db lint --schema public   # bỏ --schema sẽ báo lỗi giả trong hàm nội bộ PostGIS (schema extensions)
```

## Triển khai cloud

Project: `ancu` (`minfsjbwcmxgoqiptjka`, **Mumbai `ap-south-1`** — tạm cho dev, sẽ tạo lại ở Singapore, xem tasks.md; gói Free). Tạo project mới luôn chỉ định region cụ thể (`--region ap-southeast-1`), không dùng "auto". ⚠️ CLI 3.x: `db push`, `db lint`, `migration list` **mặc định nhắm stack local** — phải thêm `--remote` (`--linked` đã deprecated). Luôn đọc dòng `Target:` đầu output.

```bash
cd src
supabase login && supabase link --project-ref <ref>     # một lần
supabase db push --remote --dry-run                    # xem trước
supabase db push --remote                              # KHÔNG --include-seed (sẽ ghi Vault local lên cloud)
supabase migration list --remote
supabase db lint --remote --schema public
# Dữ liệu mock (chỉ chạy MỘT lần — INSERT không có on conflict): connection string Session pooler (IPv4)
psql "$(cat supabase/.temp/pooler-url)" -v ON_ERROR_STOP=1 -f supabase/seed.sql   # URL pooler do `link` lưu sẵn; psql hỏi mật khẩu DB
```

Làm tay trên dashboard (`config.toml` chỉ áp dụng local, không `config push` vì `site_url` là localhost):
- Authentication → URL Configuration: thêm redirect `ancu://login-callback`.
- Email Templates **Magic Link** + **Confirm signup**: nội dung `templates/otp.html` (có `{{ .Token }}`) — mặc định cloud gửi link, app cần mã. Email OTP Length = 6.
- SMTP mặc định chỉ gửi tới email thành viên organization, ~2 email/giờ → cần SMTP riêng trước khi cho người ngoài dùng.

## Push (APNs)

```text
project_updates ─fan-out (dedupe ≤1/ngày/dự án)─► notifications ─trigger + pg_net─► send-push ─HTTP/2─► APNs
```

- Function **không** dedupe (đã làm ở `fan_out_project_update`). Gửi lỗi không retry; xem log function và `net._http_response`.
- APNs 410 / 400 `BadDeviceToken`|`Unregistered` → xóa token trong `push_tokens`. 403 JWT hết hạn → làm mới JWT, thử lại 1 lần.
- Thiếu `APNS_KEY_P8` → **dry-run**: không gọi APNs, trả `{dry_run: true, would_send: <số token>}`.
- Endpoint `verify_jwt = false`, bảo vệ bằng header `x-webhook-secret` == env `PUSH_WEBHOOK_SECRET` (thiếu env → 401 hết).

Local: không cần làm gì — `config.toml` đặt `PUSH_WEBHOOK_SECRET`, `seeds/push_webhook_local.sql` đặt Vault (URL `http://kong:8000/functions/v1/send-push`, mạng Docker nội bộ). Test function: `deno test supabase/functions/send-push/apns_test.ts`.

Bật push thật trên cloud (khi có Apple Developer account):

```bash
# 1. Apple Developer → Keys → tạo key APNs, tải AuthKey_XXXXXXXXXX.p8 (chỉ tải được 1 lần)
# 2. Secret cho function (SUPABASE_URL / SERVICE_ROLE_KEY runtime cấp sẵn)
SECRET=$(openssl rand -hex 32)
supabase secrets set PUSH_WEBHOOK_SECRET="$SECRET" APNS_KEY_ID=XXXXXXXXXX APNS_TEAM_ID=YYYYYYYYYY \
  APNS_BUNDLE_ID=vn.ancu.app APNS_KEY_P8="$(cat AuthKey_XXXXXXXXXX.p8)"
supabase functions deploy send-push        # verify_jwt=false lấy từ config.toml
```

```sql
-- 3. Vault trên project cloud (SQL editor) — cùng $SECRET ở bước 2
select vault.create_secret('https://<project-ref>.supabase.co/functions/v1/send-push', 'send_push_url');
select vault.create_secret('<SECRET>', 'send_push_webhook_secret');
-- Đổi secret sau này: vault.update_secret((select id from vault.secrets where name = 'send_push_webhook_secret'), '<mới>')
```

Chưa đặt Vault → trigger bỏ qua (thông báo vẫn vào inbox, chỉ không có push). Host APNs (sandbox/production) chọn theo cột `push_tokens.environment` do app ghi lúc đăng ký (`register_push_token`) — không có biến môi trường toàn cục, nên token sandbox không bị xóa nhầm khi gửi lên production.

## Còn thiếu (TODO)

- Bình luận / báo cáo / chặn + kiểm duyệt (Phase 2, sau Cổng C).
- Trang quản trị nhập/sửa dự án (service role).
- Khi số dự án lên vài nghìn: chuyển `refresh_project_nearest_infra` sang job định kỳ.
