"""Nhập ranh giới tỉnh THẬT từ Bản đồ tra cứu ĐVHC Việt Nam (sapnhap.bando.com.vn, NXB TN-MT&BĐVN) vào service_areas.geojson.

Dữ liệu thô: GeoJSON mỗi tỉnh lưu từ tab Network của trang (thuộc tính a01_ten, a06_dt…), đặt trong src/data/raw/bando/
(không commit — bản quyền của nhà xuất bản). Cần Supabase local (container supabase_db_ancu) để kiểm tra bằng PostGIS.

    python3 -I src/data/scripts/import_bando_boundaries.py src/data/raw/bando src/data/geojson/service_areas.geojson \
        [--source-url URL] [--verified-at YYYY-MM-DD]

- Giữ NGUYÊN độ chi tiết gốc (app xin bản giản lược 0,0005° qua RPC) — giản lược riêng từng tỉnh làm biên chung lệch nhau.
- Kiểm tra: hình học hợp lệ, diện tích lệch ≤ 3% so với a06_dt (số chính thức).
- Tỉnh chưa có dữ liệu thật (còn mock) bị CẮT theo ranh giới thật → không chồng lấn; bỏ mảnh vụn < 1 km².
- Sau đó: python3 -I src/data/scripts/build_data.py (mock JSON app + seed) rồi viết migration cập nhật geom.
"""
import argparse, datetime, json, pathlib, subprocess, sys, unicodedata

DEFAULT_SOURCE_URL = "https://sapnhap.bando.com.vn/"
AREA_TOLERANCE = 0.03
SLIVER_KM2 = 1.0

# Tên (bỏ tiền tố "Thành phố"/"Tỉnh", không dấu) → mã service_areas.
NAME_TO_CODE = {
    "ho chi minh": "tp_hcm",
    "dong nai": "dong_nai",
    "tay ninh": "tay_ninh",
    "dong thap": "dong_thap",
    "lam dong": "lam_dong",
}


def normalize_name(name: str) -> str:
    text = unicodedata.normalize("NFD", name.lower()).replace("đ", "d")
    text = "".join(c for c in text if unicodedata.category(c) != "Mn")
    for prefix in ("thanh pho ", "tinh ", "tp. ", "tp "):
        if text.startswith(prefix):
            text = text[len(prefix):]
    return " ".join(text.split())


def official_area_km2(value) -> float | None:
    """'6.772,59' (định dạng VN) → 6772.59."""
    if value in (None, ""):
        return None
    return float(str(value).replace(".", "").replace(",", "."))


def psql(sql: str) -> str:
    # SQL qua stdin (hình học lớn vượt giới hạn tham số dòng lệnh).
    result = subprocess.run(["docker", "exec", "-i", "supabase_db_ancu", "psql", "-U", "postgres", "-At", "-F", "|",
                             "-v", "ON_ERROR_STOP=1"], input=sql, capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"psql lỗi: {result.stderr.strip()}")
    return result.stdout.strip()


def geom_sql(geometry: dict) -> str:
    text = json.dumps(geometry, separators=(",", ":")).replace("'", "''")
    return f"extensions.st_setsrid(extensions.st_geomfromgeojson('{text}'), 4326)"


def load_real(raw_dir: pathlib.Path) -> dict[str, dict]:
    found: dict[str, dict] = {}
    files = sorted(raw_dir.glob("*.geojson"))
    if not files:
        sys.exit(f"không có file *.geojson trong {raw_dir}")
    for path in files:
        for feature in json.loads(path.read_text(encoding="utf-8")).get("features", []):
            props = feature.get("properties") or {}
            name = props.get("a01_ten") or ""
            code = NAME_TO_CODE.get(normalize_name(name))
            if code is None:
                print(f"  bỏ qua '{name}' ({path.name}) — ngoài vùng phục vụ")
                continue
            if code in found:
                sys.exit(f"{code}: trùng trong {path.name} và {found[code]['file']}")
            found[code] = {"file": path.name, "name": name, "geometry": feature["geometry"],
                           "official_km2": official_area_km2(props.get("a06_dt"))}
    return found


def check_real(code: str, item: dict) -> None:
    valid, reason, km2, points = psql(
        f"with g as (select {geom_sql(item['geometry'])} g) "
        "select extensions.st_isvalid(g), extensions.st_isvalidreason(g), "
        "round((extensions.st_area(g::extensions.geography) / 1e6)::numeric, 2), extensions.st_npoints(g) from g;"
    ).split("|")
    if valid != "t":
        sys.exit(f"{code}: hình học không hợp lệ — {reason}")
    official = item["official_km2"]
    if official is None:
        sys.exit(f"{code}: thiếu diện tích chính thức (a06_dt) để đối chiếu")
    diff = abs(float(km2) - official) / official
    if diff > AREA_TOLERANCE:
        sys.exit(f"{code}: diện tích {km2} km² lệch {diff:.1%} so với chính thức {official} km² — sai tỉnh/sai dữ liệu?")
    print(f"  {code}: '{item['name']}' {points} đỉnh, {km2} km² (chính thức {official}, lệch {diff:.1%})")


def clip_mock(code: str, geometry: dict, real: list[dict]) -> dict:
    # st_union(geometry[]) trả SRID 0 (PostGIS 3.3) → đặt lại 4326.
    union = "extensions.st_setsrid(extensions.st_union(array[" + ", ".join(geom_sql(g) for g in real) + "]), 4326)"
    out = psql(
        f"with d as (select (extensions.st_dump(extensions.st_collectionextract(extensions.st_makevalid("
        f"extensions.st_difference({geom_sql(geometry)}, {union})), 3))).geom g) "
        f"select extensions.st_asgeojson(extensions.st_multi(extensions.st_union(g)), 6) from d "
        f"where extensions.st_area(g::extensions.geography) >= {SLIVER_KM2 * 1e6};"
    )
    if not out:
        sys.exit(f"{code}: cắt theo ranh giới thật thì không còn gì")
    return json.loads(out)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("raw_dir", type=pathlib.Path)
    parser.add_argument("target", type=pathlib.Path)
    parser.add_argument("--source-url", default=DEFAULT_SOURCE_URL)
    parser.add_argument("--verified-at", default=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=7))).date().isoformat())
    args = parser.parse_args()

    real = load_real(args.raw_dir)
    print(f"Ranh giới thật: {', '.join(sorted(real)) or '(không có)'}")
    for code, item in sorted(real.items()):
        check_real(code, item)

    collection = json.loads(args.target.read_text(encoding="utf-8"))
    features = []
    for feature in collection["features"]:
        props = feature["properties"]
        code = props["code"]
        if code in real:
            features.append({"type": "Feature", "properties": {
                "code": code, "is_mock": False, "source_url": args.source_url, "verified_at": args.verified_at},
                "geometry": real[code]["geometry"]})
        elif props.get("is_mock"):
            features.append({"type": "Feature", "properties": props,
                             "geometry": clip_mock(code, feature["geometry"], [r["geometry"] for r in real.values()])})
            print(f"  {code}: mock, đã cắt theo ranh giới thật")
        else:
            features.append(feature)   # ranh giới thật đã nhập trước đó — giữ nguyên
    missing = set(real) - {f["properties"]["code"] for f in features}
    if missing:
        sys.exit(f"{', '.join(sorted(missing))}: chưa có trong {args.target.name}")

    args.target.write_text(json.dumps({"type": "FeatureCollection", "features": features}, ensure_ascii=False, indent=2) + "\n",
                           encoding="utf-8")
    print(f"Đã ghi {args.target}")


if __name__ == "__main__":
    main()
