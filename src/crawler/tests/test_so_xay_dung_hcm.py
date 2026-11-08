"""Nguồn Sở XD TP.HCM — fixture là trích HTML thật (2026-11-08), không gọi mạng."""
from __future__ import annotations

import json
import pathlib
import sys
import tempfile
import unittest

import httpx

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT.parent / "data" / "scripts"))
import staging  # noqa: E402

from app.core import Fetcher, Run, document_number, extract_fields  # noqa: E402
from app.sources import so_xay_dung_hcm as sxd  # noqa: E402

FIX = pathlib.Path(__file__).parent / "fixtures"
LISTING = (FIX / "sxd_danhsach.html").read_text(encoding="utf-8")
ARTICLE = (FIX / "sxd_danhmuc.html").read_text(encoding="utf-8")
ARTICLE_URL = "https://soxaydung.hochiminhcity.gov.vn/Tin-tuc/Chi-tiet-bai-viet/tin/d982db54-b849-4a0a-9c7f-ef3a2b8df125"

SAMPLE_PDF_TEXT = """SỞ XÂY DỰNG CỘNG HÒA XÃ HỘI CHỦ NGHĨA VIỆT NAM
Số: 36379/SXD-QLN&TTBĐS ... Công bố thời gian tiếp nhận hồ sơ dự án nhà ở xã hội
Dự án có tổng số 1.240 căn hộ, trong đó 1.000 căn để bán. Giá bán dự kiến 22.500.000 đồng/m2 đến 24.000.000 đồng/m²
(đã bao gồm VAT). Thời gian tiếp nhận hồ sơ: từ ngày 15/10/2026 đến ngày 15/11/2026."""


class CatalogTests(unittest.TestCase):
    def test_find_catalog_in_listing(self):
        self.assertEqual(sxd.SoXayDungHCM.find_catalog(LISTING), ARTICLE_URL)

    def test_parse_catalog_lines(self):
        entries = sxd.SoXayDungHCM.parse_catalog(ARTICLE, ARTICLE_URL)
        self.assertEqual([e["number"] for e in entries], ["36379", "35289", "37857", "37302"])
        self.assertEqual(entries[0]["name"], "Khu dân cư Phường Long Trường, thành phố Thủ Đức")
        self.assertEqual(entries[0]["issued"], "2026-10-09")
        self.assertEqual(entries[0]["symbol"], "SXD-QLN&TTBĐS")

    def test_area_and_address_heuristics(self):
        # Hiệp Thành (Quận 12 và Thủ Dầu Một) — cả hai nay thuộc TP.HCM mới → đoán được.
        self.assertEqual(sxd.guess_service_area("Khu chung cư giá thấp Hiệp Thành III - Khối E, F"), "tp_hcm")
        # Thạnh Tân trùng tên với Tây Ninh → không đoán.
        self.assertIsNone(sxd.guess_service_area("Khu chung cư Nhà ở xã hội Thạnh Tân (Giai đoạn 1)"))
        self.assertEqual(sxd.guess_service_area("Khu dân cư tại phường Dĩ An"), "tp_hcm")
        self.assertEqual(sxd.guess_service_area("Phường Phú Mỹ, Bà Rịa – Vũng Tàu"), "tp_hcm")
        self.assertEqual(sxd.guess_service_area("Phường Linh Trung, thành phố Thủ Đức"), "tp_hcm")
        self.assertIsNone(sxd.guess_service_area("Dự án X"))
        _, addr = sxd.split_name_address("Dự án Nhà ở xã hội tại số 35 Lê Văn Chí, Phường Linh Trung, thành phố Thủ Đức")
        self.assertEqual(addr, "số 35 Lê Văn Chí, Phường Linh Trung, thành phố Thủ Đức")
        _, addr = sxd.split_name_address("Khu dân cư Phường Long Trường, thành phố Thủ Đức")
        self.assertEqual(addr, "Phường Long Trường, thành phố Thủ Đức")

    def test_document_number_from_filename(self):
        self.assertEqual(document_number("3.3.1 20261009-36379-Cong bo thoi gian tiep nhan.pdf"), "36379")
        self.assertEqual(document_number("! 33745. TUYEN TRUYEN VE PCRT.pdf"), "33745")


class PdfFieldTests(unittest.TestCase):
    def test_extracts_window_units_price(self):
        f = extract_fields(SAMPLE_PDF_TEXT)
        self.assertEqual((f.application_start, f.application_end), ("2026-10-15", "2026-11-15"))
        self.assertEqual(f.unit_count, 1240)
        self.assertEqual((f.price_min, f.price_max), (22.5, 24.0))
        self.assertIn("1.240 căn", f.evidence["unit_count"])
        self.assertTrue(any("nhiều con số căn" in w for w in f.warnings))

    def test_scanned_pdf(self):
        f = extract_fields("   \n ")
        self.assertEqual(f.properties(), {})
        self.assertIn("bản scan", f.warnings[0])

    def test_ambiguous_windows_are_not_guessed(self):
        f = extract_fields("Đợt 1 từ ngày 01/10/2026 đến ngày 10/10/2026; đợt 2 từ ngày 01/11/2026 đến ngày 10/11/2026 ...")
        self.assertIsNone(f.application_start)
        self.assertTrue(any("nhiều khoảng" in w for w in f.warnings))

    def test_word_dates_and_decomposed_unicode(self):
        import unicodedata
        text = unicodedata.normalize("NFD", "Tiếp nhận từ ngày 1 tháng 12 năm 2026 đến hết ngày 20 tháng 12 năm 2026, gồm 650 căn")
        f = extract_fields(text)
        self.assertEqual((f.application_start, f.application_end, f.unit_count), ("2026-12-01", "2026-12-20", 650))


class EndToEndTests(unittest.TestCase):
    def run_crawl(self, pdf_dir=None):
        def handler(request: httpx.Request) -> httpx.Response:
            if request.url.path == "/robots.txt":
                return httpx.Response(200, text="User-agent: *\nDisallow: /admin/\n")
            if request.url.path.endswith("/BaiViet/StyleView"):
                assert request.headers["ModuleId"] == "2635" and request.url.params["ViewStyle"] == "DanhSach"
                return httpx.Response(200, text=LISTING, headers={"content-type": "text/html"})
            if str(request.url) == ARTICLE_URL:
                return httpx.Response(200, text=ARTICLE, headers={"content-type": "text/html"})
            if request.url.path.startswith("/Files/"):
                raise AssertionError("không được tải PDF tự động (WAF chặn — phương án A)")
            return httpx.Response(404)

        tmp = tempfile.mkdtemp()
        run = Run(source="so_xay_dung_hcm", entity="projects", root=pathlib.Path(tmp))
        with Fetcher(evidence_dir=run.raw_dir, min_interval=0, sleep=lambda s: None,
                     transport=httpx.MockTransport(handler)) as fetcher:
            sxd.SoXayDungHCM().crawl(fetcher, run, pdf_dir=pdf_dir)
        return run

    def test_crawl_without_pdfs(self):
        run = self.run_crawl()
        self.assertEqual(len(run.features), 4)
        by_number = {f["properties"]["_raw"]["so_van_ban"]: f["properties"] for f in run.features}
        self.assertTrue(by_number["36379"]["source_url"].endswith(".pdf"))
        self.assertIn("%20", by_number["36379"]["source_url"])                 # tên file có dấu cách → mã hóa
        self.assertEqual(by_number["37302"]["source_url"], ARTICLE_URL)         # link PDF sai trên trang
        self.assertTrue(any("37302: link PDF" in w for w in run.warnings))
        self.assertEqual(by_number["37302"]["service_area"], "tp_hcm")        # Hiệp Thành: Q.12 hay Thủ Dầu Một đều TP.HCM mới
        self.assertFalse(any("37302: không đoán được vùng" in w for w in run.warnings))
        # Lần chạy sau cùng số văn bản → cùng id (staging nhận ra bản cũ).
        self.assertEqual({f["properties"]["id"] for f in self.run_crawl().features}, {f["properties"]["id"] for f in run.features})
        # Đầu ra qua được contract của phía tiêu thụ.
        staging.read_crawler_file(json.loads(run.write().read_text(encoding="utf-8")))

    def test_crawl_with_local_pdfs(self):
        with tempfile.TemporaryDirectory() as pdf_dir:
            pdf = pathlib.Path(pdf_dir) / "3.3.1 20261009-36379-Cong bo thoi gian tiep nhan ho so du an NOXH KDC phuong Long Truong.pdf"
            pdf.write_bytes(b"%PDF-fake")
            (pathlib.Path(pdf_dir) / "99999-khong-co.pdf").write_bytes(b"%PDF-fake")
            original = sxd.read_pdf_text
            sxd.read_pdf_text = lambda path: SAMPLE_PDF_TEXT
            try:
                run = self.run_crawl(pathlib.Path(pdf_dir))
            finally:
                sxd.read_pdf_text = original
        props = next(f["properties"] for f in run.features if f["properties"]["_raw"]["so_van_ban"] == "36379")
        self.assertEqual((props["application_start"], props["unit_count"], props["price_min"]), ("2026-10-15", 1240, 22.5))
        self.assertEqual(props["_raw"]["pdf_local"], pdf.name)
        self.assertTrue(any("35289: chưa có PDF" in w for w in run.warnings))
        self.assertTrue(any("99999" in w and "không có trong danh mục" in w for w in run.warnings))
        staging.read_crawler_file(json.loads(run.write().read_text(encoding="utf-8")))


class DefaultPdfDirTests(unittest.TestCase):
    def test_default_dir_only_when_it_has_pdfs(self):
        from app import cli
        original = cli.PDF_ROOT
        with tempfile.TemporaryDirectory() as tmp:
            cli.PDF_ROOT = pathlib.Path(tmp)
            try:
                folder = pathlib.Path(tmp) / "so_xay_dung_hcm"
                folder.mkdir()
                (folder / ".gitkeep").touch()
                self.assertIsNone(cli.default_pdf_dir("so_xay_dung_hcm"))      # chỉ có .gitkeep
                (folder / "x 20261009-36379-y.pdf").write_bytes(b"%PDF")
                self.assertEqual(cli.default_pdf_dir("so_xay_dung_hcm"), folder)
            finally:
                cli.PDF_ROOT = original


if __name__ == "__main__":
    unittest.main()
