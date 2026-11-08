#!/usr/bin/env python3
"""Kiểm tra GeoJSON trong src/data/geojson/ rồi sinh mock JSON của app iOS và supabase/seed.sql.

Chuỗi nguồn dữ liệu (một nguồn sự thật cho tuyến, nút, dự án):

    src/data/geojson/*.geojson            (crawler / người nhập liệu sửa ở đây)
      → build_data.py: validate + ghi src/ios/AnCu/Data/Mock/Resources/{routes,nodes,projects}.json
      → generate_seed.py: đọc mock JSON (kèm Lookup/*.json) → src/supabase/seed.sql

Danh mục (Lookup/*.json) vẫn nằm trong app, đây là nơi đối chiếu mã trạng thái/loại.

    python3 -I src/data/scripts/build_data.py           # validate + ghi JSON app + sinh seed.sql
    python3 -I src/data/scripts/build_data.py --no-seed # chỉ ghi JSON app
    python3 -I src/data/scripts/build_data.py --check   # chỉ kiểm tra, không ghi; exit 1 nếu JSON app lệch GeoJSON (dùng cho CI)

Chỉ dùng thư viện chuẩn. Schema chi tiết: src/data/README.md.
"""
from __future__ import annotations

import argparse
import datetime
import importlib.util
import json
import math
import pathlib
import re
import sys

SRC = pathlib.Path(__file__).resolve().parent.parent.parent
GEOJSON_DIR = SRC / "data" / "geojson"
MOCK_DIR = SRC / "ios" / "AnCu" / "Data" / "Mock" / "Resources"
LOOKUP_DIR = MOCK_DIR / "Lookup"
SEED_SCRIPT = SRC / "supabase" / "scripts" / "generate_seed.py"

# Khung bao Việt Nam (gồm biển gần bờ) — bắt lỗi đảo lat/lng hoặc tọa độ rác, không phải ranh giới chính xác.
VN_BBOX = {"min_lng": 102.0, "max_lng": 110.0, "min_lat": 8.0, "max_lat": 23.5}

UUID_RE = re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
COLOR_RE = re.compile(r"^#[0-9A-Fa-f]{6}$")
URL_RE = re.compile(r"^https?://\S+$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")

# Kiểu giá trị cho phép (None trong tuple = được null).
STR, INT, NUM, BOOL = "chuỗi", "số nguyên", "số", "boolean"

# Thứ tự khóa = thứ tự khóa trong mock JSON của app (giữ diff git nhỏ).
# (tên, kiểu, bắt buộc có mặt, được null, danh mục lookup hoặc kiểm tra đặc biệt)
ROUTE_FIELDS = [
    ("id", STR, True, False, "uuid"),
    ("name", STR, True, False, None),
    ("type", STR, True, False, "route_types"),
    ("status", STR, True, False, "route_statuses"),
    ("expected_year", INT, False, True, "year"),
    ("color_hex", STR, True, False, "color"),
    ("geometry_accuracy", STR, False, True, "accuracy"),
    ("source_url", STR, True, False, "url"),
    ("verified_at", STR, True, False, "date"),
]
NODE_FIELDS = [
    ("id", STR, True, False, "uuid"),
    ("route_id", STR, False, True, "uuid"),
    ("name", STR, True, False, None),
    ("type", STR, True, False, "node_types"),
    ("geometry_accuracy", STR, False, True, "accuracy"),
]
PROJECT_FIELDS = [
    ("id", STR, True, False, "uuid"),
    ("name", STR, True, False, None),
    ("address", STR, True, False, None),
    ("ward_code", STR, False, True, "administrative_units"),
    ("service_area", STR, True, False, "service_areas"),
    ("status", STR, True, False, "project_statuses"),
    ("legal_status", STR, True, False, "legal_statuses"),
    ("application_start", STR, False, True, "date"),
    ("application_end", STR, False, True, "date"),
    ("price_min", NUM, False, True, "price"),
    ("price_max", NUM, False, True, "price"),
    ("price_is_estimated", BOOL, False, False, None),
    ("unit_count", INT, False, True, "positive"),
    ("developer", STR, False, True, None),
    ("cover_image_url", STR, False, True, "url"),
    ("source_url", STR, True, False, "url"),
    ("verified_at", STR, True, False, "date"),
]

# Ranh giới vùng phục vụ (highlight khi chọn vùng). Mock giản lược; `code` là khóa (mỗi vùng tối đa 1 feature).
AREA_FIELDS = [
    ("code", STR, True, False, "service_areas"),
    ("is_mock", BOOL, True, False, None),
    ("source_url", STR, True, False, "url"),
    ("verified_at", STR, True, False, "date"),
]

LOOKUP_CATEGORIES = ["route_types", "route_statuses", "node_types", "project_statuses", "legal_statuses",
                     "service_areas", "administrative_units"]


# ---------- Đọc dữ liệu ----------

def load_lookups(lookup_dir: pathlib.Path = LOOKUP_DIR) -> dict[str, dict[str, dict]]:
    """{danh mục: {code: item}} từ Lookup/*.json của app."""
    result = {}
    for category in LOOKUP_CATEGORIES:
        items = json.loads((lookup_dir / f"{category}.json").read_text(encoding="utf-8"))
        result[category] = {item["code"]: item for item in items}
    return result


def load_geojson(path: pathlib.Path, errors: list[str]):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        errors.append(f"{path.name}: không tìm thấy file {path}")
    except json.JSONDecodeError as e:
        errors.append(f"{path.name}: JSON không hợp lệ (dòng {e.lineno}, cột {e.colno}): {e.msg}")
    return None


# ---------- Kiểm tra ----------

def _is_number(v) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)


def _type_ok(value, kind: str) -> bool:
    if kind == STR:
        return isinstance(value, str) and value.strip() != ""
    if kind == INT:
        return isinstance(value, int) and not isinstance(value, bool)
    if kind == NUM:
        return _is_number(value)
    if kind == BOOL:
        return isinstance(value, bool)
    raise ValueError(kind)


def _in_vn_bbox(lng, lat) -> bool:
    return VN_BBOX["min_lng"] <= lng <= VN_BBOX["max_lng"] and VN_BBOX["min_lat"] <= lat <= VN_BBOX["max_lat"]


def _is_date(value) -> bool:
    if not isinstance(value, str) or not DATE_RE.match(value):
        return False
    try:
        datetime.date.fromisoformat(value)
    except ValueError:
        return False
    return True


def _check_position(pos, where: str, errors: list[str]) -> None:
    if not isinstance(pos, list) or len(pos) != 2 or not all(_is_number(c) for c in pos):
        errors.append(f"{where}: tọa độ phải là [lng, lat] gồm 2 số, nhận {json.dumps(pos, ensure_ascii=False)}")
        return
    lng, lat = pos
    hint = " (có thể đảo lat/lng — GeoJSON là [lng, lat])" if _in_vn_bbox(lat, lng) else ""
    if not (-180 <= lng <= 180 and -90 <= lat <= 90):
        errors.append(f"{where}: tọa độ [{lng}, {lat}] ngoài miền lng [-180, 180] / lat [-90, 90]{hint}")
    elif not _in_vn_bbox(lng, lat):
        errors.append(f"{where}: tọa độ [{lng}, {lat}] nằm ngoài khung Việt Nam "
                      f"(lng {VN_BBOX['min_lng']}–{VN_BBOX['max_lng']}, lat {VN_BBOX['min_lat']}–{VN_BBOX['max_lat']}){hint}")


def _check_line(coords, where: str, errors: list[str]) -> None:
    if not isinstance(coords, list) or len(coords) < 2:
        errors.append(f"{where}: LineString cần ít nhất 2 điểm")
        return
    for i, pos in enumerate(coords):
        _check_position(pos, f"{where}[{i}]", errors)


def _check_polygon(rings, where: str, errors: list[str]) -> None:
    """Chỉ 1 vòng ngoài (chưa hỗ trợ lỗ), khép kín, ≥ 4 vị trí (3 đỉnh + điểm đóng)."""
    if not isinstance(rings, list) or len(rings) != 1:
        errors.append(f"{where}: đa giác phải có đúng 1 vòng ngoài (chưa hỗ trợ lỗ/vòng trong)")
        return
    ring = rings[0]
    if not isinstance(ring, list) or len(ring) < 4:
        errors.append(f"{where}[0]: vòng cần ít nhất 4 vị trí (3 đỉnh + điểm đóng)")
        return
    for j, pos in enumerate(ring):
        _check_position(pos, f"{where}[0][{j}]", errors)
    if ring[0] != ring[-1]:
        errors.append(f"{where}[0]: vòng chưa khép kín (điểm đầu ≠ điểm cuối)")


def polygons_of(geom) -> list[list[list[float]]]:
    """Danh sách vòng ngoài [[lng, lat], ...] của Polygon/MultiPolygon."""
    if geom["type"] == "Polygon":
        return [geom["coordinates"][0]]
    return [rings[0] for rings in geom["coordinates"]]


def point_in_ring(lng: float, lat: float, ring) -> bool:
    """Ray casting trên mặt phẳng lng/lat — đủ chính xác ở quy mô tỉnh."""
    inside = False
    for (x1, y1), (x2, y2) in zip(ring, ring[1:]):
        if (y1 > lat) != (y2 > lat) and lng < (x2 - x1) * (lat - y1) / (y2 - y1) + x1:
            inside = not inside
    return inside


def _check_geometry(geom, allowed: tuple[str, ...], where: str, errors: list[str]) -> None:
    if not isinstance(geom, dict) or geom.get("type") not in allowed:
        got = geom.get("type") if isinstance(geom, dict) else geom
        errors.append(f"{where}: geometry phải là {' hoặc '.join(allowed)}, nhận {json.dumps(got, ensure_ascii=False)}")
        return
    coords = geom.get("coordinates")
    where = f"{where} geometry.coordinates"
    if geom["type"] == "Point":
        _check_position(coords, where, errors)
    elif geom["type"] == "LineString":
        _check_line(coords, where, errors)
    elif geom["type"] in ("Polygon", "MultiPolygon"):
        polygons = [coords] if geom["type"] == "Polygon" else coords
        if not isinstance(polygons, list) or not polygons:
            errors.append(f"{where}: {geom['type']} cần ít nhất 1 đa giác")
            return
        for i, rings in enumerate(polygons):
            _check_polygon(rings, f"{where}[{i}]" if geom["type"] == "MultiPolygon" else where, errors)
    else:  # MultiLineString
        if not isinstance(coords, list) or not coords:
            errors.append(f"{where}: MultiLineString cần ít nhất 1 đoạn")
            return
        for i, line in enumerate(coords):
            _check_line(line, f"{where}[{i}]", errors)


def _check_value(name: str, value, rule: str | None, lookups, where: str, errors: list[str]) -> None:
    if rule is None:
        return
    if rule == "uuid":
        if not UUID_RE.match(value):
            errors.append(f"{where}: '{name}' phải là UUID, nhận '{value}'")
    elif rule == "date":
        if not _is_date(value):
            errors.append(f"{where}: '{name}' phải là ngày hợp lệ dạng YYYY-MM-DD, nhận '{value}'")
    elif rule == "url":
        if not URL_RE.match(value):
            errors.append(f"{where}: '{name}' phải bắt đầu bằng http:// hoặc https://, nhận '{value}'")
    elif rule == "color":
        if not COLOR_RE.match(value):
            errors.append(f"{where}: '{name}' phải dạng #RRGGBB, nhận '{value}'")
    elif rule == "year":
        if not 1990 <= value <= 2100:
            errors.append(f"{where}: '{name}' phải trong khoảng 1990–2100, nhận {value}")
    elif rule == "price":
        # Cột numeric(6, 2), đơn vị triệu đồng/m².
        if not 0 < value < 10000:
            errors.append(f"{where}: '{name}' phải > 0 và < 10000 (triệu đồng/m²), nhận {value}")
    elif rule == "accuracy":
        if value not in ("chinh_xac", "gan_dung", "minh_hoa"):
            errors.append(f"{where}: '{name}' phải là chinh_xac / gan_dung / minh_hoa, nhận '{value}'")
    elif rule == "positive":
        if value <= 0:
            errors.append(f"{where}: '{name}' phải > 0, nhận {value}")
    elif value not in lookups[rule]:
        errors.append(f"{where}: '{name}' = '{value}' không có trong danh mục {rule} "
                      f"(hợp lệ: {', '.join(sorted(lookups[rule]))})")


def _check_features(fc, file: str, fields, allowed_geom, lookups, errors: list[str]) -> list[tuple[dict, dict]]:
    """Kiểm tra chung; trả về [(properties, geometry)] của các feature đọc được."""
    if not isinstance(fc, dict) or fc.get("type") != "FeatureCollection" or not isinstance(fc.get("features"), list):
        errors.append(f"{file}: gốc phải là FeatureCollection có mảng 'features'")
        return []
    known = {f[0] for f in fields}
    seen: dict[str, int] = {}
    result = []
    for i, feat in enumerate(fc["features"]):
        where = f"{file} features[{i}]"
        if not isinstance(feat, dict) or feat.get("type") != "Feature":
            errors.append(f"{where}: phải là object có \"type\": \"Feature\"")
            continue
        props = feat.get("properties")
        if not isinstance(props, dict):
            errors.append(f"{where}: thiếu 'properties' (object)")
            continue
        if isinstance(props.get("id"), str):
            where = f"{where} (id={props['id']})"
        for name, kind, required, nullable, rule in fields:
            if name not in props:
                if required:
                    errors.append(f"{where}: thiếu thuộc tính bắt buộc '{name}'")
                continue
            value = props[name]
            if value is None:
                if not nullable:
                    errors.append(f"{where}: '{name}' không được null")
                continue
            if not _type_ok(value, kind):
                errors.append(f"{where}: '{name}' phải là {kind}" + (" không rỗng" if kind == STR else "")
                              + f", nhận {json.dumps(value, ensure_ascii=False)}")
                continue
            _check_value(name, value, rule, lookups, where, errors)
        for name in sorted(set(props) - known):
            errors.append(f"{where}: thuộc tính lạ '{name}' (gõ sai tên? danh sách hợp lệ ở src/data/README.md)")
        fid = props.get("id")
        if isinstance(fid, str):
            if fid.lower() in seen:
                errors.append(f"{where}: id trùng với features[{seen[fid.lower()]}]")
            else:
                seen[fid.lower()] = i
        _check_geometry(feat.get("geometry"), allowed_geom, where, errors)
        result.append((props, feat.get("geometry")))
    return result


def validate(routes_fc, nodes_fc, projects_fc, lookups, areas_fc=None) -> list[str]:
    """Trả về danh sách lỗi (rỗng = hợp lệ). Không dừng ở lỗi đầu tiên. `areas_fc` = service_areas.geojson (tùy chọn)."""
    errors: list[str] = []
    areas = []
    if areas_fc is not None:
        areas = _check_features(areas_fc, "service_areas.geojson", AREA_FIELDS, ("Polygon", "MultiPolygon"), lookups, errors)
        seen_codes: set[str] = set()
        for i, (p, _) in enumerate(areas):
            code = p.get("code")
            if code in seen_codes:
                errors.append(f"service_areas.geojson features[{i}]: code '{code}' trùng (mỗi vùng tối đa 1 feature)")
            seen_codes.add(code)
    routes = _check_features(routes_fc, "routes.geojson", ROUTE_FIELDS, ("LineString", "MultiLineString"), lookups, errors)
    nodes = _check_features(nodes_fc, "nodes.geojson", NODE_FIELDS, ("Point",), lookups, errors)
    projects = _check_features(projects_fc, "projects.geojson", PROJECT_FIELDS, ("Point",), lookups, errors)

    route_ids = {p["id"].lower() for p, _ in routes if isinstance(p.get("id"), str)}
    for i, (p, _) in enumerate(nodes):
        rid = p.get("route_id")
        if isinstance(rid, str) and rid.lower() not in route_ids:
            errors.append(f"nodes.geojson features[{i}] (id={p.get('id')}): route_id '{rid}' không có trong routes.geojson")

    for i, (p, geom) in enumerate(projects):
        where = f"projects.geojson features[{i}] (id={p.get('id')})"
        lo, hi = p.get("price_min"), p.get("price_max")
        if _is_number(lo) and _is_number(hi) and lo > hi:
            errors.append(f"{where}: price_min ({lo}) lớn hơn price_max ({hi})")
        start, end = p.get("application_start"), p.get("application_end")
        if _is_date(start) and _is_date(end) and start > end:
            errors.append(f"{where}: application_start ({start}) sau application_end ({end})")
        # Dự án phải nằm trong ranh giới vùng của nó (nếu vùng có ranh giới) — bắt sai service_area / sai tọa độ.
        area_geom = next((g for a, g in areas if a.get("code") == p.get("service_area") and isinstance(g, dict)), None)
        point = geom.get("coordinates") if isinstance(geom, dict) else None
        if area_geom and isinstance(point, list) and len(point) == 2 and all(map(_is_number, point)):
            try:
                if not any(point_in_ring(point[0], point[1], r) for r in polygons_of(area_geom)):
                    errors.append(f"{where}: tọa độ [{point[0]}, {point[1]}] nằm ngoài ranh giới vùng '{p.get('service_area')}'")
            except (TypeError, IndexError, ZeroDivisionError):
                pass  # hình học lỗi đã được báo ở trên
        ward_code = p.get("ward_code")
        ward = lookups["administrative_units"].get(ward_code) if isinstance(ward_code, str) else None
        if ward and ward["service_area"] != p.get("service_area"):
            errors.append(f"{where}: ward_code '{p['ward_code']}' thuộc vùng '{ward['service_area']}' "
                          f"nhưng service_area là '{p.get('service_area')}'")
    return errors


# ---------- Chuyển GeoJSON → mock JSON của app ----------

def _point(pos) -> dict:
    return {"lat": pos[1], "lng": pos[0]}


def _ordered(props: dict, fields, extra: dict, insert_after: str) -> dict:
    """Ghi khóa theo thứ tự cố định của app; khóa không bắt buộc vắng mặt → null."""
    out = {}
    for name, kind, *_ in fields:
        value = props.get(name)
        if kind == NUM and _is_number(value):
            value = float(value)  # giữ kiểu "24.0" như file hiện tại
        out[name] = value
        if name == insert_after:
            out.update(extra)
    return out


def to_app_routes(fc) -> list[dict]:
    result = []
    for f in fc["features"]:
        geom = f["geometry"]
        lines = [geom["coordinates"]] if geom["type"] == "LineString" else geom["coordinates"]
        segments = [[_point(p) for p in line] for line in lines]
        result.append(_ordered(f["properties"], ROUTE_FIELDS, {"segments": segments}, "color_hex"))
    return result


def to_app_nodes(fc) -> list[dict]:
    return [_ordered(f["properties"], NODE_FIELDS, {"location": _point(f["geometry"]["coordinates"])}, "type")
            for f in fc["features"]]


def to_app_projects(fc) -> list[dict]:
    result = []
    for f in fc["features"]:
        p = _ordered(f["properties"], PROJECT_FIELDS, {"location": _point(f["geometry"]["coordinates"])}, "service_area")
        if p["price_is_estimated"] is None:
            p["price_is_estimated"] = True  # thận trọng: chưa rõ → coi là giá dự kiến (khớp default cột DB)
        result.append(p)
    return result


def to_app_service_areas(fc) -> list[dict]:
    """[{code, is_mock, source_url, verified_at, polygons: [[{lat, lng}, ...]]}] — vòng ngoài, bỏ điểm đóng lặp."""
    out = []
    for feat in fc["features"]:
        props = feat["properties"]
        rings = polygons_of(feat["geometry"])
        out.append({
            "code": props["code"],
            "is_mock": props["is_mock"],
            "source_url": props["source_url"],
            "verified_at": props["verified_at"],
            "polygons": [[_point(pos) for pos in ring[:-1]] for ring in rings],
        })
    return out


def dumps_app_json(data) -> str:
    """Cùng định dạng file mock hiện tại: indent 2, giữ Unicode, xuống dòng cuối file."""
    return json.dumps(data, indent=2, ensure_ascii=False) + "\n"


# ---------- Chạy ----------

def run_seed() -> None:
    spec = importlib.util.spec_from_file_location("generate_seed", SEED_SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.main()


STAGE_OUT = SRC / "data" / "out" / "stage.sql"


def run_stage(args) -> int:
    """GeoJSON → stage.sql cho schema `ingest` (staging → admin duyệt). Xem staging.py."""
    # `python3 -I` không tự thêm thư mục script vào sys.path.
    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
    import staging

    try:
        if args.stage:
            path = pathlib.Path(args.stage)
            fc = json.loads(path.read_text(encoding="utf-8"))
            header, features = staging.read_crawler_file(fc)
            batches = [(header["entity"], features)]
            source, run_ref = header["source"], header.get("run_ref") or path.parent.name
        else:
            entities = [e.strip() for e in args.entities.split(",") if e.strip()]
            unknown = [e for e in entities if e not in staging.ENTITIES]
            if unknown:
                raise staging.StagingError([f"--entities lạ: {', '.join(unknown)}"])
            problems: list[str] = []
            batches = []
            for entity in entities:
                fc = json.loads((GEOJSON_DIR / f"{entity}.geojson").read_text(encoding="utf-8"))
                for i, feat in enumerate(fc.get("features", [])):
                    staging.check_feature(entity, feat, f"{entity}.geojson features[{i}]", problems, manual=True)
                    props = (feat.get("properties") or {}) if isinstance(feat, dict) else {}
                    if entity in ("routes", "nodes") and props.get("geometry_accuracy") is None and not args.default_accuracy:
                        problems.append(f"{entity}.geojson features[{i}]: thiếu 'geometry_accuracy' "
                                        "(hoặc truyền --default-accuracy)")
                batches.append((entity, fc.get("features", [])))
            if problems:
                raise staging.StagingError(problems)
            source, run_ref = "qgis_manual", None
    except staging.StagingError as e:
        print(f"LỖI: không nạp được vào staging — {len(e.problems)} vấn đề:", file=sys.stderr)
        for problem in e.problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1

    sql = staging.stage_sql(batches, source=source, run_ref=run_ref, silent=args.silent, note=args.note,
                            default_accuracy=args.default_accuracy)
    out = pathlib.Path(args.out) if args.out else STAGE_OUT
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(sql, encoding="utf-8")
    counts = ", ".join(f"{len(f)} {e}" for e, f in batches)
    print(f"Đã ghi {out} — đợt '{source}'{' (silent)' if args.silent else ''}: {counts}")
    print(f'Chạy: psql "<connection string>" -v ON_ERROR_STOP=1 -f {out}')
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate GeoJSON → sinh mock JSON của app + seed.sql; hoặc nạp staging")
    parser.add_argument("--check", action="store_true", help="chỉ kiểm tra, không ghi; lỗi nếu JSON app lệch GeoJSON")
    parser.add_argument("--no-seed", action="store_true", help="không chạy generate_seed.py")
    stage = parser.add_argument_group("staging (schema ingest → admin duyệt)")
    stage.add_argument("--stage", metavar="FILE", help="file features.geojson của crawler (contract v1, có khối 'ancu')")
    stage.add_argument("--stage-manual", action="store_true", help="nạp dữ liệu vẽ tay trong data/geojson (nguồn qgis_manual)")
    stage.add_argument("--entities", default="routes,nodes", help="với --stage-manual: routes,nodes,projects")
    stage.add_argument("--silent", action="store_true", help="đợt nhập lặng: duyệt không bắn thông báo")
    stage.add_argument("--note", help="ghi chú cho đợt")
    stage.add_argument("--default-accuracy", choices=["chinh_xac", "gan_dung", "minh_hoa"],
                       help="geometry_accuracy cho tuyến/ga chưa khai báo")
    stage.add_argument("--out", help=f"file SQL (mặc định {STAGE_OUT.relative_to(SRC)})")
    args = parser.parse_args(argv)
    if args.stage and args.stage_manual:
        parser.error("chọn --stage hoặc --stage-manual, không cả hai")
    if args.stage or args.stage_manual:
        return run_stage(args)

    errors: list[str] = []
    fcs = {name: load_geojson(GEOJSON_DIR / f"{name}.geojson", errors)
           for name in ("routes", "nodes", "projects", "service_areas")}
    if not errors:
        errors = validate(fcs["routes"], fcs["nodes"], fcs["projects"], load_lookups(), fcs["service_areas"])
    if errors:
        print(f"LỖI: dữ liệu GeoJSON không hợp lệ — {len(errors)} vấn đề:", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 1

    outputs = {
        "routes": to_app_routes(fcs["routes"]),
        "nodes": to_app_nodes(fcs["nodes"]),
        "projects": to_app_projects(fcs["projects"]),
        "service_area_boundaries": to_app_service_areas(fcs["service_areas"]),
    }
    print("GeoJSON hợp lệ: " + ", ".join(f"{len(v)} {k}" for k, v in outputs.items()))

    stale = []
    for name, data in outputs.items():
        path = MOCK_DIR / f"{name}.json"
        text = dumps_app_json(data)
        current = path.read_text(encoding="utf-8") if path.exists() else None
        if current == text:
            continue
        if args.check:
            stale.append(path.relative_to(SRC))
        else:
            path.write_text(text, encoding="utf-8")
            print(f"Đã ghi {path.relative_to(SRC)}")
    if args.check:
        if stale:
            print("LỖI: JSON app chưa đồng bộ với GeoJSON (chạy build_data.py không --check): "
                  + ", ".join(map(str, stale)), file=sys.stderr)
            return 1
        print("JSON app đã đồng bộ với GeoJSON.")
        return 0

    if not args.no_seed:
        run_seed()
    return 0


if __name__ == "__main__":
    sys.exit(main())
