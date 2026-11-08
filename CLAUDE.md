# AnCu - Vibe Coding với Claude Code

## 1. Project Overview
- **Dự án**: AnCu
- **Mục tiêu**: App iOS giúp người mua nhà ở xã hội (NOXH) tại TP.HCM, Bình Dương cũ, Đồng Nai (MVP; Hà Nội sau) xem dự án trên bản đồ cùng hạ tầng giao thông tương lai, theo dõi đợt nhận hồ sơ và tự kiểm tra điều kiện mua.
- **Tech Stack**: SwiftUI + MapKit (iOS) · Supabase (PostgreSQL + PostGIS, Auth, Storage, Realtime, Edge Functions). Trang web công khai từng dự án và Android (Kotlin + Compose) làm sau. Có khả năng chuyển backend sang .NET → bắt buộc Repository Pattern phía iOS (`docs/02-specs/architecture.md` mục 5).

## 2. Lệnh thường dùng
Project iOS: `src/ios/AnCu.xcodeproj` (scheme `AnCu`, deployment target iOS 17, synchronized folders — thêm file vào `src/ios/AnCu/` là tự vào target).
```bash
cd src/ios

# Build
xcodebuild build -project AnCu.xcodeproj -scheme AnCu -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build/DerivedData

# Test (Swift Testing)
xcodebuild test -project AnCu.xcodeproj -scheme AnCu -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build/DerivedData

# Kiểm tra nhánh fallback (không Liquid Glass) trên iOS 18.5
xcodebuild build -project AnCu.xcodeproj -scheme AnCu -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5' -derivedDataPath build/DerivedData
```
```bash
# Đồng bộ Localizable.xcstrings sau khi build bằng CLI (Xcode IDE tự làm)
python3 -I scripts/sync_strings.py build/DerivedData

# Chụp màn hình trạng thái cụ thể (cờ DEBUG, xem src/ios/README.md)
xcrun simctl launch booted vn.ancu.app -SignedIn -SeedBookmarks -Tab tracking

# Chạy app / integration test với Supabase local (cần `supabase start`)
xcrun simctl launch booted vn.ancu.app -Backend local
TEST_RUNNER_ANCU_SUPABASE_URL=http://127.0.0.1:54321 xcodebuild test -project AnCu.xcodeproj -scheme AnCu -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build/DerivedData
```
Chi tiết kiến trúc, cách thay Mock bằng backend, danh sách `TODO(backend)`: `src/ios/README.md`.
```bash
# Supabase local (cần Docker) — chạy trong src/
supabase start                      # áp migrations + seed.sql
supabase db reset                   # chạy lại từ đầu sau khi sửa migration/seed
supabase test db                    # pgTAP (src/supabase/tests/database)
supabase db lint --schema public
python3 -I supabase/scripts/generate_seed.py   # sinh lại seed.sql từ mock JSON của app
python3 -I data/scripts/build_data.py          # validate data/geojson → mock JSON app → seed.sql (xem src/data/README.md)
python3 -I data/scripts/build_data.py --stage <features.geojson>   # → data/out/stage.sql nạp schema ingest; duyệt bằng ingest.approve_* (DBeaver)

# Cloud (project ancu) — CLI 3.x mặc định nhắm LOCAL, phải có --remote. Không dùng --include-seed.
supabase db push --remote --dry-run && supabase db push --remote
supabase migration list --remote
supabase db lint --remote --schema public
```
Chi tiết triển khai cloud (seed, Auth dashboard, SMTP): `src/supabase/README.md` mục "Triển khai cloud".

## 3. Quy tắc cốt lõi (Core Guidelines)
- **Tư duy nguyên tử (Atomic Tasks)**: Chỉ xử lý 1 task nhỏ mỗi lần, không sửa dàn trải nhiều module cùng lúc.
- **Tự động xác minh (Verification)**: Sau khi tạo/sửa code, luôn chạy lint hoặc test để đảm bảo không gãy build.
- **Tài liệu trước, code sau**: Trước khi implement tính năng lớn, luôn thảo luận và cập nhật spec/plan.
- **Không tự ý thêm dependency**: Hỏi trước khi cài đặt thêm thư viện mới nếu chưa có trong plan.

## 4. Tài liệu tham chiếu
- **Checklist tiến độ**: `docs/04-tracking/tasks.md`
- **Kế hoạch thực thi**: `docs/03-plans/phase-1-mvp.md`
- **Kiến trúc & Specs**: `docs/02-specs/architecture.md`, `schema.md`, `data-strategy.md`, `compliance.md`
- **Sản phẩm**: `docs/01-ideas/prd.md` · Lộ trình: `docs/03-plans/roadmap.md` · Spec gốc: `docs/01-ideas/source/`
- **Nhật ký session**: `docs/04-tracking/devlog.md`
