from __future__ import annotations

import pathlib

from .contract import Run
from .fetch import Fetcher


class Source:
    """Một nguồn dữ liệu. `crawl` dùng `fetcher` (robots.txt, giãn cách, lưu bằng chứng) và ghi vào `run`."""

    name: str = ""          # mã [a-z0-9_], khớp sources.json và ingest.batches.source
    entity: str = "projects"
    start_urls: list[str] = []

    def crawl(self, fetcher: Fetcher, run: Run, *, limit: int | None = None, pdf_dir: "pathlib.Path | None" = None) -> None:
        """`pdf_dir`: thư mục PDF người dùng tự tải bằng trình duyệt (nguồn chặn tải tự động) — ghép theo số văn bản."""
        raise NotImplementedError
