# An Cư crawler

Thu thập dữ liệu từ **nguồn chính thống** → `runs/<run>/features.geojson` (contract v1). Project Python **tách biệt**:
venv và dependency riêng, **không có thông tin kết nối DB** — parser lỗi hay thư viện bị chèn mã độc cũng không ghi được
vào DB. Dữ liệu vào staging qua `src/data` (người sở hữu contract), admin duyệt rồi mới lên bảng chính
(`docs/02-specs/data-strategy.md` mục 2b).

## Chạy một lần crawl (từng bước)

Ví dụ với nguồn `so_xay_dung_hcm`. Lệnh crawler chạy **trong `src/crawler`** (Python tìm package `app` từ thư mục
hiện tại — không cài crawler thành package). Các lệnh còn lại chạy từ **thư mục gốc repo** (`~/Downloads/AnCu`).

```
crawl → kiểm tra report → (tải PDF tay) → nạp staging LOCAL → xem → nạp staging CLOUD → duyệt trong DBeaver → kiểm tra app
```

### Bước 0 — Cài đặt (chỉ lần đầu)

```bash
cd src/crawler
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt        # httpx, beautifulsoup4, pdfplumber (phiên bản ghim)
.venv/bin/python -m unittest discover -s tests   # phải OK (không gọi mạng)
.venv/bin/python -m app list            # thấy: so_xay_dung_hcm  projects  …
```

**Không** chạy `pip install -e .` — bản cài editable làm Python nhận `app` thành namespace package
(`No module named app.__main__`). Đã gặp 2026-11-08.

### Bước 1 — Crawl

```bash
cd src/crawler
.venv/bin/python -m app run so_xay_dung_hcm
cd ../..
```

Kết quả in ra:

```
Đã ghi …/src/crawler/runs/2026-11-08_1145_so_xay_dung_hcm/features.geojson — 4 projects, 3 cảnh báo
Tiếp: python3 -I src/data/scripts/build_data.py --stage …/features.geojson
```

- Lần đầu nên thêm `--limit 2` để thử. Mỗi lần chạy ~3 request, cách nhau ≥ 3 giây (`--interval` để chỉnh, không giảm dưới 3).
- Thư mục `runs/<ngày_giờ>_<nguồn>/` gồm: `features.geojson` (dữ liệu), `report.json` (số lượng + cảnh báo), `raw/` (bản chụp trang — bằng chứng).

### Bước 2 — Đọc cảnh báo

```bash
cat src/crawler/runs/<run>/report.json      # <run> = tên thư mục in ở bước 1, vd 2026-11-08_1145_so_xay_dung_hcm
```

| Cảnh báo | Nghĩa | Làm gì |
| --- | --- | --- |
| `No module named app…` | Đang chạy ngoài `src/crawler` hoặc đã cài editable | `cd src/crawler`; nếu đã cài `-e .`: `.venv/bin/pip uninstall ancu-crawler` |
| `DỪNG: robots.txt không cho phép …` + `0 projects` | Không đọc được robots.txt (mạng chập chờn) hoặc trang cấm thật | Chạy lại sau ít phút. Lặp lại → mở `https://<trang>/robots.txt` xem có bị cấm thật không. **Không sửa code để bỏ qua** |
| `không thấy bài 'Danh mục…'` | Trang đổi cấu trúc | Báo dev — parser cần sửa |
| `<số văn bản>: không đoán được vùng` / `không tách được địa chỉ` | Crawler không chắc | Điền khi duyệt (bước 6) |
| `<số văn bản>: link PDF trên trang không khớp…` | Trang của Sở gắn nhầm file | Bình thường — đã dùng link bài viết |
| `<số văn bản>: chưa có PDF trong --pdf-dir` | Chưa tải PDF của công văn đó | Bước 3 (tùy chọn) |
| `PDF không có lớp chữ (bản scan)` | PDF là ảnh scan | Đọc PDF, nhập tay ngày nhận hồ sơ / số căn / giá khi duyệt |

### Bước 3 — (Tùy chọn) Tải PDF tay để có ngày nhận hồ sơ, số căn, giá

Sở XD chặn tải PDF tự động — **tải bằng trình duyệt như người dùng bình thường**:

1. Mở bài danh mục (link trong `source_url` của feature, hoặc trang Sở XD → Dự án Nhà ở xã hội).
2. Bấm từng link PDF → lưu vào `src/crawler/pdf/so_xay_dung_hcm/`, **giữ nguyên tên file gốc** (crawler ghép theo số văn bản trong tên file).
3. Chạy lại bước 1 — crawler tự đọc PDF trong thư mục đó (hoặc chỉ định `--pdf-dir <thư mục khác>`).

### Bước 4 — Nạp vào staging LOCAL để xem trước (cần `supabase start`)

```bash
python3 -I src/data/scripts/build_data.py --stage src/crawler/runs/<run>/features.geojson --silent --note "Sở XD <ngày>"
docker exec -i supabase_db_ancu psql -U postgres -v ON_ERROR_STOP=1 < src/data/out/stage.sql
```

- `--silent`: đợt nhập lặng — khi duyệt **không** bắn thông báo cho người dùng. Dùng cho lần nhập đầu và khi chỉ sửa định dạng. Bỏ `--silent` khi muốn người theo dõi dự án nhận thông báo (vd dự án đổi trạng thái thật).
- `build_data.py` báo `LỖI: không nạp được vào staging` → file sai contract (crawler lỗi) — báo dev, không sửa tay file.

Xem trong DBeaver (kết nối **local**: `127.0.0.1:54322`, user/pass `postgres`):

```sql
select candidate_id, change, name, changed_fields, needs_location, validation_errors
from ingest.pending_review where source = 'so_xay_dung_hcm' order by candidate_id;
```

`change = new` (dự án mới) / `update` (đã có — xem `changed_fields`). `validation_errors` rỗng + `needs_location = false` mới duyệt cả đợt được.

### Bước 5 — Nạp vào staging CLOUD

Khi bản xem trước ở local ổn, chạy lại **cùng file** `stage.sql` lên cloud:

```bash
psql "$(cat src/supabase/.temp/pooler-url)" -v ON_ERROR_STOP=1 -f src/data/out/stage.sql   # hỏi mật khẩu DB
```

(Hoặc mở `src/data/out/stage.sql` trong DBeaver với kết nối cloud và chạy cả file.)

### Bước 6 — Duyệt trong DBeaver (kết nối CLOUD)

```sql
-- 1. Xem
select candidate_id, change, name, needs_location, validation_errors
from ingest.pending_review where source = 'so_xay_dung_hcm' order by candidate_id;

-- 2. Bản sai / không muốn đưa lên → từ chối (bắt buộc lý do)
select ingest.reject('project', 22, 'chưa rõ địa chỉ, chờ công văn');

-- 3. Bổ sung phần crawler không chắc → trigger kiểm tra lại, validation_errors cập nhật ngay
update ingest.project_candidates set address = '…', service_area = 'tp_hcm' where candidate_id = 21;

-- 4. Đợt mới của dự án ĐÃ CÓ trong An Cư → gắn vào dự án cũ (giữ bookmark, thông báo đúng người theo dõi)
update ingest.project_candidates set id = '<id dự án cũ>' where candidate_id = 21;

-- 5. Duyệt từng dự án kèm vị trí (lấy lat/lng trên bản đồ theo địa chỉ trong công văn)
select ingest.approve_project(21, 10.8512, 106.7895, 'đối chiếu CV 37857');

-- (Khi mọi bản đều đủ vị trí + không lỗi) duyệt cả đợt — all-or-nothing:
select * from ingest.approve_batch('<batch_id trong pending_review>');
```

Nếu tắt Auto-commit trong DBeaver: bấm **Commit** sau khi duyệt (Rollback nếu lỡ tay).

### Bước 7 — Kiểm tra

- Mở app (đang trỏ cloud) → dự án mới hiện trên bản đồ, chi tiết có nguồn + "Cập nhật: <ngày duyệt>".
- Bản nháp đã duyệt: `select review_status, reviewed_by, reviewed_at from ingest.project_candidates where candidate_id = 21;` → `applied`.

### Chạy lại định kỳ (hằng tuần)

Lặp bước 1 → 6. Công văn đã nạp trước đó cho **cùng id** → bản nháp cũ tự `superseded`; `pending_review` cho biết đã đổi gì
(`change = update`, `changed_fields`). Công văn mới → `change = new`.

## Cấu trúc

```
src/crawler/
├─ app/
│  ├─ cli.py              python -m app list | run <nguồn>
│  ├─ core/               DÙNG CHUNG — nguồn mới không sửa ở đây
│  │  ├─ fetch.py         robots.txt, giãn cách theo host, thử lại, lưu bằng chứng
│  │  ├─ contract.py      contract v1: id ổn định (UUID v5), Run → features.geojson + report.json
│  │  ├─ pdf_fields.py    trích ngày nhận hồ sơ / số căn / giá từ chữ công văn PDF
│  │  └─ source.py        class cơ sở Source
│  └─ sources/            RIÊNG TỪNG NGUỒN — chỉ phần đọc trang
│     ├─ __init__.py      đăng ký (@register) + import các nguồn
│     └─ so_xay_dung_hcm.py
├─ sources.json           danh sách nguồn + kết quả khảo sát (robots.txt, cấu trúc, chặn…)
├─ pdf/<nguồn>/           PDF bạn tự tải bằng trình duyệt (không commit)
├─ runs/<ngày>_<nguồn>/   kết quả mỗi lần chạy: raw/, features.geojson, report.json (không commit)
└─ tests/                 test không gọi mạng + fixtures/ (trích HTML thật)
```

Import trong nguồn: `from ..core import Fetcher, Run, Source, extract_fields, …`

## Nguyên tắc
- **Chỉ nguồn chính thống** (`sources.json`). Không scrape sàn bất động sản / app khác.
- **Tôn trọng nguồn** (`core/fetch.py`, mọi request bắt buộc đi qua đây): `robots.txt` (không đọc được = chặn), ≥ 3 giây giữa
  2 request cùng host, User-Agent tự xưng `AnCuCrawler/0.1` (không giả trình duyệt; không kèm liên hệ — quyết định 2026-11-08), thử lại có
  giới hạn, tôn trọng `Retry-After`.
- **PDF tải tay**: `pdf/<nguồn>/` (mặc định của `--pdf-dir`). **Không commit** (.gitignore): công văn có bản quyền của
  Sở, repo phình nhanh — lưu lâu dài sau này ở Supabase Storage (bucket private `ingest-evidence`).
- **Bằng chứng**: mỗi trang/PDF tải về lưu ở `runs/<run>/raw/`, đường dẫn ghi vào `_evidence` của feature.
- **id ổn định**: `Run.add(natural_key, …)` → UUID v5 từ (nguồn, khóa tự nhiên: mã dự án hoặc URL — không dùng tên).
  Không bao giờ đổi `ID_NAMESPACE`.
- **Không điền `verified_at`** (người duyệt đặt). Thiếu vị trí → `geometry: null` (admin đặt ghim khi duyệt).
- **Test không gọi mạng**: lưu HTML/PDF mẫu ở `tests/fixtures/`, dùng `httpx.MockTransport`.
- Contract kiểm bằng chính `src/data/scripts/staging.py` trong test (consumer-driven) — crawler đổi định dạng sai là test đỏ.

## Thêm nguồn
1. Khảo sát: robots.txt, điều khoản, cấu trúc trang; cập nhật `sources.json` (`trang_thai`).
2. `app/sources/<ten>.py`: class kế thừa `core.Source`, `@register`, import trong `sources/__init__.py`. Chỉ viết phần đọc trang — tải, contract, PDF dùng `core/`.
3. Lưu trang mẫu vào `tests/fixtures/`, viết test parser.

## Nguồn `so_xay_dung_hcm` (Sở XD TP.HCM) — phương án A

PDF công văn bị WAF chặn tải tự động → **không lách**. Crawler đọc bài "Danh mục các dự án NOXH đang tiếp nhận hồ sơ"
(3 request): tên + địa bàn (có dấu), số văn bản, ngày, link PDF. Bạn tự tải PDF bằng trình duyệt (bước 3 ở trên).

- Mỗi **công văn** (số văn bản) = 1 bản nháp; chạy lại → cùng id (bản cũ `superseded`).
- Vùng chỉ đoán theo tên quận/huyện **không trùng tên** (Hiệp Thành, Thạnh Tân… bị trùng nhiều nơi → để trống).
- Link PDF trên trang **không khớp** số văn bản (đã gặp: 37302 trỏ file 33745) → dùng link bài viết + cảnh báo.
- Trích từ PDF là heuristic: chỉ điền khi chắc; đoạn trích nằm trong `raw->'pdf_trich'` để đối chiếu. PDF scan → cảnh báo, nhập tay.
