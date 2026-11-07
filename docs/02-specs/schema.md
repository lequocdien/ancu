# Thiết kế Dữ liệu & Schema - An Cư

> Nguồn: Đặc tả sản phẩm v2 (`01-ideas/source/`) — mục 5.
> Migration chính thức: `src/supabase/migrations/` (2026-11-07). Contract RPC ↔ app: `src/supabase/README.md`. Bảng bên dưới là tổng quan.

Bản v1 lưu tọa độ dạng số thực, tuyến dạng JSON — chưa tận dụng PostGIS (lý do chính chọn Supabase). v2 dùng kiểu địa lý PostGIS, thêm bảng ga/nút giao, kiểm duyệt, thông báo, lịch sử thay đổi, luật điều kiện.

## 1. Database Tables

| Bảng | Lưu gì | Thông tin chính |
| --- | --- | --- |
| `profiles` | Hồ sơ gắn với tài khoản | Tên hiển thị, đã xác thực SĐT chưa, số bình luận đã duyệt, vai trò (`user` / `moderator` / `admin`) |
| `projects` | Dự án NOXH | Tên, địa chỉ, tỉnh/phường theo địa giới mới (+ tên cũ để tìm kiếm), vị trí, trạng thái, khung nhận hồ sơ, khoảng giá, số căn, chủ đầu tư, `source_url`, `verified_at` |
| `infrastructure_routes` | Metro, Vành đai, Cao tốc, Quốc lộ | Tên, loại, trạng thái (quy hoạch / đang thi công / đã khai thác), năm dự kiến khai thác, hướng tuyến, màu, `source_url`, `verified_at` |
| `infra_nodes` | Ga / nút giao — nơi thực sự lên/xuống | Thuộc tuyến nào, tên, loại (ga / nút giao), vị trí |
| `bookmarks` | Dự án người dùng theo dõi | Người dùng, dự án, bật thông báo không, ngày lưu |
| `comments` | Bình luận + ảnh | Dự án, người viết, nội dung (≤ 1.000 ký tự), ≤ 3 ảnh, trạng thái duyệt, điểm rủi ro, lý do kiểm duyệt |
| `reports` | Báo cáo bình luận vi phạm | Bình luận, người báo cáo, lý do. Unique (comment, reporter) |
| `user_blocks` | Người dùng chặn nhau | Người chặn, người bị chặn |
| `project_updates` | Lịch sử mọi thay đổi dự án | Trường bị đổi, giá trị cũ, giá trị mới, thời điểm |
| `push_tokens` | Nơi gửi push | Người dùng, mã thiết bị, nền tảng (iOS / Android) |
| `data_reports` | Phản ánh dữ liệu dự án sai | Dự án, người báo, ghi chú, trạng thái xử lý |
| `notifications` | Hộp thông báo trong app | Người dùng, dự án, loại, tiêu đề, nội dung, thời điểm, đã đọc. Sinh bởi trigger fan-out từ `project_updates` |
| `lookup_items` | Danh mục dùng chung | (category, code), nhãn, thứ tự, màu, icon, thuộc tính, tâm (cho vùng phục vụ) |
| `app_config` | Cấu hình từ xa | `min_supported_version`, ngưỡng kiểm duyệt |
| `eligibility_rules` | Cấu hình kiểm tra điều kiện | Mục luật, giá trị (vd ngưỡng thu nhập), điều khoản dẫn chiếu, ngày hiệu lực |
| `moderation_config` *(đề xuất)* | Ngưỡng kiểm duyệt | `auto_approve_after` = 5, `auto_hide_reports` = 3, `daily_comment_limit` = 10 |
| `project_nearest_infra` *(đề xuất, materialized)* | Khoảng cách tính sẵn | Dự án, node gần nhất theo loại, khoảng cách (m), năm khai thác |

**Quan hệ:** một người dùng có nhiều bookmark và bình luận. Một dự án có nhiều bình luận, bookmark, bản ghi lịch sử. Một tuyến có nhiều ga/nút giao.

### Kiểu dữ liệu không gian (đề xuất)
- `projects.location`: `geography(Point, 4326)` + GiST index
- `infrastructure_routes.geom`: `geography(MultiLineString, 4326)` + GiST index
- `infra_nodes.location`: `geography(Point, 4326)`
- `route_type`: `metro`, `vanh_dai`, `cao_toc`, `quoc_lo` (thêm `cao_toc` 2026-11-07). Danh mục đặt ở bảng lookup thay vì Postgres enum để thêm giá trị không cần migration (xem `supabase/migrations`).
- Enum: `project_status` (vd `sap_mo`, `nhan_ho_so`, `da_dong`…), `route_status`, `comment_status` (`pending` / `approved` / `rejected` / `hidden`)

## 2. Nguyên tắc

- **Khoảng cách tới ga/nút giao gần nhất:** tính sẵn bằng truy vấn không gian PostGIS (KNN `<->`), lưu thành bảng tổng hợp, làm mới khi dữ liệu thay đổi. MVP dùng **đường chim bay** và ghi rõ trên UI; khoảng cách theo đường đi để giai đoạn sau.
- **Row Level Security:**
  - Khách chỉ đọc dự án, tuyến, ga, bình luận `approved`.
  - Người dùng chỉ sửa dữ liệu của chính mình.
  - Trạng thái duyệt bình luận chỉ server (service role) hoặc moderator được đổi.
- **Tải theo vùng nhìn:** chỉ trả dự án/tuyến trong bbox; tuyến giản lược (`ST_Simplify`) theo zoom.
- **Lịch sử thay đổi:** trigger ghi mọi thay đổi trên `projects` vào `project_updates` — vừa là nguồn thông báo, vừa là bằng chứng khi tranh cãi.
- **Logic ở server:** ưu tiên SQL function/trigger (chạy ở Postgres bất kỳ, giảm lock-in), Edge Function chỉ cho việc cần gọi dịch vụ ngoài (Gemini, APNs).
- **Không lưu** câu trả lời kiểm tra điều kiện nếu chưa có consent.

## 3. RPC Contracts (đề xuất)

App gọi qua RPC thay vì query bảng trực tiếp — RPC là contract ổn định, giúp chuyển backend sau này (xem `architecture.md` mục 5).

| Loại | Tên | Chức năng | Auth? |
| --- | --- | --- | --- |
| RPC | `projects_in_bbox(min_lng, min_lat, max_lng, max_lat, filter)` | Dự án trong khung nhìn | Không |
| RPC | `routes_in_bbox(bbox, zoom, types[])` | Tuyến (đã giản lược) trong khung nhìn | Không |
| RPC | `project_detail(project_id)` | Chi tiết + khoảng cách ga/nút giao gần nhất | Không |
| RPC | `search_places(q)` | Tìm theo tên dự án, quận/phường (tên mới + cũ) | Không |
| Table/RPC | `bookmarks` upsert / delete, `merge_guest_bookmarks(ids[])` | Lưu dự án, gộp danh sách khách | Có |
| Edge Function | `submit-comment` | Validate, rate limit, chạy pipeline kiểm duyệt | Có + SĐT đã xác thực |
| RPC | `report_comment(comment_id, reason)` | Báo cáo, tự ẩn khi ≥ ngưỡng | Có |
| RPC | `report_data(project_id, note)` | Báo thông tin sai | Có |
| RPC | `eligibility_rules_current()` | Luật hiện hành cho công cụ kiểm tra | Không |
| Edge Function | `delete-account` | Xóa tài khoản + dữ liệu liên quan | Có |
| Edge Function | `send-push` (internal) | Đọc `project_updates`, gửi APNs/FCM | Service |
