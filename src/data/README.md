# An Cư — Dữ liệu nguồn (GeoJSON)

Nguồn sự thật duy nhất cho **tuyến hạ tầng, nút (ga/nút giao/điểm lớn), dự án và ranh giới vùng phục vụ**. Hiện là dữ liệu **mock**; pipeline crawl/nhập liệu sau này chỉ cần xuất 3 file GeoJSON đúng contract dưới đây (`docs/02-specs/architecture.md` mục 5.6, bước 2.6).

```text
src/data/geojson/{routes,nodes,projects}.geojson      ← crawler / người nhập liệu sửa ở đây
  └─ build_data.py: validate → src/ios/AnCu/Data/Mock/Resources/{routes,nodes,projects}.json  (mock của app)
       └─ supabase/scripts/generate_seed.py → src/supabase/seed.sql
```

Danh mục (`Lookup/*.json` trong app) **không** nằm ở đây: vẫn sửa trực tiếp trong `src/ios/AnCu/Data/Mock/Resources/Lookup/`; validator đối chiếu mã với các file đó. `notifications.json` không thuộc pipeline (trên server sinh từ trigger).

## Lệnh

```bash
python3 -I src/data/scripts/build_data.py            # validate + ghi JSON app + sinh seed.sql (một lệnh làm hết)
python3 -I src/data/scripts/build_data.py --check    # chỉ kiểm tra, không ghi; exit 1 nếu JSON app lệch GeoJSON (CI)
python3 -I src/data/scripts/build_data.py --no-seed  # không chạy generate_seed.py
python3 -I -m unittest discover -s src/data/scripts -p 'test_*.py' -v   # test validator
```

Chỉ dùng thư viện chuẩn Python 3 (≥ 3.9). Gặp lỗi → in **toàn bộ** vấn đề (tiếng Việt, kèm file, chỉ số feature, id) rồi exit 1, không ghi gì. Không đụng DB: muốn nạp vào Supabase local thì `supabase db reset` (xóa dữ liệu local).

**Không sửa tay** `routes.json`, `nodes.json`, `projects.json` của app hay `seed.sql` — lần chạy sau sẽ ghi đè.

## Quy ước chung

- GeoJSON chuẩn **RFC 7946**: gốc là `FeatureCollection`, mỗi phần tử là `Feature` có `properties` và `geometry`. Hệ tọa độ WGS 84 (EPSG:4326), không khai báo `crs`.
- Thứ tự tọa độ **`[lng, lat]`** (kinh độ trước). Chỉ 2 thành phần, không có độ cao. Mọi điểm phải nằm trong khung Việt Nam: lng 102–110, lat 8–23.5 (bắt lỗi đảo lat/lng).
- `id` nằm trong `properties` (không dùng `Feature.id` cấp ngoài), là **UUID**, duy nhất trong file. Giữ nguyên id giữa các lần xuất — app lưu bookmark theo id. Crawler nên sinh UUID v5 ổn định từ khóa tự nhiên (vd URL nguồn).
- Ngày dạng `YYYY-MM-DD` (giờ Việt Nam). URL bắt đầu `http://` hoặc `https://`.
- Chuỗi bắt buộc không được rỗng. **Thuộc tính lạ bị từ chối** (bắt lỗi gõ sai tên); thêm thuộc tính mới = sửa validator + DTO app + schema DB cùng lúc.
- "Tùy chọn" = được vắng mặt hoặc `null`; khi sinh JSON app, khóa vắng mặt ghi thành `null` (riêng `price_is_estimated` → `true`).
- Mã danh mục phải có trong `src/ios/AnCu/Data/Mock/Resources/Lookup/<danh mục>.json`.

## `routes.geojson` — tuyến hạ tầng

Geometry: `LineString` (≥ 2 điểm) hoặc `MultiLineString` (≥ 1 đoạn, mỗi đoạn ≥ 2 điểm — tuyến khai thác từng đoạn rời như Vành đai 3). Trên DB luôn lưu `MultiLineString`.

| Thuộc tính | Bắt buộc | Kiểu | Ràng buộc |
| --- | --- | --- | --- |
| `id` | có | string | UUID |
| `name` | có | string | |
| `type` | có | string | `route_types`: `metro`, `vanh_dai`, `cao_toc`, `quoc_lo` |
| `status` | có | string | `route_statuses`: `da_khai_thac`, `dang_thi_cong`, `quy_hoach` |
| `expected_year` | tùy chọn | integer | 1990–2100 |
| `color_hex` | có | string | `#RRGGBB` |
| `source_url` | có | string | http(s) |
| `verified_at` | có | string | `YYYY-MM-DD` |

## `nodes.geojson` — ga, nút giao, điểm hạ tầng lớn

Geometry: `Point`.

| Thuộc tính | Bắt buộc | Kiểu | Ràng buộc |
| --- | --- | --- | --- |
| `id` | có | string | UUID |
| `route_id` | tùy chọn | string \| null | UUID có trong `routes.geojson`; `null` = không thuộc tuyến nào (vd Sân bay Long Thành) |
| `name` | có | string | |
| `type` | có | string | `node_types`: `ga_metro`, `nut_giao`, `diem_hat_nhan` |

## `projects.geojson` — dự án NOXH

Geometry: `Point` (vị trí dự án).

| Thuộc tính | Bắt buộc | Kiểu | Ràng buộc |
| --- | --- | --- | --- |
| `id` | có | string | UUID |
| `name` | có | string | |
| `address` | có | string | |
| `ward_code` | tùy chọn | string \| null | `code` trong `administrative_units.json`; phải thuộc cùng `service_area` |
| `service_area` | có | string | `service_areas`: `hcm_cu`, `binh_duong_cu`, `dong_nai_cu`, `ba_ria_vung_tau_cu`, `binh_phuoc_cu` |
| `status` | có | string | `project_statuses`: `nhan_ho_so`, `sap_mo`, `dang_xay`, `da_dong` |
| `legal_status` | có | string | `legal_statuses`: `chu_truong_dau_tu`, `da_co_giay_phep_xd`, `du_dieu_kien_ban`, `da_ban_giao` |
| `application_start` | tùy chọn | string \| null | `YYYY-MM-DD`, ≤ `application_end` |
| `application_end` | tùy chọn | string \| null | `YYYY-MM-DD` |
| `price_min` | tùy chọn | number \| null | triệu đồng/m², 0 < giá < 10000, ≤ `price_max` |
| `price_max` | tùy chọn | number \| null | như trên |
| `price_is_estimated` | tùy chọn | boolean | vắng mặt → `true` (giá dự kiến); không nhận `null` |
| `unit_count` | tùy chọn | integer \| null | > 0 |
| `developer` | tùy chọn | string \| null | |
| `cover_image_url` | tùy chọn | string \| null | http(s) |
| `source_url` | có | string | http(s) |
| `verified_at` | có | string | `YYYY-MM-DD` |

Danh sách mã ở các bảng trên là ảnh chụp lúc viết; nguồn chính xác là `Lookup/*.json` (thêm mã mới ở đó, không sửa validator). Các ràng buộc số/ngày/URL khớp `CHECK` trong `src/supabase/migrations/*_02_core_tables.sql`.

## `service_areas.geojson` — ranh giới vùng phục vụ

Dùng để highlight vùng khi người dùng chọn chip TP.HCM / Bình Dương / Đồng Nai. Hiện là **đa giác giản lược (mock)**, chỉ để nhận biết hình dạng — không dùng xác định địa giới.

Geometry: `Polygon` hoặc `MultiPolygon`; mỗi đa giác **đúng 1 vòng ngoài** (chưa hỗ trợ lỗ), khép kín (điểm đầu = điểm cuối), ≥ 4 vị trí. App nhận vòng ngoài bỏ điểm đóng lặp (`service_area_boundaries.json`).

| Thuộc tính | Bắt buộc | Kiểu | Ràng buộc |
| --- | --- | --- | --- |
| `code` | ✓ | chuỗi | Mã trong `service_areas`; mỗi mã tối đa 1 feature |
| `is_mock` | ✓ | boolean | `true` khi là hình giản lược |
| `source_url` | ✓ | chuỗi | http(s) |
| `verified_at` | ✓ | chuỗi | `YYYY-MM-DD` |

Kiểm tra chéo: **mọi dự án phải nằm trong ranh giới vùng của nó** (`service_area`) — bắt sai tọa độ hoặc gán nhầm vùng. Vùng nằm ngoài MVP được phép không có ranh giới.

## Staging → duyệt → bảng chính (2026-11-08)

Dữ liệu thật **không** đi qua `seed.sql` (chỉ dùng cho local/test). Luồng: GeoJSON → `stage.sql` → schema `ingest` → admin duyệt trong DBeaver → bảng chính (data-strategy.md 2b).

```bash
# Dữ liệu vẽ tay (QGIS) trong data/geojson — tuyến/ga phải khai báo geometry_accuracy (hoặc --default-accuracy)
python3 -I src/data/scripts/build_data.py --stage-manual --entities routes,nodes [--silent] [--note "…"]
# File của crawler (contract v1, có khối "ancu")
python3 -I src/data/scripts/build_data.py --stage src/crawler/runs/<run>/features.geojson
# Nạp vào staging (cloud: connection string Session pooler)
psql "<connection string>" -v ON_ERROR_STOP=1 -f src/data/out/stage.sql
```

Duyệt (DBeaver, user `postgres`):

```sql
select * from ingest.pending_review order by batch_id, entity, name;       -- mới/sửa, trường đổi, dời bao nhiêu mét, lỗi
select ingest.reject('project', <candidate_id>, 'lý do');                  -- bản sai: từ chối trước
select * from ingest.approve_batch('<batch_id>');                          -- cả đợt (all-or-nothing)
select ingest.approve_project(<candidate_id>, <lat>, <lng>, 'ghi chú');    -- dự án thiếu vị trí: admin đặt ghim
```

- **Kiểm 2 tầng**: `staging.py` kiểm cấu trúc (kiểu, UUID, hình học, thuộc tính lạ, contract); trigger DB kiểm nghiệp vụ (danh mục, vùng MVP, đủ cặp giá/ngày) → cột `validation_errors`.
- **Trường tùy chọn trống** trong bản nháp dự án = giữ giá trị hiện có. **`verified_at`** = ngày duyệt. Đợt `--silent`: không bắn thông báo (vẫn ghi `project_updates`).
- **Contract file crawler v1**: gốc `{"type":"FeatureCollection","ancu":{"contract_version":1,"entity":"projects|routes|nodes","source":"<mã>","run_ref":"…"},"features":[…]}`; thuộc tính như bảng trên (bỏ `verified_at`) + `geometry_accuracy` (tuyến/ga) + metadata `_crawled_at`, `_evidence`, `_raw`. Dự án được `geometry: null`.
