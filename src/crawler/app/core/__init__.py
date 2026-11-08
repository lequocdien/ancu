"""Phần DÙNG CHUNG cho mọi nguồn — nguồn mới chỉ viết phần đọc trang trong `sources/`.

- `fetch`      tải trang có kỷ luật: robots.txt, giãn cách theo host, thử lại, lưu bằng chứng
- `contract`   contract đầu ra v1: id ổn định (UUID v5), Run → features.geojson + report.json
- `pdf_fields` trích ngày nhận hồ sơ / số căn / giá từ chữ của công văn PDF
- `source`     class cơ sở `Source` mà mỗi nguồn kế thừa
"""
from .contract import CONTRACT_VERSION, Run, stable_id
from .fetch import Fetcher, FetchBlocked, FetchResult, USER_AGENT
from .pdf_fields import PdfFields, document_number, extract_fields, normalize, read_pdf_text
from .source import Source

__all__ = [
    "CONTRACT_VERSION", "Run", "stable_id",
    "Fetcher", "FetchBlocked", "FetchResult", "USER_AGENT",
    "PdfFields", "document_number", "extract_fields", "normalize", "read_pdf_text",
    "Source",
]
