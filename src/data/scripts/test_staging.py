"""Test staging.py + build_data.py --stage (chỉ thư viện chuẩn, không cần DB)."""
import json
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import build_data  # noqa: E402
import staging  # noqa: E402

PROJECT_ID = "6f1c2a4e-1111-4a2b-9c3d-2e4f5a6b7c8d"


def crawler_file(features, **header):
    return {"type": "FeatureCollection",
            "ancu": {"contract_version": 1, "entity": "projects", "source": "so_xay_dung_hcm",
                     "run_ref": "2026-11-08_so_xay_dung_hcm", **header},
            "features": features}


def project(**props):
    base = {"id": PROJECT_ID, "name": "NOXH O'Neil", "address": "Phường Thủ Đức", "service_area": "hcm_cu",
            "status": "sap_mo", "legal_status": "chu_truong_dau_tu", "price_min": 18, "price_max": 20.5,
            "source_url": "https://soxaydung.hochiminhcity.gov.vn/a", "_crawled_at": "2026-11-08T09:00:00+07:00",
            "_evidence": "runs/2026-11-08_so_xay_dung_hcm/raw/a.html", "_raw": {"tieu_de": "NOXH O'Neil"}}
    base.update(props)
    return {"type": "Feature", "geometry": None, "properties": base}


class ContractTests(unittest.TestCase):
    def test_valid_project_without_location(self):
        header, feats = staging.read_crawler_file(crawler_file([project()]))
        self.assertEqual(header["entity"], "projects")
        self.assertEqual(len(feats), 1)

    def test_header_problems(self):
        with self.assertRaises(staging.StagingError) as ctx:
            staging.read_crawler_file(crawler_file([project()], contract_version=2, entity="du_an", source="Sở XD"))
        self.assertEqual(len(ctx.exception.problems), 3)

    def test_missing_header(self):
        with self.assertRaises(staging.StagingError):
            staging.read_crawler_file({"type": "FeatureCollection", "features": []})

    def test_feature_problems(self):
        bad = [project(id="khong-phai-uuid", gia="20tr", price_max="20"),
               {"type": "Feature", "geometry": {"type": "Point", "coordinates": [10.8, 106.7]}, "properties": {"id": PROJECT_ID}}]
        with self.assertRaises(staging.StagingError) as ctx:
            staging.read_crawler_file(crawler_file(bad))
        text = "\n".join(ctx.exception.problems)
        self.assertIn("UUID", text)
        self.assertIn("thuộc tính lạ 'gia'", text)
        self.assertIn("'price_max' phải là số", text)
        self.assertIn("lng 102–110", text)   # đảo lat/lng

    def test_duplicate_ids(self):
        with self.assertRaises(staging.StagingError) as ctx:
            staging.read_crawler_file(crawler_file([project(), project()]))
        self.assertIn("trùng", ctx.exception.problems[0])

    def test_verified_at_only_allowed_for_manual_files(self):
        problems: list[str] = []
        staging.check_feature("projects", project(verified_at="2026-11-08"), "x", problems)
        self.assertTrue(any("verified_at" in p for p in problems))
        problems = []
        staging.check_feature("projects", project(verified_at="2026-11-08"), "x", problems, manual=True)
        self.assertEqual(problems, [])


class SqlTests(unittest.TestCase):
    def test_sql_escapes_and_types(self):
        sql = staging.stage_sql([("projects", [project()])], source="so_xay_dung_hcm", run_ref="r1", silent=True,
                                note=None, batch_id="00000000-0000-0000-0000-00000000b001")
        self.assertIn("'NOXH O''Neil'", sql)                       # nháy đơn được escape
        self.assertIn("'00000000-0000-0000-0000-00000000b001', 'so_xay_dung_hcm', 'r1', 1, true", sql)
        self.assertIn("'2026-11-08T09:00:00+07:00'::timestamptz", sql)
        self.assertIn('"tieu_de": "NOXH O\'\'Neil"', sql)          # _raw thành jsonb
        self.assertIn(", null, '{", sql)                            # thiếu vị trí → null
        self.assertTrue(sql.index("begin;") < sql.index("insert into ingest.project_candidates") < sql.index("commit;"))

    def test_routes_before_nodes_and_linestring_becomes_multi(self):
        route = {"type": "Feature", "geometry": {"type": "LineString", "coordinates": [[106.7, 10.77], [106.72, 10.79]]},
                 "properties": {"id": "00000000-0000-0000-0000-00000000a001", "name": "M", "type": "metro"}}
        node = {"type": "Feature", "geometry": {"type": "Point", "coordinates": [106.71, 10.78]},
                "properties": {"id": "00000000-0000-0000-0000-00000000a002", "route_id": "00000000-0000-0000-0000-00000000a001",
                               "name": "Ga", "type": "ga_metro"}}
        sql = staging.stage_sql([("nodes", [node]), ("routes", [route])], source="qgis_manual", run_ref=None,
                                silent=False, note="đợt đầu", default_accuracy="minh_hoa")
        self.assertLess(sql.index("route_candidates"), sql.index("node_candidates"))
        self.assertIn("MULTILINESTRING((106.7 10.77, 106.72 10.79))", sql)
        self.assertIn("POINT(106.71 10.78)", sql)
        self.assertEqual(sql.count("'minh_hoa'"), 2)


class CliTests(unittest.TestCase):
    def test_stage_crawler_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = pathlib.Path(tmp) / "features.geojson"
            src.write_text(json.dumps(crawler_file([project()]), ensure_ascii=False), encoding="utf-8")
            out = pathlib.Path(tmp) / "stage.sql"
            self.assertEqual(build_data.main(["--stage", str(src), "--silent", "--out", str(out)]), 0)
            self.assertIn("insert into ingest.project_candidates", out.read_text(encoding="utf-8"))

    def test_manual_requires_accuracy(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = pathlib.Path(tmp) / "stage.sql"
            self.assertEqual(build_data.main(["--stage-manual", "--out", str(out)]), 1)   # mock chưa có geometry_accuracy
            self.assertEqual(build_data.main(["--stage-manual", "--default-accuracy", "minh_hoa", "--out", str(out)]), 0)
            sql = out.read_text(encoding="utf-8")
            self.assertEqual(sql.count("insert into ingest.route_candidates"), 1)
            self.assertIn("'qgis_manual'", sql)
            # verified_at do người duyệt đặt: không phải CỘT của bản nháp (chỉ còn trong `raw` để truy vết).
            columns = sql.split("insert into ingest.route_candidates (")[1].split(")")[0]
            self.assertNotIn("verified_at", columns)


if __name__ == "__main__":
    unittest.main()
