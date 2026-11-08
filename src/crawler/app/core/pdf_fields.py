"""Trích trường từ chữ của công văn công bố tiếp nhận hồ sơ NOXH (PDF người dùng tự tải bằng trình duyệt).

Heuristic — công văn không theo mẫu cố định. Nguyên tắc: chỉ điền khi chắc (đúng 1 giá trị hợp lệ); mơ hồ thì để trống
+ cảnh báo, admin đọc PDF và điền khi duyệt. Mỗi giá trị kèm đoạn trích (`evidence`) để admin đối chiếu nhanh.
PDF scan (không có lớp chữ) → không trích được → cảnh báo "cần nhập tay" (OCR cần thư viện mới — chưa duyệt).
"""
from __future__ import annotations

import pathlib
import re
import unicodedata
from dataclasses import dataclass, field
from datetime import date

_DATE = r"(\d{1,2})\s*[/\-.]\s*(\d{1,2})\s*[/\-.]\s*(\d{4})"
_DATE_WORDS = r"(\d{1,2})\s+tháng\s+(\d{1,2})\s+năm\s+(\d{4})"


def normalize(text: str) -> str:
    """NFC + gộp khoảng trắng — PDF hay tách dấu (NFD) và xuống dòng giữa câu."""
    return re.sub(r"\s+", " ", unicodedata.normalize("NFC", text)).strip()


def _to_date(d: str, m: str, y: str) -> date | None:
    try:
        return date(int(y), int(m), int(d))
    except ValueError:
        return None


@dataclass
class PdfFields:
    application_start: str | None = None
    application_end: str | None = None
    unit_count: int | None = None
    price_min: float | None = None   # triệu đồng/m²
    price_max: float | None = None
    evidence: dict[str, str] = field(default_factory=dict)
    warnings: list[str] = field(default_factory=list)

    def properties(self) -> dict:
        return {k: v for k, v in {
            "application_start": self.application_start, "application_end": self.application_end,
            "unit_count": self.unit_count, "price_min": self.price_min, "price_max": self.price_max,
        }.items() if v is not None}


def _snippet(text: str, match: re.Match, pad: int = 60) -> str:
    return text[max(0, match.start() - pad): match.end() + pad]


def extract_fields(raw_text: str) -> PdfFields:
    text = normalize(raw_text)
    out = PdfFields()
    if len(text) < 40:
        out.warnings.append("PDF không có lớp chữ (bản scan) — cần nhập tay khi duyệt")
        return out

    # Thời gian tiếp nhận hồ sơ: "từ ngày 15/10/2026 đến ngày 15/11/2026" (hoặc "15 tháng 10 năm 2026").
    windows = []
    for pattern in (rf"từ\s+ngày\s+{_DATE}\s+đến\s+(?:hết\s+)?ngày\s+{_DATE}",
                    rf"từ\s+ngày\s+{_DATE_WORDS}\s+đến\s+(?:hết\s+)?ngày\s+{_DATE_WORDS}"):
        for m in re.finditer(pattern, text, re.IGNORECASE):
            start, end = _to_date(*m.group(1, 2, 3)), _to_date(*m.group(4, 5, 6))
            if start and end and start <= end:
                windows.append((start, end, _snippet(text, m)))
    unique_windows = {(s, e) for s, e, _ in windows}
    if len(unique_windows) == 1:
        s, e, snip = windows[0]
        out.application_start, out.application_end = s.isoformat(), e.isoformat()
        out.evidence["application_window"] = snip
    elif len(unique_windows) > 1:
        out.warnings.append(f"nhiều khoảng thời gian tiếp nhận ({len(unique_windows)}) — kiểm tra tay")
    else:
        out.warnings.append("không thấy thời gian tiếp nhận hồ sơ")

    # Số căn: "tổng số 1.240 căn", "gồm 980 căn hộ".
    counts = []
    for m in re.finditer(r"(\d{1,3}(?:[.,]\d{3})+|\d{1,5})\s*căn(?:\s+hộ|\s+nhà)?", text, re.IGNORECASE):
        value = int(re.sub(r"[.,]", "", m.group(1)))
        if value > 0:
            counts.append((value, _snippet(text, m)))
    if counts:
        # Công văn thường nêu tổng rồi chia nhỏ (bán / thuê mua…) → lấy số lớn nhất, ghi cảnh báo nếu có nhiều số.
        value, snip = max(counts, key=lambda c: c[0])
        out.unit_count = value
        out.evidence["unit_count"] = snip
        if len({c[0] for c in counts}) > 1:
            out.warnings.append(f"nhiều con số căn ({sorted({c[0] for c in counts})}) — đã lấy lớn nhất, kiểm tra tay")
    else:
        out.warnings.append("không thấy số căn")

    # Giá: "giá bán 22.500.000 đồng/m²" → 22,5 triệu/m². Chỉ nhận đơn vị đồng/m² (giá cả căn không quy đổi được).
    prices = []
    for m in re.finditer(r"(\d{1,3}(?:[.,]\d{3}){2,})\s*(?:đồng|đ|vnđ)\s*/\s*m\s*(?:2|²)", text, re.IGNORECASE):
        value = int(re.sub(r"[.,]", "", m.group(1))) / 1_000_000
        if 1 <= value < 10_000:
            prices.append((round(value, 2), _snippet(text, m)))
    if prices:
        values = sorted({p[0] for p in prices})
        out.price_min, out.price_max = values[0], values[-1]
        out.evidence["price"] = prices[0][1]
    else:
        out.warnings.append("không thấy giá (đồng/m²) — có thể chưa phê duyệt giá")
    return out


def read_pdf_text(path: pathlib.Path) -> str:
    import pdfplumber

    with pdfplumber.open(path) as pdf:
        return "\n".join(page.extract_text() or "" for page in pdf.pages)


def document_number(filename: str) -> str | None:
    """Số văn bản trong tên file của Sở: '3.3.1 20261009-36379-Cong bo….pdf' → '36379'."""
    m = re.search(r"\d{8}-(\d{3,6})-", filename) or re.search(r"(?<!\d)(\d{4,6})(?!\d)", filename)
    return m.group(1) if m else None
