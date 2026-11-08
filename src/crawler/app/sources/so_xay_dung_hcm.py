"""Sở Xây dựng TP.HCM — "Danh mục các dự án nhà ở xã hội đang tiếp nhận hồ sơ mua, thuê, thuê mua".

Khảo sát 2026-11-08 (sources.json): robots.txt cho phép; danh sách nạp bằng JS (endpoint StyleView mà chính trang gọi);
mỗi dự án = 1 dòng trong bài + 1 PDF công văn. **PDF bị WAF chặn tải tự động → KHÔNG lách**: người dùng tự tải bằng
trình duyệt vào một thư mục, chạy `--pdf-dir` để ghép theo số văn bản (phương án A, quyết định 2026-11-08).

Mỗi CÔNG VĂN = một bản nháp (id từ số văn bản). Đợt mới của dự án đã có trong An Cư: admin đổi `id` bản nháp thành id
dự án cũ trong DBeaver trước khi duyệt (README).
"""
from __future__ import annotations

import pathlib
import re
from datetime import date
from urllib.parse import quote, urljoin

from bs4 import BeautifulSoup

from ..core import Fetcher, Run, Source, document_number, extract_fields, normalize, read_pdf_text
from . import register

BASE = "https://soxaydung.hochiminhcity.gov.vn"
LISTING_ENDPOINT = BASE + "/DesktopModules/MVC/TinTucModule/BaiViet/StyleView"
LISTING_PARAMS = {"ViewStyle": "DanhSach", "moduleID": 2635}
LISTING_HEADERS = {"ModuleId": "2635", "TabId": "1499", "X-Requested-With": "XMLHttpRequest"}
CATALOG_TITLE = "danh mục các dự án nhà ở xã hội đang tiếp nhận hồ sơ"

# "- <tên, địa bàn>: <số>/<ký hiệu> ngày 09 tháng 10 năm 2026"
LINE_RE = re.compile(
    r"^[-–•]\s*(?P<name>.+?)\s*:\s*(?P<number>\d{3,6})\s*/\s*(?P<symbol>\S+)\s+ngày\s+"
    r"(?P<d>\d{1,2})\s+tháng\s+(?P<m>\d{1,2})\s+năm\s+(?P<y>\d{4})", re.IGNORECASE)

# Đoán vùng phục vụ (địa giới MỚI, sau 1/7/2025) CHỈ theo địa danh KHÔNG trùng tên với tỉnh khác. TP.HCM mới gồm
# TP.HCM cũ + Bình Dương cũ + Bà Rịa – Vũng Tàu cũ → Hiệp Thành (Quận 12 / Thủ Dầu Một) nay an toàn: cả hai đều tp_hcm.
# Thạnh Tân (cũng có ở Tây Ninh) vẫn bị loại — đoán sai nguy hiểm hơn để trống (admin điền khi duyệt).
AREA_HINTS = [
    ("tp_hcm", (
        # TP.HCM cũ
        "thủ đức", "bình chánh", "củ chi", "hóc môn", "nhà bè", "cần giờ", "bình tân", "gò vấp",
        "bình thạnh", "phú nhuận", "tân bình", "hiệp thành",
        # Bình Dương cũ
        "thủ dầu một", "dĩ an", "thuận an", "bến cát", "tân uyên", "bàu bàng", "bình dương",
        # Bà Rịa – Vũng Tàu cũ
        "vũng tàu", "bà rịa", "phú mỹ", "long điền", "đất đỏ", "côn đảo")),
]


def guess_service_area(text: str) -> str | None:
    lowered = text.lower()
    for area, hints in AREA_HINTS:
        if any(h in lowered for h in hints):
            return area
    return None


def split_name_address(text: str) -> tuple[str, str | None]:
    """'Dự án NOXH tại số 35 Lê Văn Chí, Phường Linh Trung, …' → (cả câu, 'số 35 Lê Văn Chí, Phường Linh Trung, …')."""
    if " tại " in text:
        return text, text.split(" tại ", 1)[1].strip()
    if "," in text:
        rest = text.split(",", 1)[1].strip()
        if re.search(r"\b(phường|xã|quận|huyện|thành phố|tp\.?)\b", rest, re.IGNORECASE):
            head = text.split(",", 1)[0]
            area = re.search(r"\b(phường|xã)\s+.+$", head, re.IGNORECASE)
            return text, ((area.group(0) + ", ") if area else "") + rest
    return text, None


@register
class SoXayDungHCM(Source):
    name = "so_xay_dung_hcm"
    entity = "projects"
    start_urls = [LISTING_ENDPOINT]

    def crawl(self, fetcher: Fetcher, run: Run, *, limit=None, pdf_dir=None) -> None:
        listing = fetcher.get(LISTING_ENDPOINT, params=LISTING_PARAMS, headers=LISTING_HEADERS)
        article_url = self.find_catalog(listing.text)
        if article_url is None:
            run.warn("không thấy bài 'Danh mục các dự án nhà ở xã hội đang tiếp nhận hồ sơ' — trang có thể đã đổi cấu trúc")
            return
        article = fetcher.get(article_url)
        pdfs = self.local_pdfs(pdf_dir, run) if pdf_dir else {}
        for entry in self.parse_catalog(article.text, article.url)[:limit]:
            self.add_entry(run, entry, article, pdfs)
        unused = set(pdfs) - {e["number"] for e in self.parse_catalog(article.text, article.url)}
        for number in sorted(unused):
            run.warn(f"PDF {pdfs[number].name}: số văn bản {number} không có trong danh mục — bỏ qua")

    @staticmethod
    def find_catalog(listing_html: str) -> str | None:
        soup = BeautifulSoup(listing_html, "html.parser")
        for a in soup.find_all("a", href=True):
            if CATALOG_TITLE in normalize(a.get_text(" ")).lower():
                return urljoin(BASE, a["href"])
        return None

    @staticmethod
    def parse_catalog(article_html: str, article_url: str) -> list[dict]:
        soup = BeautifulSoup(article_html, "html.parser")
        body = soup.select_one("#noidungchitiet") or soup
        entries = []
        for p in body.find_all("p"):
            text = normalize(p.get_text(" "))
            m = LINE_RE.match(text)
            if not m:
                continue
            link = p.find("a", href=True)
            href = link["href"] if link else None
            entries.append({
                "text": text, "name": normalize(m.group("name")), "number": m.group("number"),
                "symbol": m.group("symbol"), "issued": date(int(m.group("y")), int(m.group("m")), int(m.group("d"))).isoformat(),
                "pdf_path": href, "article_url": article_url,
            })
        return entries

    @staticmethod
    def local_pdfs(pdf_dir: pathlib.Path, run: Run) -> dict[str, pathlib.Path]:
        found: dict[str, pathlib.Path] = {}
        for path in sorted(pathlib.Path(pdf_dir).glob("*.pdf")):
            number = document_number(path.name)
            if number is None:
                run.warn(f"PDF {path.name}: không đọc được số văn bản trong tên file — đổi tên giữ nguyên tên gốc của Sở")
            elif number in found:
                run.warn(f"PDF {path.name}: trùng số văn bản {number} với {found[number].name}")
            else:
                found[number] = path
        return found

    def add_entry(self, run: Run, entry: dict, article, pdfs: dict[str, pathlib.Path]) -> None:
        name, address = split_name_address(entry["name"])
        props = {
            "name": name,
            "address": address,
            "service_area": guess_service_area(entry["name"]),
            # Danh mục "đang tiếp nhận hồ sơ" ⇒ đang nhận hồ sơ + đủ điều kiện bán (Sở đã công bố).
            "status": "nhan_ho_so",
            "legal_status": "du_dieu_kien_ban",
            "source_url": article.url,
        }
        number = entry["number"]
        pdf_path = entry["pdf_path"]
        # Trang có link PDF sai (vd dòng 37302 trỏ tới file tuyên truyền 33745) → không gắn nhầm, dùng link bài viết.
        if pdf_path and document_number(pathlib.PurePosixPath(pdf_path).name) == number:
            props["source_url"] = BASE + quote(pdf_path)
        elif pdf_path:
            run.warn(f"{number}: link PDF trên trang không khớp số văn bản ({pathlib.PurePosixPath(pdf_path).name}) — dùng link bài viết")
        if props["service_area"] is None:
            run.warn(f"{number}: không đoán được vùng — điền service_area khi duyệt")
        if props["address"] is None:
            run.warn(f"{number}: không tách được địa chỉ — điền khi duyệt")

        raw = {"dong_danh_muc": entry["text"], "so_van_ban": number, "ky_hieu": entry["symbol"],
               "ngay_ban_hanh": entry["issued"], "bai_viet": entry["article_url"], "pdf_tren_trang": pdf_path}
        evidence = str(article.evidence_path) if article.evidence_path else None
        local = pdfs.get(number)
        if local is not None:
            fields = extract_fields(read_pdf_text(local))
            props.update(fields.properties())
            raw["pdf_local"] = local.name
            raw["pdf_trich"] = fields.evidence
            for w in fields.warnings:
                run.warn(f"{number}: {w}")
            evidence = str(local)
        elif pdfs:
            run.warn(f"{number}: chưa có PDF trong --pdf-dir — thiếu ngày nhận hồ sơ / số căn / giá")
        run.add(f"so_van_ban:{number}", props, evidence=evidence, raw=raw)
