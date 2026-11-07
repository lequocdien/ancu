"""Unit test cho validator của build_data.py (stdlib unittest).

    python3 -I -m unittest discover -s src/data/scripts -p 'test_*.py' -v
"""
import copy
import importlib.util
import json
import pathlib
import unittest

_HERE = pathlib.Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("build_data", _HERE / "build_data.py")
bd = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(bd)

ROUTE_ID = "114bfa70-5447-58b6-ac1e-59ae01daa9c2"


def fc(*features):
    return {"type": "FeatureCollection", "features": list(features)}


def feature(props, geom):
    return {"type": "Feature", "properties": props, "geometry": geom}


def valid_data():
    routes = fc(feature({
        "id": ROUTE_ID, "name": "Metro số 1", "type": "metro", "status": "da_khai_thac", "expected_year": 2024,
        "color_hex": "#EF4444", "source_url": "https://mock.ancu.vn/tuyen", "verified_at": "2026-10-28",
    }, {"type": "LineString", "coordinates": [[106.6983, 10.7721], [106.7031, 10.7766]]}))
    nodes = fc(
        feature({"id": "5bb6fb99-d6a2-5008-bffc-df22460939b8", "route_id": ROUTE_ID, "name": "Ga Bến Thành",
                 "type": "ga_metro"}, {"type": "Point", "coordinates": [106.6983, 10.7721]}),
        feature({"id": "7eb8e164-510c-5165-9ac4-09ec96681116", "route_id": None, "name": "Sân bay Long Thành",
                 "type": "diem_hat_nhan"}, {"type": "Point", "coordinates": [107.03, 10.77]}),
    )
    projects = fc(feature({
        "id": "ffe14cd8-75bb-5a59-b5dd-a91c233c5cfc", "name": "NOXH A", "address": "Phường Thủ Đức, TP.HCM",
        "ward_code": "hcm_thu_duc", "service_area": "hcm_cu", "status": "nhan_ho_so",
        "legal_status": "du_dieu_kien_ban", "application_start": "2026-11-01", "application_end": "2026-11-18",
        "price_min": 22.5, "price_max": 24, "price_is_estimated": False, "unit_count": 1240,
        "developer": None, "cover_image_url": None, "source_url": "https://mock.ancu.vn/du-an",
        "verified_at": "2026-11-02",
    }, {"type": "Point", "coordinates": [106.772, 10.842]}))
    return routes, nodes, projects


class ValidateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lookups = bd.load_lookups()

    def errors(self, routes, nodes, projects):
        return bd.validate(routes, nodes, projects, self.lookups)

    def assertOneError(self, errors, *fragments):
        self.assertEqual(len(errors), 1, errors)
        for fragment in fragments:
            self.assertIn(fragment, errors[0])

    def test_valid_data_passes(self):
        self.assertEqual(self.errors(*valid_data()), [])

    def test_repo_geojson_passes(self):
        errors = []
        fcs = [bd.load_geojson(bd.GEOJSON_DIR / f"{n}.geojson", errors) for n in ("routes", "nodes", "projects")]
        self.assertEqual(errors, [])
        self.assertEqual(self.errors(*fcs), [])

    def test_coordinate_out_of_vietnam(self):
        routes, nodes, projects = valid_data()
        projects["features"][0]["geometry"]["coordinates"] = [2.35, 48.85]  # Paris
        self.assertOneError(self.errors(routes, nodes, projects), "projects.geojson", "ngoài khung Việt Nam")

    def test_swapped_lat_lng_hints(self):
        routes, nodes, projects = valid_data()
        nodes["features"][0]["geometry"]["coordinates"] = [10.7721, 106.6983]
        self.assertOneError(self.errors(routes, nodes, projects), "nodes.geojson", "ngoài miền", "đảo lat/lng")

    def test_invalid_coordinate_shape(self):
        routes, nodes, projects = valid_data()
        nodes["features"][0]["geometry"]["coordinates"] = [106.6983, "10.7721"]
        self.assertOneError(self.errors(routes, nodes, projects), "gồm 2 số")

    def test_linestring_needs_two_points(self):
        routes, nodes, projects = valid_data()
        routes["features"][0]["geometry"]["coordinates"] = [[106.6983, 10.7721]]
        self.assertOneError(self.errors(routes, nodes, projects), "ít nhất 2 điểm")

    def test_wrong_geometry_type(self):
        routes, nodes, projects = valid_data()
        routes["features"][0]["geometry"] = {"type": "Point", "coordinates": [106.6983, 10.7721]}
        self.assertOneError(self.errors(routes, nodes, projects), "LineString hoặc MultiLineString")

    def test_missing_required_property(self):
        routes, nodes, projects = valid_data()
        del routes["features"][0]["properties"]["name"]
        self.assertOneError(self.errors(routes, nodes, projects), "thiếu thuộc tính bắt buộc 'name'")

    def test_optional_property_may_be_absent(self):
        routes, nodes, projects = valid_data()
        del routes["features"][0]["properties"]["expected_year"]
        del projects["features"][0]["properties"]["price_is_estimated"]
        self.assertEqual(self.errors(routes, nodes, projects), [])
        self.assertIsNone(bd.to_app_routes(routes)[0]["expected_year"])
        self.assertIs(bd.to_app_projects(projects)[0]["price_is_estimated"], True)

    def test_null_in_required_property(self):
        routes, nodes, projects = valid_data()
        projects["features"][0]["properties"]["source_url"] = None
        self.assertOneError(self.errors(routes, nodes, projects), "'source_url' không được null")

    def test_unknown_property(self):
        routes, nodes, projects = valid_data()
        projects["features"][0]["properties"]["sourceUrl"] = "https://x.vn"
        self.assertOneError(self.errors(routes, nodes, projects), "thuộc tính lạ 'sourceUrl'")

    def test_duplicate_id(self):
        routes, nodes, projects = valid_data()
        nodes["features"][1]["properties"]["id"] = nodes["features"][0]["properties"]["id"]
        self.assertOneError(self.errors(routes, nodes, projects), "id trùng với features[0]")

    def test_dangling_route_id(self):
        routes, nodes, projects = valid_data()
        nodes["features"][0]["properties"]["route_id"] = "00000000-0000-0000-0000-000000000000"
        self.assertOneError(self.errors(routes, nodes, projects), "không có trong routes.geojson")

    def test_unknown_lookup_code(self):
        routes, nodes, projects = valid_data()
        routes["features"][0]["properties"]["type"] = "tau_dien"
        projects["features"][0]["properties"]["ward_code"] = "khong_ton_tai"
        errors = self.errors(routes, nodes, projects)
        self.assertEqual(len(errors), 2, errors)
        self.assertIn("danh mục route_types", errors[0])
        self.assertIn("danh mục administrative_units", errors[1])

    def test_ward_outside_service_area(self):
        routes, nodes, projects = valid_data()
        projects["features"][0]["properties"]["service_area"] = "dong_nai_cu"
        self.assertOneError(self.errors(routes, nodes, projects), "thuộc vùng 'hcm_cu'")

    def test_invalid_date(self):
        routes, nodes, projects = valid_data()
        routes["features"][0]["properties"]["verified_at"] = "28/10/2026"
        projects["features"][0]["properties"]["application_end"] = "2026-02-30"
        errors = self.errors(routes, nodes, projects)
        self.assertEqual(len(errors), 2, errors)
        self.assertTrue(all("YYYY-MM-DD" in e for e in errors))

    def test_source_url_must_be_http(self):
        routes, nodes, projects = valid_data()
        routes["features"][0]["properties"]["source_url"] = "ftp://mock.ancu.vn"
        self.assertOneError(self.errors(routes, nodes, projects), "http:// hoặc https://")

    def test_cross_field_checks(self):
        routes, nodes, projects = valid_data()
        projects["features"][0]["properties"].update(price_min=30, application_start="2026-12-01")
        errors = self.errors(routes, nodes, projects)
        self.assertEqual(len(errors), 2, errors)

    def test_reports_all_problems(self):
        routes, nodes, projects = valid_data()
        del routes["features"][0]["properties"]["status"]
        nodes["features"][0]["properties"]["type"] = "ben_xe"
        projects["features"][0]["geometry"]["coordinates"] = [200, 10]
        self.assertEqual(len(self.errors(routes, nodes, projects)), 3)


class ConvertTests(unittest.TestCase):
    def test_app_json_shape(self):
        routes, nodes, projects = valid_data()
        multi = copy.deepcopy(routes)
        coords = multi["features"][0]["geometry"]["coordinates"]
        multi["features"][0]["geometry"] = {"type": "MultiLineString", "coordinates": [coords, coords]}

        route = bd.to_app_routes(routes)[0]
        self.assertEqual(list(route), ["id", "name", "type", "status", "expected_year", "color_hex", "segments",
                                       "source_url", "verified_at"])
        self.assertEqual(route["segments"], [[{"lat": 10.7721, "lng": 106.6983}, {"lat": 10.7766, "lng": 106.7031}]])
        self.assertEqual(len(bd.to_app_routes(multi)[0]["segments"]), 2)

        node = bd.to_app_nodes(nodes)[0]
        self.assertEqual(list(node), ["id", "route_id", "name", "type", "location"])

        project = bd.to_app_projects(projects)[0]
        self.assertEqual(list(project)[4:6], ["service_area", "location"])
        self.assertEqual(json.dumps(project["price_max"]), "24.0")


if __name__ == "__main__":
    unittest.main()


class ServiceAreaTests(unittest.TestCase):
    """Ranh giới vùng phục vụ (service_areas.geojson)."""

    @classmethod
    def setUpClass(cls):
        cls.lookups = bd.load_lookups()

    @staticmethod
    def area(code="hcm_cu", ring=None):
        # Hình vuông bao Thủ Đức (dự án mẫu ở [106.772, 10.842]).
        ring = ring or [[106.7, 10.8], [106.9, 10.8], [106.9, 10.9], [106.7, 10.9], [106.7, 10.8]]
        return feature({"code": code, "is_mock": True, "source_url": "https://mock.ancu.vn/rg", "verified_at": "2026-11-07"},
                       {"type": "Polygon", "coordinates": [ring]})

    def run_validate(self, *areas):
        routes, nodes, projects = valid_data()
        return bd.validate(routes, nodes, projects, self.lookups, fc(*areas))

    def test_valid_area_passes(self):
        self.assertEqual(self.run_validate(self.area()), [])

    def test_project_outside_its_area_fails(self):
        far = [[106.3, 10.4], [106.4, 10.4], [106.4, 10.5], [106.3, 10.5], [106.3, 10.4]]
        errors = self.run_validate(self.area(ring=far))
        self.assertTrue(any("nằm ngoài ranh giới vùng 'hcm_cu'" in e for e in errors), errors)

    def test_unclosed_ring_fails(self):
        ring = [[106.7, 10.8], [106.9, 10.8], [106.9, 10.9], [106.7, 10.9]]
        self.assertTrue(any("chưa khép kín" in e for e in self.run_validate(self.area(ring=ring + [[106.8, 10.95]]))))

    def test_hole_is_rejected(self):
        bad = self.area()
        bad["geometry"]["coordinates"].append([[106.75, 10.82], [106.76, 10.82], [106.76, 10.83], [106.75, 10.82]])
        self.assertTrue(any("đúng 1 vòng ngoài" in e for e in self.run_validate(bad)))

    def test_duplicate_code_and_unknown_code(self):
        errors = self.run_validate(self.area(), self.area(), self.area(code="ha_noi"))
        self.assertTrue(any("trùng" in e for e in errors))
        self.assertTrue(any("'ha_noi' không có trong danh mục service_areas" in e for e in errors))

    def test_app_json_drops_closing_point(self):
        out = bd.to_app_service_areas(fc(self.area()))
        self.assertEqual(len(out[0]["polygons"][0]), 4)
        self.assertEqual(out[0]["polygons"][0][0], {"lat": 10.8, "lng": 106.7})

    def test_repo_boundaries_contain_all_projects(self):
        errors: list[str] = []
        fcs = {n: bd.load_geojson(bd.GEOJSON_DIR / f"{n}.geojson", errors)
               for n in ("routes", "nodes", "projects", "service_areas")}
        self.assertEqual(errors, [])
        self.assertEqual(bd.validate(fcs["routes"], fcs["nodes"], fcs["projects"], self.lookups, fcs["service_areas"]), [])
