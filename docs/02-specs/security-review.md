# Rà soát bảo mật — Phase 1 (bước 5.3)

> Ngày: 2026-11-07 · Phạm vi: Supabase (migration 01–11, Edge Function `send-push`) + app iOS. Kiểm chứng bằng pgTAP (`src/supabase/tests/database/`, 64 test) và integration test iOS gọi PostgREST thật.

## 1. Kết luận nhanh

| Hạng mục | Trạng thái |
| --- | --- |
| Không có service key / secret trong app | ✅ `BackendConfig.isPublishableKey` từ chối `sb_secret_…` và JWT `service_role` (có test) |
| RLS bật cho mọi bảng `public` | ✅ |
| Dữ liệu người dùng chỉ thấy của mình | ✅ pgTAP: user B không thấy bookmark/báo cáo của A |
| Ghi dữ liệu dự án/tuyến | ✅ Chỉ service role (không policy ghi cho anon/authenticated) |
| Rate limit | ⚠️ Một phần — xem mục 4 |
| Lỗ đã sửa trong lần rà soát | 1 (mục 3) |

## 2. Bảng quyền theo bảng

| Bảng | anon | authenticated | Ghi chú |
| --- | --- | --- | --- |
| lookup_items, administrative_units, projects, infrastructure_routes, infra_nodes, project_nearest_infra, project_updates, eligibility_rules, app_config | đọc | đọc | Ghi: service role. App đọc qua RPC |
| profiles | — | đọc/sửa dòng của mình, **chỉ cột `display_name`** | `role`, `phone_verified`, `notification_prefs` chỉ qua server/RPC |
| bookmarks | — | toàn quyền dòng của mình | |
| notifications | — | đọc của mình, sửa **chỉ `read_at`** | Tạo bởi trigger fan-out (SECURITY DEFINER) |
| push_tokens | — | toàn quyền dòng của mình | Đổi chủ token qua RPC `register_push_token` |
| data_reports | — | đọc của mình; **ghi chỉ qua RPC** `report_data` | Đã sửa (mục 3) |
| analytics_events | — (thu hồi cả quyền bảng) | — | Ghi qua RPC `track_events`; đọc: service role / Studio |

## 3. Lỗ phát hiện & đã sửa

| # | Mô tả | Mức | Sửa |
| --- | --- | --- | --- |
| 1 | Policy `own reports insert` cho phép ghi thẳng `data_reports` qua PostgREST → **vượt giới hạn 10 báo cáo/24h** của RPC, spam đội dữ liệu | Trung bình | Migration 11: bỏ policy + quyền INSERT; `report_data` thành SECURITY DEFINER. pgTAP kiểm tra ghi thẳng bị 42501 |

## 4. Rate limit & chống lạm dụng

| Điểm | Giới hạn hiện có | Rủi ro còn lại / việc sau |
| --- | --- | --- |
| Đăng nhập email OTP | Supabase Auth: `email_sent`/giờ, `max_frequency` 1s; app chặn gửi lại 30s | Cloud: giữ mặc định thấp + SMTP riêng (SendGrid/SES) trước khi phát hành; cân nhắc CAPTCHA (`[auth.captcha]`) nếu bị spam |
| Báo sai | 10 lần / 24h / tài khoản (RPC, mã `AC429` → `.rateLimited`) | — |
| Analytics | 50 sự kiện/lô, 2.000 sự kiện / 24h / install (bỏ lặng lẽ) | Kẻ phá đổi `install_id` liên tục vẫn ghi được → cần rate limit theo IP ở gateway (Cloudflare trước Supabase, hoặc chuyển ingest sang Edge Function có kiểm tra). Theo dõi dung lượng bảng; đặt job xóa sự kiện > 13 tháng |
| RPC đọc công khai | `projects_in_bbox` tối đa 500 dòng; `search_places` tối đa 20 | Không có rate limit theo IP — chấp nhận cho MVP (dữ liệu công khai); thêm gateway khi có traffic thật |
| Webhook `send-push` | Secret header, so sánh constant-time; thiếu secret → từ chối hết | Secret nằm trong Vault + secrets của function, không trong migration |

## 5. SECURITY DEFINER

Mọi hàm SECURITY DEFINER đặt `search_path = ''` (lint không cảnh báo) và tự kiểm tra `auth.uid()` khi thao tác dữ liệu người dùng. Danh sách: `current_profile`, `delete_my_account`, `handle_new_user`, `fan_out_project_update`, `refresh_*` (trigger), `register_push_token`, `set_notification_prefs`, `report_data`, `track_events`, `notify_send_push`. Hàm trigger/nội bộ đã thu hồi quyền EXECUTE khỏi `public, anon, authenticated`.

## 6. App iOS

- Phiên đăng nhập trong Keychain (mặc định supabase-swift); `signOut(scope: .local)` + gỡ push token trước khi bỏ phiên.
- Không lưu câu trả lời kiểm tra điều kiện; analytics không chứa PII — props chỉ là mã danh mục/cờ (rà bằng đọc code ở mọi chỗ gọi `track`; test chỉ kiểm tên sự kiện và phễu, chưa có test tự động chặn PII trong props).
- ATS: chỉ `http://127.0.0.1` cho stack local (IP được miễn ATS); bản phát hành dùng `https://<ref>.supabase.co`.
- Key nằm trong app là công khai theo thiết kế — an toàn nhờ RLS, không nhờ giấu key.

## 7. Trước khi phát hành (checklist)

- [ ] Cloud: bật SMTP riêng, rà `[auth.rate_limit]`, tắt `enable_signup` cho provider chưa dùng.
- [ ] Cloud: đặt Vault `send_push_url`, `send_push_webhook_secret`; `supabase secrets set` cho APNs.
- [ ] Cloud: Network Restrictions cho DB (chỉ IP quản trị), bật PITR backup.
- [ ] Chạy lại `supabase db lint --remote --schema public` (2026-11-07: sạch) + Security Advisor trên dashboard.
- [ ] Gateway rate limit theo IP (mục 4) nếu analytics bị lạm dụng.
