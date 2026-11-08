from __future__ import annotations

from ..contract import Run
from ..fetch import Fetcher


class Source:
    """Một nguồn dữ liệu. `crawl` dùng `fetcher` (robots.txt, giãn cách, lưu bằng chứng) và ghi vào `run`."""

    name: str = ""          # mã [a-z0-9_], khớp sources.json và ingest.batches.source
    entity: str = "projects"
    start_urls: list[str] = []

    def crawl(self, fetcher: Fetcher, run: Run, *, limit: int | None = None) -> None:
        raise NotImplementedError
