"""Test crawler không gọi mạng (httpx.MockTransport + fixture). Contract kiểm bằng staging.py của src/data."""
from __future__ import annotations

import json
import pathlib
import re
import sys
import tempfile
import unittest
from datetime import datetime

import httpx
from bs4 import BeautifulSoup

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT.parent / "data" / "scripts"))   # phía tiêu thụ contract
import staging  # noqa: E402

from ancu_crawler.contract import Run, stable_id  # noqa: E402
from ancu_crawler.fetch import Fetcher, FetchBlocked, USER_AGENT  # noqa: E402
from ancu_crawler.sources.base import Source  # noqa: E402

FIXTURE = (pathlib.Path(__file__).parent / "fixtures" / "thong_bao_mau.html").read_bytes()


def transport(routes: dict[str, list[httpx.Response] | httpx.Response], seen: list[httpx.Request]):
    queues = {k: (v if isinstance(v, list) else [v]) for k, v in routes.items()}

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        queue = queues.get(str(request.url))
        if not queue:
            return httpx.Response(404)
        return queue.pop(0) if len(queue) > 1 else queue[0]
    return httpx.MockTransport(handler)


class FakeClock:
    def __init__(self):
        self.now = 0.0
        self.sleeps: list[float] = []

    def clock(self):
        return self.now

    def sleep(self, seconds):
        self.sleeps.append(seconds)
        self.now += seconds


class FetchTests(unittest.TestCase):
    def make(self, routes, tmp=None, **kw):
        self.seen: list[httpx.Request] = []
        self.clock = FakeClock()
        return Fetcher(transport=transport(routes, self.seen), sleep=self.clock.sleep, clock=self.clock.clock,
                       evidence_dir=pathlib.Path(tmp) if tmp else None, **kw)

    def test_robots_disallow_blocks_and_never_requests_page(self):
        f = self.make({"https://so.example/robots.txt": httpx.Response(200, text="User-agent: *\nDisallow: /noi-bo/")})
        with self.assertRaises(FetchBlocked):
            f.get("https://so.example/noi-bo/danh-sach")
        self.assertEqual([r.url.path for r in self.seen], ["/robots.txt"])

    def test_missing_robots_allows_but_broken_robots_blocks(self):
        ok = self.make({"https://a.example/p": httpx.Response(200, content=FIXTURE, headers={"content-type": "text/html"})})
        self.assertEqual(ok.get("https://a.example/p").status, 200)            # robots 404 → cho phép
        broken = self.make({"https://b.example/robots.txt": httpx.Response(503)})
        with self.assertRaises(FetchBlocked):                                    # không đọc được robots → chặn
            broken.get("https://b.example/p")

    def test_user_agent_and_rate_limit_per_host(self):
        f = self.make({"https://a.example/1": httpx.Response(200), "https://a.example/2": httpx.Response(200)}, min_interval=3.0)
        f.get("https://a.example/1")
        f.get("https://a.example/2")
        self.assertTrue(all(r.headers["user-agent"] == USER_AGENT for r in self.seen))
        self.assertGreaterEqual(sum(self.clock.sleeps), 6.0)   # robots → /1 → /2, cách nhau ≥ 3 giây

    def test_retries_server_errors_and_honors_retry_after(self):
        f = self.make({"https://a.example/p": [httpx.Response(429, headers={"Retry-After": "7"}), httpx.Response(503),
                                               httpx.Response(200, text="ok")]})
        self.assertEqual(f.get("https://a.example/p").text, "ok")
        self.assertIn(7.0, self.clock.sleeps)

    def test_gives_up_after_max_retries(self):
        f = self.make({"https://a.example/p": httpx.Response(500)}, max_retries=1)
        with self.assertRaises(httpx.HTTPStatusError):
            f.get("https://a.example/p")

    def test_saves_evidence(self):
        with tempfile.TemporaryDirectory() as tmp:
            f = self.make({"https://a.example/p": httpx.Response(200, content=FIXTURE, headers={"content-type": "text/html"})}, tmp)
            result = f.get("https://a.example/p")
            self.assertTrue(result.evidence_path.name.endswith(".html"))
            self.assertEqual(result.evidence_path.read_bytes(), FIXTURE)


class ContractTests(unittest.TestCase):
    def test_stable_id_is_deterministic_and_source_scoped(self):
        self.assertEqual(stable_id("so_xay_dung_hcm", "NOXH-001"), stable_id("so_xay_dung_hcm", " noxh-001 "))
        self.assertNotEqual(stable_id("so_xay_dung_hcm", "NOXH-001"), stable_id("maur_hcm", "NOXH-001"))

    def test_add_rejects_id_and_verified_at(self):
        run = Run(source="x_src", entity="projects", root=pathlib.Path("/tmp"))
        with self.assertRaises(ValueError):
            run.add("k", {"verified_at": "2026-11-08"})
        with self.assertRaises(ValueError):
            run.add("k", {"id": "abc"})


class DemoSource(Source):
    """Nguồn giả CHỈ dùng trong test: minh họa cách viết parser (bs4) + ghi feature theo contract."""
    name = "demo_test"
    entity = "projects"
    start_urls = ["https://so.example/thong-bao"]

    def crawl(self, fetcher, run, *, limit=None):
        page = fetcher.get(self.start_urls[0])
        soup = BeautifulSoup(page.content, "html.parser")
        for row in soup.select("table.du-an tr")[:limit]:
            code = row["data-ma"]
            props = {"name": row.select_one(".ten").get_text(strip=True),
                     "address": row.select_one(".dia-chi").get_text(strip=True),
                     "service_area": "hcm_cu", "status": "sap_mo", "legal_status": "du_dieu_kien_ban",
                     "source_url": page.url}
            prices = re.findall(r"\d+(?:,\d+)?", row.select_one(".gia").get_text())
            if len(prices) == 2:
                props["price_min"], props["price_max"] = (float(p.replace(",", ".")) for p in prices)
            else:
                run.warn(f"{code}: chưa có giá")
            dates = re.findall(r"\d{2}/\d{2}/\d{4}", row.select_one(".han").get_text())
            if len(dates) == 2:
                props["application_start"], props["application_end"] = (
                    datetime.strptime(d, "%d/%m/%Y").date().isoformat() for d in dates)
            run.add(code, props, evidence=str(page.evidence_path), raw={"html": str(row)})


class EndToEndTests(unittest.TestCase):
    def test_source_output_passes_staging_contract(self):
        with tempfile.TemporaryDirectory() as tmp:
            run = Run(source=DemoSource.name, entity="projects", root=pathlib.Path(tmp))
            with Fetcher(evidence_dir=run.raw_dir, min_interval=0, sleep=lambda s: None,
                         transport=transport({"https://so.example/thong-bao": httpx.Response(
                             200, content=FIXTURE, headers={"content-type": "text/html; charset=utf-8"})}, [])) as fetcher:
                DemoSource().crawl(fetcher, run)
            out = run.write()

            fc = json.loads(out.read_text(encoding="utf-8"))
            header, features = staging.read_crawler_file(fc)          # phía tiêu thụ chấp nhận
            self.assertEqual((header["entity"], header["source"]), ("projects", "demo_test"))
            self.assertEqual(len(features), 2)
            first = features[0]["properties"]
            self.assertEqual((first["price_min"], first["price_max"]), (18.5, 20.0))
            self.assertEqual(first["application_start"], "2026-12-01")
            self.assertIsNone(features[0]["geometry"])                  # vị trí: admin đặt khi duyệt
            self.assertTrue(pathlib.Path(first["_evidence"]).exists())
            report = json.loads((out.parent / "report.json").read_text(encoding="utf-8"))
            self.assertEqual(report["warnings"], ["NOXH-002: chưa có giá"])
            sql = staging.stage_sql([("projects", features)], source="demo_test", run_ref=header["run_ref"],
                                    silent=True, note=None)
            self.assertIn("insert into ingest.project_candidates", sql)


if __name__ == "__main__":
    unittest.main()
