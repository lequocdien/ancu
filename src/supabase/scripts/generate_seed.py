#!/usr/bin/env python3
"""Sinh supabase/seed.sql từ mock JSON của app iOS — một nguồn dữ liệu cho cả prototype lẫn Supabase local.

Chuỗi nguồn: src/data/geojson/*.geojson → src/data/scripts/build_data.py (validate, ghi routes/nodes/projects.json
của app, rồi gọi script này) → seed.sql. Sửa tuyến/nút/dự án ở GeoJSON; danh mục ở Lookup/*.json của app.

    python3 -I src/data/scripts/build_data.py      # cả chuỗi (khuyến nghị)
    python3 -I scripts/generate_seed.py            # chỉ bước này, chạy trong src/supabase

Thông báo (notifications.json) KHÔNG seed: trên server chúng sinh ra từ trigger fan-out khi dự án thay đổi.
Ngày giữ nguyên như JSON (không áp DateShift của mock).
"""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
MOCK = ROOT.parent / "ios" / "AnCu" / "Data" / "Mock" / "Resources"
OUT = ROOT / "seed.sql"

LOOKUP_CATEGORIES = [
    "project_statuses", "legal_statuses", "route_types", "route_statuses", "node_types",
    "service_areas", "eligibility_subjects", "housing_conditions", "notification_types",
]


def load(name: str):
    return json.loads((MOCK / f"{name}.json").read_text(encoding="utf-8"))


def lit(value) -> str:
    """Literal SQL an toàn cho chuỗi/số/bool/None."""
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    return "'" + str(value).replace("'", "''") + "'"


def text_array(values) -> str:
    return "array[" + ", ".join(lit(v) for v in values) + "]::text[]" if values else "'{}'::text[]"


def point(p) -> str:
    return f"'SRID=4326;POINT({p['lng']} {p['lat']})'::extensions.geography"


def multiline(segments) -> str:
    lines = ", ".join("(" + ", ".join(f"{pt['lng']} {pt['lat']}" for pt in seg) + ")" for seg in segments)
    return f"'SRID=4326;MULTILINESTRING({lines})'::extensions.geography"


def multipolygon(polygons) -> str:
    """Vòng ngoài trong JSON app không lặp điểm đóng → WKT phải tự khép kín."""
    def ring(points):
        closed = points + points[:1]
        return "((" + ", ".join(f"{pt['lng']} {pt['lat']}" for pt in closed) + "))"
    return f"'SRID=4326;MULTIPOLYGON({', '.join(ring(p) for p in polygons)})'::extensions.geography"


def rows(table: str, columns: list[str], values: list[list[str]]) -> str:
    body = ",\n".join("  (" + ", ".join(v) + ")" for v in values)
    return f"insert into public.{table} ({', '.join(columns)}) values\n{body};\n"


def main() -> None:
    parts = ["-- SINH TỰ ĐỘNG bởi scripts/generate_seed.py từ mock JSON. Không sửa tay.\n"]

    lookup = []
    for category in LOOKUP_CATEGORIES:
        for item in load(f"Lookup/{category}"):
            attributes = {k: str(v).lower() if isinstance(v, bool) else str(v) for k, v in item.get("attributes", {}).items()}
            lookup.append([
                lit(category), lit(item["code"]), lit(item["label_vi"]), lit(item.get("sort_order", 0)),
                lit(item.get("color_hex")), lit(item.get("sf_symbol")),
                lit(json.dumps(attributes, ensure_ascii=False)) + "::jsonb",
                point(item["center"]) if item.get("center") else "null",
            ])
    parts.append(rows("lookup_items",
                      ["category", "code", "label_vi", "sort_order", "color_hex", "sf_symbol", "attributes", "center"], lookup))

    parts.append(rows("administrative_units", ["code", "name", "province", "service_area", "old_names", "center"], [
        [lit(u["code"]), lit(u["name"]), lit(u["province"]), lit(u["service_area"]), text_array(u["old_names"]), point(u["center"])]
        for u in load("Lookup/administrative_units")
    ]))

    parts.append(rows("infrastructure_routes",
                      ["id", "name", "type", "status", "expected_year", "color_hex", "geom", "source_url", "verified_at"], [
        [lit(r["id"]), lit(r["name"]), lit(r["type"]), lit(r["status"]), lit(r.get("expected_year")), lit(r["color_hex"]),
         multiline(r["segments"]), lit(r["source_url"]), lit(r["verified_at"])]
        for r in load("routes")
    ]))

    parts.append(rows("infra_nodes", ["id", "route_id", "name", "type", "location"], [
        [lit(n["id"]), lit(n.get("route_id")), lit(n["name"]), lit(n["type"]), point(n["location"])]
        for n in load("nodes")
    ]))

    parts.append(rows("projects", [
        "id", "name", "address", "ward_code", "service_area", "location", "status", "legal_status",
        "application_start", "application_end", "price_min", "price_max", "price_is_estimated",
        "unit_count", "developer", "cover_image_url", "source_url", "verified_at",
    ], [
        [lit(p["id"]), lit(p["name"]), lit(p["address"]), lit(p.get("ward_code")), lit(p["service_area"]), point(p["location"]),
         lit(p["status"]), lit(p["legal_status"]), lit(p.get("application_start")), lit(p.get("application_end")),
         lit(p.get("price_min")), lit(p.get("price_max")), lit(p.get("price_is_estimated", True)), lit(p.get("unit_count")),
         lit(p.get("developer")), lit(p.get("cover_image_url")), lit(p["source_url"]), lit(p["verified_at"])]
        for p in load("projects")
    ]))

    parts.append(rows("service_area_boundaries", ["code", "geom", "is_mock", "source_url", "verified_at"], [
        [lit(b["code"]), multipolygon(b["polygons"]), lit(b["is_mock"]), lit(b["source_url"]), lit(b["verified_at"])]
        for b in load("service_area_boundaries")
    ]))

    parts.append(rows("eligibility_rules", [
        "rule_key", "value_type", "value_number", "value_text", "value_codes", "legal_reference", "effective_from", "is_mock",
    ], [
        [lit(r["rule_key"]), lit(r["value_type"]), lit(r.get("value_number")), lit(r.get("value_text")),
         text_array(r["value_codes"]) if r.get("value_codes") else "null",
         lit(r.get("legal_reference", "")), lit(r["effective_from"]), lit(r.get("is_mock", False))]
        for r in load("Lookup/eligibility_rules")
    ]))

    parts.append(rows("app_config", ["key", "value"], [
        [lit("min_supported_version"), lit(json.dumps({"ios": "0.1.0"})) + "::jsonb"],
        [lit("moderation"), lit(json.dumps({"auto_approve_after": 5, "auto_hide_reports": 3, "daily_comment_limit": 10})) + "::jsonb"],
    ]))

    OUT.write_text("\n".join(parts), encoding="utf-8")
    print(f"Đã ghi {OUT.relative_to(ROOT.parent.parent)} ({sum(p.count(chr(10)) for p in parts)} dòng)")


if __name__ == "__main__":
    main()
