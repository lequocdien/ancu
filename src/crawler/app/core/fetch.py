"""Tải trang có kỷ luật (data-strategy.md 2b): tôn trọng robots.txt, giãn cách theo host, User-Agent nêu tên,
lưu bản chụp gốc làm bằng chứng, thử lại có giới hạn. Mọi nguồn đều đi qua đây — không gọi httpx trực tiếp.
"""
from __future__ import annotations

import hashlib
import pathlib
import time
import urllib.robotparser
from dataclasses import dataclass
from urllib.parse import urlsplit

import httpx

# Tự xưng là bot (không giả trình duyệt). Không kèm thông tin liên hệ — quyết định của chủ dự án 2026-11-08.
USER_AGENT = "AnCuCrawler/0.1"


class FetchBlocked(Exception):
    """robots.txt không cho phép — nguồn phải được bỏ qua, không lách."""


@dataclass
class FetchResult:
    url: str
    status: int
    content: bytes
    content_type: str
    evidence_path: pathlib.Path | None

    @property
    def text(self) -> str:
        return self.content.decode("utf-8", errors="replace")


class Fetcher:
    def __init__(self, *, evidence_dir: pathlib.Path | None = None, min_interval: float = 3.0, max_retries: int = 2,
                 transport: httpx.BaseTransport | None = None, sleep=time.sleep, clock=time.monotonic) -> None:
        self.evidence_dir = evidence_dir
        self.min_interval = min_interval
        self.max_retries = max_retries
        self._sleep = sleep
        self._clock = clock
        self._last_request: dict[str, float] = {}
        self._robots: dict[str, urllib.robotparser.RobotFileParser] = {}
        self._client = httpx.Client(headers={"User-Agent": USER_AGENT}, timeout=30.0, follow_redirects=True,
                                    transport=transport)

    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> "Fetcher":
        return self

    def __exit__(self, *exc) -> None:
        self.close()

    def _wait_turn(self, host: str) -> None:
        last = self._last_request.get(host)
        if last is not None:
            remaining = self.min_interval - (self._clock() - last)
            if remaining > 0:
                self._sleep(remaining)
        self._last_request[host] = self._clock()

    def allowed(self, url: str) -> bool:
        parts = urlsplit(url)
        origin = f"{parts.scheme}://{parts.netloc}"
        parser = self._robots.get(origin)
        if parser is None:
            parser = urllib.robotparser.RobotFileParser()
            self._wait_turn(parts.netloc)
            try:
                response = self._client.get(f"{origin}/robots.txt")
                # Không có robots.txt (404) = cho phép; lỗi máy chủ/không tải được = thận trọng, chặn.
                if response.status_code == 404:
                    parser.parse([])
                elif response.status_code >= 400:
                    parser.parse(["User-agent: *", "Disallow: /"])
                else:
                    parser.parse(response.text.splitlines())
            except httpx.HTTPError:
                parser.parse(["User-agent: *", "Disallow: /"])
            self._robots[origin] = parser
        return parser.can_fetch(USER_AGENT, url)

    def get(self, url: str, *, params: dict | None = None, headers: dict | None = None) -> FetchResult:
        """`params`/`headers`: cho endpoint mà chính trang web gọi (vd danh sách nạp bằng JS) — không dùng để giả danh."""
        if headers and any(k.lower() == "user-agent" for k in headers):
            raise ValueError("không được đổi User-Agent (tự xưng là bot)")
        if not self.allowed(url):
            raise FetchBlocked(f"robots.txt không cho phép: {url}")
        host = urlsplit(url).netloc
        attempt = 0
        while True:
            self._wait_turn(host)
            try:
                response = self._client.get(url, params=params, headers=headers)
            except httpx.TransportError:
                if attempt >= self.max_retries:
                    raise
                attempt += 1
                self._sleep(self.min_interval * 2 ** attempt)
                continue
            if response.status_code in (429, 500, 502, 503, 504) and attempt < self.max_retries:
                attempt += 1
                retry_after = response.headers.get("Retry-After")
                delay = float(retry_after) if retry_after and retry_after.isdigit() else self.min_interval * 2 ** attempt
                self._sleep(delay)
                continue
            response.raise_for_status()
            return FetchResult(url=str(response.url), status=response.status_code, content=response.content,
                               content_type=response.headers.get("content-type", ""),
                               evidence_path=self._save_evidence(url, response))

    def _save_evidence(self, url: str, response: httpx.Response) -> pathlib.Path | None:
        if self.evidence_dir is None:
            return None
        self.evidence_dir.mkdir(parents=True, exist_ok=True)
        content_type = response.headers.get("content-type", "")
        ext = ".pdf" if "pdf" in content_type else ".html" if "html" in content_type else ".bin"
        path = self.evidence_dir / (hashlib.sha1(url.encode("utf-8")).hexdigest()[:16] + ext)
        path.write_bytes(response.content)
        return path
