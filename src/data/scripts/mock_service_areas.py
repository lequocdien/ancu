"""Dựng ranh giới MOCK 5 tỉnh mới (địa giới sau 1/7/2025): thành phần (lng, lat) → ST_Union bằng PostGIS → GeoJSON.

Cần Supabase local (`supabase start`, container supabase_db_ancu). Chạy:
    python3 -I src/data/scripts/mock_service_areas.py src/data/geojson/service_areas.geojson
Đường biên chung giữa các tỉnh dùng ĐÚNG cùng đỉnh → union sạch, không chồng lấn. Thay bằng ranh giới chính thức khi có.
"""
import json, subprocess, sys

HCM_CU = [(106.46,11.16),(106.55,11.1),(106.62,11.0),(106.68,10.88),(106.74,10.87),(106.8,10.88),(106.88,10.87),(106.89,10.8),(106.88,10.75),(106.85,10.67),(106.9,10.62),(107.0,10.58),(107.03,10.45),(106.98,10.38),(106.85,10.4),(106.78,10.48),(106.75,10.55),(106.72,10.62),(106.65,10.65),(106.55,10.62),(106.45,10.7),(106.38,10.8),(106.36,10.92),(106.38,11.06),(106.46,11.16)]
BD_CU = [(106.46,11.16),(106.4,11.25),(106.37,11.35),(106.45,11.45),(106.62,11.48),(106.74,11.45),(106.86,11.38),(106.98,11.3),(106.97,11.2),(106.9,11.1),(106.8,10.97),(106.8,10.88),(106.74,10.87),(106.68,10.88),(106.62,11.0),(106.55,11.1),(106.46,11.16)]
# Biên nam Đồng Nai cũ dời lên (107.12,10.66)/(107.25,10.68): bản cũ đặt Phú Mỹ (BR-VT cũ) vào Đồng Nai.
DN_CU = [(106.86,11.38),(107.1,11.32),(107.35,11.55),(107.5,11.4),(107.58,11.2),(107.55,10.95),(107.45,10.75),(107.25,10.68),(107.12,10.66),(107.0,10.58),(106.9,10.62),(106.85,10.67),(106.88,10.75),(106.89,10.8),(106.88,10.87),(106.8,10.88),(106.8,10.97),(106.9,11.1),(106.97,11.2),(106.98,11.3),(106.86,11.38)]
BRVT_CU = [(107.0,10.58),(107.12,10.66),(107.25,10.68),(107.45,10.75),(107.58,10.55),(107.5,10.45),(107.3,10.42),(107.15,10.38),(107.08,10.33),(107.05,10.4),(107.03,10.45),(107.0,10.58)]
BP_CU = [(106.45,11.45),(106.40,11.65),(106.45,11.85),(106.70,12.05),(107.00,12.25),(107.20,12.10),(107.45,11.80),(107.35,11.55),(107.1,11.32),(106.86,11.38),(106.74,11.45),(106.62,11.48),(106.45,11.45)]
TAY_NINH = [(106.45,11.85),(106.30,11.98),(106.05,11.85),(105.90,11.55),(106.05,11.25),(105.95,11.05),(105.75,10.98),(105.45,10.95),(105.55,10.85),(105.80,10.62),(106.00,10.55),(106.30,10.48),(106.50,10.47),(106.78,10.48),(106.75,10.55),(106.72,10.62),(106.65,10.65),(106.55,10.62),(106.45,10.7),(106.38,10.8),(106.36,10.92),(106.38,11.06),(106.46,11.16),(106.4,11.25),(106.37,11.35),(106.45,11.45),(106.40,11.65),(106.45,11.85)]
DONG_THAP = [(105.45,10.95),(105.15,10.95),(105.20,10.70),(105.35,10.40),(105.55,10.15),(105.85,10.22),(106.20,10.30),(106.55,10.25),(106.80,10.30),(106.85,10.4),(106.78,10.48),(106.50,10.47),(106.30,10.48),(106.00,10.55),(105.80,10.62),(105.55,10.85),(105.45,10.95)]
LAM_DONG = [(107.20,12.10),(107.40,12.35),(107.60,12.60),(107.85,12.80),(108.20,12.60),(108.55,12.25),(108.72,11.85),(108.90,11.45),(108.95,11.25),(108.65,11.00),(108.20,10.90),(107.95,10.68),(107.70,10.55),(107.58,10.55),(107.45,10.75),(107.55,10.95),(107.58,11.2),(107.5,11.4),(107.35,11.55),(107.45,11.80),(107.20,12.10)]

AREAS = [  # (mã, các thành phần hợp lại)
    ("tp_hcm", [HCM_CU, BD_CU, BRVT_CU]),
    ("dong_nai", [DN_CU, BP_CU]),
    ("tay_ninh", [TAY_NINH]),
    ("dong_thap", [DONG_THAP]),
    ("lam_dong", [LAM_DONG]),
]

def wkt(ring): return "POLYGON((" + ", ".join(f"{x} {y}" for x, y in ring) + "))"

features = []
for code, parts in AREAS:
    geoms = ", ".join(f"ST_GeomFromText('{wkt(p)}', 4326)" for p in parts)
    sql = (f"select extensions.ST_AsGeoJSON(extensions.ST_Union(array[{geoms}]), 4), "
           f"extensions.ST_IsValid(extensions.ST_Union(array[{geoms}])), "
           f"extensions.ST_NumGeometries(extensions.ST_Union(array[{geoms}]))")
    sql = sql.replace("ST_GeomFromText", "extensions.ST_GeomFromText")
    out = subprocess.run(["docker", "exec", "supabase_db_ancu", "psql", "-U", "postgres", "-At", "-F", "|", "-c", sql],
                         capture_output=True, text=True, check=True).stdout.strip()
    geo, valid, n = out.split("|")
    if valid != "t" or n != "1":
        sys.exit(f"{code}: union không sạch (valid={valid}, parts={n})")
    geometry = json.loads(geo)
    features.append({"type": "Feature", "properties": {
        "code": code, "is_mock": True, "source_url": f"https://mock.ancu.vn/nguon/ranh-gioi/{code}", "verified_at": "2026-11-08"},
        "geometry": geometry})
    print(code, geometry["type"], len(geometry["coordinates"][0]), "đỉnh")
json.dump({"type": "FeatureCollection", "features": features}, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False, indent=2)
