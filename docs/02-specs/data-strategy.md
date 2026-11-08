# Chiến lược dữ liệu - An Cư

> Nguồn: Đặc tả sản phẩm v2 (`01-ideas/source/`) — mục 6.

Dữ liệu mới là sản phẩm thật, app chỉ là lớp hiển thị. MVP bắt đầu với **một vùng**: **TP.HCM (gồm Bình Dương cũ) + Đồng Nai** (chốt 2026-11-06), để đối chiếu thủ công từng dự án và giữ độ chính xác cao.

**Phạm vi địa lý MVP — đổi 2026-11-08: theo địa giới MỚI (sau sáp nhập 1/7/2025), TP.HCM + 4 tỉnh giáp ranh**:

| Mã | Tỉnh mới | Gồm (địa giới cũ) |
| --- | --- | --- |
| `tp_hcm` | TP.HCM | TP.HCM cũ, Bình Dương cũ, Bà Rịa – Vũng Tàu cũ |
| `dong_nai` | Đồng Nai | Đồng Nai cũ, Bình Phước cũ |
| `tay_ninh` | Tây Ninh | Tây Ninh cũ, Long An cũ |
| `dong_thap` | Đồng Tháp | Đồng Tháp cũ, Tiền Giang cũ |
| `lam_dong` | Lâm Đồng | Lâm Đồng cũ, Đắk Nông cũ, Bình Thuận cũ |

- Mã cũ (`hcm_cu`, `binh_duong_cu`, `dong_nai_cu`, `ba_ria_vung_tau_cu`, `binh_phuoc_cu`) **giữ trong danh mục** (`in_mvp = false`, `merged_into = <mã mới>`) để dữ liệu/lịch sử cũ không gãy; không còn là chip, không còn ranh giới.
- Tìm kiếm vẫn hiểu tên cũ (Thủ Dầu Một, Vũng Tàu, Long An…) qua alias phường/xã.
- *Trước 2026-11-08*: MVP = TP.HCM cũ + Bình Dương cũ + Đồng Nai cũ (địa giới cũ). Đổi vì: người dùng tìm nhà quanh TP.HCM theo tỉnh hiện hành; một mô hình địa giới duy nhất dễ hiểu hơn trộn cũ/mới.

## 1. Nguồn dữ liệu

| Loại dữ liệu | Nguồn chính | Cách đưa vào hệ thống |
| --- | --- | --- |
| Danh sách dự án NOXH, khung nhận hồ sơ | Thông báo Sở Xây dựng, cổng Bộ Xây dựng, thông báo chính thức của chủ đầu tư | Nhập tay qua trang quản trị, kèm `source_url` |
| Giá, số căn | Quyết định phê duyệt giá, thông báo chủ đầu tư | Nhập tay. Chưa có giá phê duyệt → ghi rõ "Giá dự kiến" |
| Tuyến Metro, ga | Quy hoạch được phê duyệt, Ban QL đường sắt đô thị HN & TP.HCM | Số hóa bằng QGIS / geojson.io → GeoJSON → PostGIS |
| Vành đai, quốc lộ, nút giao | Quyết định phê duyệt dự án, quy hoạch giao thông | Như trên. Ghi chú "hướng tuyến minh họa" |
| Trạng thái thực tế, ảnh công trường | Cộng đồng người dùng | Bình luận đã kiểm duyệt + nút "Báo thông tin sai" |

**Không scrape** từ sàn bất động sản hay app quy hoạch khác: dễ vi phạm điều khoản sử dụng, bản quyền cơ sở dữ liệu, và kéo theo dữ liệu sai.

## 2. Quy trình duy trì

- Mỗi bản ghi có `source_url` và `verified_at`, cả hai **hiển thị công khai** trong app.
- Bản ghi quá **30 ngày** chưa đối chiếu lại → app hiện "Thông tin có thể đã cũ".
- **Hằng tuần** rà lại dự án ở trạng thái `nhan_ho_so` hoặc sắp mở nhận hồ sơ.
- Báo cáo "thông tin sai" xử lý trong **72 giờ**.
- Mọi tuyến hạ tầng kèm miễn trừ: "Hướng tuyến mang tính minh họa theo quy hoạch được công bố, không dùng để xác định ranh giới đất."
- Cần ít nhất **một người phụ trách dữ liệu** (có thể bán thời gian) — chi phí vận hành cố định, tính vào kế hoạch từ đầu.
- Địa giới: dùng tên đơn vị hành chính mới sau 2025, giữ alias tên cũ (vd Bình Dương → TP.HCM) cho tìm kiếm.

## 2b. Thu thập → staging → duyệt (2026-11-08)

Dữ liệu thật **không ghi thẳng vào bảng chính**. Mọi nguồn (crawler, vẽ tay QGIS) đi qua staging, admin duyệt rồi mới xuất bản:

```
src/crawler (tách biệt, không có quyền DB) ─► runs/<ngày>_<nguồn>/{raw/, features.geojson, report.json}
src/data/geojson (vẽ tay, Git)             ─┤
                                            ▼  build_data.py --stage  →  stage.sql  →  psql
                         schema ingest: batches + route/node/project_candidates (+ raw, evidence_url, crawled_at)
                                            ▼  admin duyệt (DBeaver): ingest.approve_*(…) / approve_batch(…)
                         bảng chính → trigger: project_updates, thông báo (trừ đợt silent), khoảng cách ga
```

- **Crawler không chạm DB**, đầu ra duy nhất là file. Contract (`contract_version`) do `src/data` sở hữu và kiểm tra ở biên.
- **id ổn định** (UUID v5 từ khóa tự nhiên) → lần crawl sau trùng id: bản nháp cũ `superseded`, duyệt = upsert giữ bookmark.
- **`verified_at` do người duyệt đặt** (ngày duyệt), crawler không điền. Dự án crawl về **được thiếu vị trí** — admin đặt khi duyệt.
- **Đợt `silent`** (nhập lần đầu, sửa hàng loạt): vẫn ghi `project_updates` nhưng **không** bắn thông báo.
- **`geometry_accuracy`** cho tuyến/ga: `chinh_xac` (đã xây, đối chiếu được) · `gan_dung` (theo hồ sơ dự án) · `minh_hoa` (chỉ quy hoạch). App hiện nhãn "Hướng tuyến minh họa".
- Bằng chứng (`raw/`) lưu lâu dài ở Supabase Storage bucket private `ingest-evidence` (sau); DB chỉ giữ đường dẫn.
- Tôn trọng nguồn: `robots.txt`, ≤ 1 request / vài giây, User-Agent nêu tên An Cư; chỉ nguồn chính thống (mục 1).

## 2b'. Ranh giới tỉnh (2026-11-08)
| Tỉnh | Nguồn | `is_mock` |
|---|---|---|
| TP.HCM, Đồng Nai, Tây Ninh | Bản đồ tra cứu ĐVHC Việt Nam — sapnhap.bando.com.vn (NXB TN-MT&BĐVN, 2026, ISBN 978-632-622-303-3) | false |
| Đồng Tháp, Lâm Đồng | Mock vẽ tay, đã cắt theo ranh giới thật | true |

Quy trình: trên trang chọn tỉnh → DevTools Network → request `pread_json` (`id=diaphanhanhchinhcaptinh_sn.<n>`) → Save response vào
`src/data/raw/bando/` (**không commit**, bản quyền nhà xuất bản) → `python3 -I src/data/scripts/import_bando_boundaries.py src/data/raw/bando src/data/geojson/service_areas.geojson`
(kiểm hợp lệ + diện tích lệch ≤ 3% so với `a06_dt`) → `build_data.py` → migration cập nhật `geom`. Giữ nguyên độ chi tiết gốc; app xin bản giản lược 0,0005° qua RPC.
Không tự gọi `pread_json` (API nội bộ, cần cookie phiên) — người duyệt lưu thủ công từng tỉnh.
Lưu ý: trang ghi "xuất bản phẩm không kinh doanh" — nếu app có doanh thu, xin phép nhà xuất bản cho phần dữ liệu này.

## 2c. Ẩn/hiện (tạm ngừng phục vụ) một tỉnh (2026-11-08)
Cờ duy nhất: `lookup_items.attributes.in_mvp` của danh mục `service_areas` — không thêm cờ thứ hai để khỏi lệch nhau.
Admin đổi bằng hàm (DBeaver; không mở qua API):
```sql
select ingest.set_service_area_active('lam_dong', false, 'chưa có dự án');  -- tạm ngừng (bắt buộc lý do)
select ingest.set_service_area_active('lam_dong', true);                    -- bật lại
```
| | Khi tạm ngừng |
|---|---|
| App | Mất chip; tìm tên tỉnh/phường → "Sắp có"; không khôi phục vùng đã chọn. Áp dụng ở lần tải danh mục kế tiếp (mở lại app) |
| Dự án | Ẩn khỏi bản đồ (`projects_in_bbox`) và tìm kiếm (`search_places`); bookmark vẫn mở được (`projects_by_ids`) |
| Địa điểm lưu | Không tạo/đề xuất mới (AC403); địa điểm cũ vẫn sửa tên/ghi chú/xóa được |
| Staging | Bản nháp dự án thuộc tỉnh đó bị từ chối khi kiểm tra |
| Không đổi | Khung camera, ranh giới, dữ liệu đã có |

Chặn: mã cũ đã gộp; bật tỉnh chưa có ranh giới/tâm (vd Hà Nội); tắt vùng phục vụ cuối cùng. Hàm trả về số dự án / địa điểm lưu / bookmark trong tỉnh để admin thấy ảnh hưởng.

## 3. Câu hỏi còn mở
- Hợp tác chủ đầu tư tự cập nhật (tài khoản xác minh, gắn nhãn) mà không mất khách quan?
- ~~Mở rộng TP.HCM (và Bình Dương cũ) ngay sau MVP hay chờ ngưỡng người dùng?~~ → Đã gộp vào MVP (2026-11-06).
- Mở rộng Hà Nội sau MVP khi nào (ngưỡng người dùng)?
