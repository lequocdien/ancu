# An Cư — iOS prototype

App SwiftUI cho người mua nhà ở xã hội (NOXH) tại TP.HCM, Bình Dương cũ và Đồng Nai: bản đồ dự án + hạ tầng giao thông, theo dõi đợt nhận hồ sơ, kiểm tra điều kiện mua.

**Trạng thái:** prototype. Kiến trúc production, **dữ liệu mock** (JSON trong bundle). Không gọi network, không dependency bên thứ ba.
Spec: [`docs/02-specs/prototype-ios.md`](../../docs/02-specs/prototype-ios.md) · Kiến trúc: [`docs/02-specs/architecture.md`](../../docs/02-specs/architecture.md)

## Chạy

Yêu cầu Xcode 26+ (SDK iOS 26). Deployment target iOS 17.

```bash
cd src/ios
open AnCu.xcodeproj                      # scheme AnCu → Run

# hoặc CLI
xcodebuild test  -project AnCu.xcodeproj -scheme AnCu -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build/DerivedData
# nhánh fallback (không Liquid Glass)
xcodebuild build -project AnCu.xcodeproj -scheme AnCu -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5' -derivedDataPath build/DerivedData
```

Chuỗi UI nằm ở `AnCu/Resources/Localizable.xcstrings`. Xcode IDE tự đồng bộ khi build; nếu chỉ build bằng CLI, chạy thêm:

```bash
python3 -I scripts/sync_strings.py build/DerivedData
```

## Kiến trúc

```
View ──► @Observable @MainActor ViewModel ──► Repository protocol (Domain) ──► Mock*/Supabase*/DotNet* Repository
                     ▲
          SessionStore (user + bookmark, dùng chung 3 tab, inject qua environment)
```

| Thư mục | Nội dung |
| --- | --- |
| `App/` | `AnCuApp`, `AppContainer` (composition root), `BackendConfig`, `SessionStore`, `RootTabView`, `DebugLaunchOptions` |
| `Core/DesignSystem/` | Token màu, `Glass.swift` (điểm duy nhất biết Liquid Glass), Typography/Motion, Spacing, `MeshBackground`, component, gallery |
| `Core/Extensions/` | `DisplayFormat` (giá, khoảng cách, ngày theo giờ VN) |
| `Domain/` | Model thuần Swift, protocol repository, `RepositoryError`, `EligibilityEvaluator`, `SearchNormalizer` |
| `Data/Shared/` | DTO (snake_case, đúng shape RPC) + `DTOMapper` — dùng chung Mock và Supabase |
| `Data/Mock/` | `Mock*Repository`, JSON |
| `Data/Supabase/` | `RPCClient` (protocol), `SupabaseRPCClient` + `SupabaseErrorMapper`, `Supabase*Repository`, `SupabaseAuthService` (chỉ thư mục này + `AppContainer` import SDK) |
| `Data/Local/` | `LocalBookmarkStorage` — bookmark tạm của khách |
| `Data/Device/` | `CoreLocationService`, `AppleIDCredentialRequest`, `PushNotificationService` + `AppDelegate`, `MetricKitReporter`, `ConnectivityMonitor` |
| `Data/Analytics/` | `BatchingAnalytics` (gom lô, tắt được) + `SupabaseAnalyticsSink` |
| `Features/` | `Map`, `Tracking`, `Eligibility`, `Account`, `Auth` |

Quy tắc được test tự kiểm tra: mọi API kính/material chỉ nằm trong `Core/DesignSystem/Glass.swift` (`DesignSystemTests.glassAPIsOnlyInGlassFile`).

## Backend: Mock hay Supabase

Dependency: `supabase-swift` (SPM, từ 2.55.0). Chọn ở `BackendConfig.resolve()` → `AppContainer.make(_:)`:

| Cách chạy | Backend |
| --- | --- |
| Env `ANCU_SUPABASE_URL` + `ANCU_SUPABASE_KEY` | Supabase bất kỳ — ưu tiên cao nhất (test, CI) |
| DEBUG `-Backend local` / `-Backend mock` | Supabase local `127.0.0.1:54321` (cần `cd src && supabase start`) / ép Mock |
| `Config/Secrets-Debug.xcconfig`, `Secrets-Release.xcconfig` | Supabase cloud cho bản build (copy từ `Secrets.example.xcconfig`, đã gitignore) |
| Không cấu hình gì | Mock (JSON trong bundle) |

Chỉ nhận key **publishable** (`sb_publishable_…`) hoặc JWT `anon`; `sb_secret_…` / `service_role` bị từ chối → Mock. Trong xcconfig viết URL dạng `https:/$()/<ref>.supabase.co` (`//` là comment).

```bash
xcrun simctl launch booted vn.ancu.app -Backend local
# Integration test với stack local (tự bỏ qua nếu thiếu biến):
TEST_RUNNER_ANCU_SUPABASE_URL=http://127.0.0.1:54321 xcodebuild test -project AnCu.xcodeproj -scheme AnCu -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build/DerivedData
```

Toàn bộ repository có bản Supabase (`Data/Supabase/`), gọi RPC — không query bảng. Repository mới phải: dùng `DTOMapper` (code lookup lạ → `.unknown`), để `SupabaseRPCClient` map lỗi về `RepositoryError` (`P0002` → `.notFound`, `28000`/`42501` → `.unauthorized`, `AC429` → `.rateLimited`, lớp `22`/`23` → `.decoding`).

| Tính năng | Cấu hình để bật |
| --- | --- |
| Email OTP | Luôn có. Local: mã trong Mailpit `http://127.0.0.1:54324` |
| Apple / Google / Facebook | `ANCU_AUTH_PROVIDERS = apple,google,facebook` (xcconfig) + provider bật trong Supabase; Apple cần capability Sign in with Apple |
| Push | Capability Push Notifications + key APNs `.p8` cho Edge Function (`src/supabase/README.md` mục Push). Thiếu → thông báo vẫn vào hộp thư trong app |
| Analytics | Tự bật với Supabase; người dùng tắt ở Tài khoản → Cài đặt. Mock: không gửi |

## Danh sách `TODO(backend)`

| File | Việc |
| --- | --- |
| `Data/Supabase/SupabaseAuthService.swift` | Lưu tên từ Sign in with Apple vào `profiles.display_name` (Apple chỉ gửi lần đầu) |
| `Features/Account/AccountScreen.swift` | Xác thực SĐT bằng OTP (bắt buộc trước khi bình luận — NĐ 147, Phase 2) |

Cập nhật bảng: `grep -rn "TODO(backend)" AnCu`.

## Debug launch arguments (chỉ DEBUG)

Dùng để chụp màn hình trên Simulator vì `simctl` không bấm được:

```bash
xcrun simctl launch booted vn.ancu.app -SignedIn -SeedBookmarks -Tab tracking
```

| Cờ | Tác dụng |
| --- | --- |
| `-DesignSystemGallery` | Mở bảng xem token + component |
| `-Tab map\|tracking\|account` | Tab mở đầu |
| `-SignedIn` | Đăng nhập mock khi khởi động |
| `-SeedBookmarks` | Lưu sẵn 4 dự án (khi danh sách trống) |
| `-SelectFirstProject` | Mở sheet dự án "Đang nhận hồ sơ" đầu tiên |
| `-DetailLarge` | Sheet chi tiết mở ở detent `.large` |
| `-EligibilityWizard` | Mở thẳng wizard kiểm tra điều kiện (tab Tài khoản) |
| `-Backend local` | Đọc dữ liệu công khai từ Supabase local |
| `-ForceUpdate` | Mock: server "yêu cầu" 99.0.0 → màn chặn cập nhật |
| `-FocusArea tp_hcm` | Như bấm chip vùng (`tp_hcm`, `dong_nai`, `tay_ninh`, `dong_thap`, `lam_dong`): highlight ranh giới + camera ôm vùng |
| `-ResetMapPreferences` | Xóa chip bản đồ đã ghi nhớ (lớp tuyến, "Đang nhận hồ sơ", vùng) → bắt đầu từ mặc định. Dùng khi chụp màn hình |
| `-SeedPlaces` | Tạo sẵn 3 địa điểm riêng (cần `-SignedIn`; khi danh sách trống) |
| `-ShowSavedLayer` | Bật sẵn lớp "Đã lưu" (ghim dự án đã lưu + ô vuông địa điểm riêng) |
| `-SearchQuery vinhomes` | Điền sẵn ô tìm kiếm (kết quả 2 nhóm: An Cư + Apple Maps) |
| `-EditFirstPlace` | Mở sẵn sheet sửa địa điểm riêng đầu tiên (kèm `-SignedIn -SeedPlaces`) — xem lưới icon |
| `-SelectRouteAt 10.7766,106.7031` | Như chạm vào tuyến tại điểm đó: tuyến nổi bật + thẻ tên |
| `-PickAt 10.80,106.74` | Như nhấn giữ tại điểm đó: chế độ chọn vị trí (ghim giữa màn hình, thẻ Lưu tại đây) |
| `-LocateOnLaunch` | Như bấm "Gần tôi" (đặt vị trí: `xcrun simctl location booted set 10.85,106.77`) |

## Dữ liệu mock — cần đối chiếu trước khi dùng thật

Tên phường/xã mới, tọa độ và trạng thái tuyến, năm khai thác, ngưỡng thu nhập trong `eligibility_rules.json` đều là **MOCK** (UI có gắn nhãn). Ngày trong mock tự dời theo ngày chạy (`DateShift`) để luôn có dự án đang mở — chỉ có ở mock.
