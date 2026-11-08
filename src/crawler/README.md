# An Cư crawler

Thu thập dữ liệu từ **nguồn chính thống** → `runs/<run>/features.geojson` (contract v1). Project Python **tách biệt**:
venv và dependency riêng, **không có thông tin kết nối DB** — parser lỗi hay thư viện bị chèn mã độc cũng không ghi được
vào DB. Dữ liệu vào staging qua `src/data` (người sở hữu contract), admin duyệt rồi mới lên bảng chính
(`docs/02-specs/data-strategy.md` mục 2b).

```bash
cd src/crawler
python3 -m venv .venv && .venv/bin/pip install -e .     # httpx, beautifulsoup4, pdfplumber (ghim phiên bản)
.venv/bin/python -m ancu_crawler list
.venv/bin/python -m ancu_crawler run <nguồn> --limit 5   # → runs/<ngày>_<nguồn>/{raw/, features.geojson, report.json}
.venv/bin/python -m unittest discover -s tests            # không gọi mạng

# Sau đó (từ thư mục gốc repo):
python3 -I src/data/scripts/build_data.py --stage src/crawler/runs/<run>/features.geojson
psql "<connection string>" -v ON_ERROR_STOP=1 -f src/data/out/stage.sql   # → ingest.*, duyệt trong DBeaver
```

## Nguyên tắc
- **Chỉ nguồn chính thống** (`sources.json`). Không scrape sàn bất động sản / app khác.
- **Tôn trọng nguồn** (`fetch.py`, mọi request bắt buộc đi qua đây): `robots.txt` (không đọc được = chặn), ≥ 3 giây giữa
  2 request cùng host, User-Agent nêu tên An Cư (**đặt URL/email liên hệ thật trước khi chạy nguồn thật**), thử lại có
  giới hạn, tôn trọng `Retry-After`.
- **Bằng chứng**: mỗi trang/PDF tải về lưu ở `runs/<run>/raw/`, đường dẫn ghi vào `_evidence` của feature.
- **id ổn định**: `Run.add(natural_key, …)` → UUID v5 từ (nguồn, khóa tự nhiên: mã dự án hoặc URL — không dùng tên).
  Không bao giờ đổi `ID_NAMESPACE`.
- **Không điền `verified_at`** (người duyệt đặt). Thiếu vị trí → `geometry: null` (admin đặt ghim khi duyệt).
- **Test không gọi mạng**: lưu HTML/PDF mẫu ở `tests/fixtures/`, dùng `httpx.MockTransport`.
- Contract kiểm bằng chính `src/data/scripts/staging.py` trong test (consumer-driven) — crawler đổi định dạng sai là test đỏ.

## Thêm nguồn
1. Khảo sát: robots.txt, điều khoản, cấu trúc trang; cập nhật `sources.json` (`trang_thai`).
2. `ancu_crawler/sources/<ten>.py`: class kế thừa `Source`, `@register`, import trong `sources/__init__.py`.
3. Lưu trang mẫu vào `tests/fixtures/`, viết test parser.
