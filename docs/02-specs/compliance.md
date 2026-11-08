# Pháp lý & Tuân thủ - An Cư

> Nguồn: Đặc tả sản phẩm v2 (`01-ideas/source/`) — mục 2.2, 7.
> Viết theo hiểu biết chung đến giữa 2026 — **cần luật sư xác nhận** trước khi phát hành.

Phần bình luận khiến app có thể bị coi là dịch vụ mạng xã hội theo pháp luật VN. Cả hai store đều có yêu cầu bắt buộc với nội dung do người dùng tạo (UGC).

## 1. Pháp luật Việt Nam

| Văn bản | Ảnh hưởng tới app | Việc cần làm |
| --- | --- | --- |
| Nghị định 147/2024/NĐ-CP về dịch vụ Internet | Mạng xã hội phải xác thực tài khoản bằng SĐT Việt Nam, xử lý nội dung vi phạm khi có yêu cầu. Tùy quy mô phải thông báo hoặc xin giấy phép | Bắt buộc OTP trước khi bình luận. Hỏi luật sư ngưỡng phải xin phép |
| Luật Bảo vệ dữ liệu cá nhân (hiệu lực 01/01/2026), Nghị định 13/2023 | Xử lý SĐT, ảnh, dữ liệu điều kiện mua. Dữ liệu chuyển ra nước ngoài (máy chủ Supabase, Gemini) | Chính sách quyền riêng tư + cơ chế consent. Hồ sơ đánh giá chuyển dữ liệu ra nước ngoài. Không lưu câu trả lời kiểm tra điều kiện nếu chưa đồng ý |
| Luật Đo đạc và Bản đồ | Bản đồ phát hành tại VN phải thể hiện đúng chủ quyền | Chọn nhà cung cấp/cách hiển thị phù hợp (`architecture.md` mục 3) |
| Luật Kinh doanh bất động sản 2023 | Áp dụng nếu sau này đăng tin rao / quảng cáo dự án | Giai đoạn đầu không đăng tin rao. Nội dung trả phí phải gắn nhãn |

> Ghi chú kiến trúc: nếu cần giảm rủi ro chuyển dữ liệu ra nước ngoài, cân nhắc region Supabase gần nhất (Singapore) và không gửi PII sang Gemini (chỉ gửi nội dung bình luận đã loại thông tin định danh).

## 2. App Store (và Google Play khi có Android) — checklist

- [ ] Sign in with Apple trên iOS (vì có đăng nhập Google/Facebook).
- [ ] Đủ 4 yêu cầu UGC: bộ lọc, nút báo cáo, nút chặn người dùng, thông tin liên hệ nhà phát triển.
- [ ] Xóa tài khoản ngay trong app. Google Play cần thêm link web yêu cầu xóa.
- [ ] Khai báo App Privacy (iOS) / Data safety (Android) khớp dữ liệu thực tế thu thập.
- [ ] Chỉ xin quyền vị trí "khi dùng app", kèm câu giải thích rõ ràng. Ảnh dùng PhotosPicker (không xin toàn quyền thư viện).
- [ ] Trang quy tắc cộng đồng + điều khoản sử dụng, liên kết từ app và trang store.
- [ ] Câu miễn trừ về thông tin quy hoạch và kết quả kiểm tra điều kiện.
- [ ] Privacy manifest `PrivacyInfo.xcprivacy` (lý do dùng `UserDefaults`), không tracking, không IDFA.
- [ ] Analytics tự làm: không gửi tên/email/SĐT/vị trí chính xác; khai báo "Usage Data" + "Diagnostics" (không liên kết danh tính) trong App Privacy.

### 2.1. Khai báo App Privacy (App Store Connect) — khớp `src/ios/AnCu/Resources/PrivacyInfo.xcprivacy`

| Dữ liệu (Apple) | Thu thập khi | Liên kết danh tính | Tracking | Mục đích |
| --- | --- | --- | --- | --- |
| Contact Info → Email Address | Đăng nhập email OTP / Apple / Google / Facebook | Có | Không | App Functionality |
| Identifiers → User ID | Có tài khoản (bookmark, thông báo) | Có | Không | App Functionality |
| User Content → Other User Content | Gửi "Báo thông tin sai" / "Đề xuất thêm dự án"; **ghi chú + địa điểm đã lưu** (tên, địa chỉ, vị trí người dùng tự chọn — 2026-11-07) | Có | Không | App Functionality |
| Usage Data → Product Interaction | Analytics tự làm (tắt được trong Tài khoản) | **Không** (mã cài đặt ngẫu nhiên) | Không | Analytics |
| Identifiers → Device ID | Mã cài đặt ngẫu nhiên của analytics | Không | Không | Analytics |
| Diagnostics → Crash Data | MetricKit (số lần crash/treo) | Không | Không | App Functionality |

**Không** khai báo: vị trí thiết bị (chỉ dùng trên máy cho "Gần tôi", không gửi đi — địa điểm đã lưu là điểm người dùng **tự chọn** trên bản đồ/kết quả tìm kiếm, khai trong User Content; **không có** tính năng lưu vị trí GPS hiện tại để giữ đúng điều này). Physical Address: chưa khai, chờ luật sư (0.5 câu d), câu trả lời kiểm tra điều kiện (không rời máy), danh bạ, ảnh (Phase 1 chưa có ảnh). Push token là dữ liệu kỹ thuật để gửi thông báo, không phải loại Apple yêu cầu khai báo.

Thay đổi dữ liệu thu thập → sửa đồng thời bảng này, `PrivacyInfo.xcprivacy`, chính sách quyền riêng tư trong app, và câu trả lời trên App Store Connect.

### 2.2. Checklist nộp bản build (Phase 1 bước 5.4)

- [x] Xóa tài khoản trong app (2 bước, RPC `delete_my_account`).
- [x] Quyền vị trí "khi dùng app" + câu giải thích (`NSLocationWhenInUseUsageDescription`); không xin quyền lúc mở app.
- [x] Quyền thông báo xin theo ngữ cảnh (khi bật thông báo một dự án).
- [x] Privacy manifest; không IDFA/ATT.
- [x] Thông tin liên hệ nhà phát triển trong app (hotro@ancu.vn).
- [x] Câu miễn trừ kết quả kiểm tra điều kiện + hướng tuyến.
- [ ] Sign in with Apple bật thật khi có Google/Facebook (Review 4.8) — code sẵn, cần capability.
- [ ] Nội dung chính sách quyền riêng tư / điều khoản / quy tắc cộng đồng được luật sư duyệt (bước 0.5) và có URL công khai (App Store Connect bắt buộc Privacy Policy URL).
- [ ] Ảnh chụp màn hình store, mô tả, từ khóa, phân loại tuổi; tài khoản demo cho App Review (email OTP: dùng hộp thư thật hoặc tài khoản review riêng).
- [ ] Kiểm tra hiển thị Hoàng Sa/Trường Sa trên máy thật (camera đã khóa vùng MVP — bước 0.4).

## 3. Câu miễn trừ chuẩn
- Hạ tầng: "Hướng tuyến mang tính minh họa theo quy hoạch được công bố, không dùng để xác định ranh giới đất."
- Điều kiện mua: "Kết quả chỉ để tham khảo, cơ quan có thẩm quyền xét duyệt mới là căn cứ cuối cùng."
- Cảnh báo cố định: "NOXH không có suất ngoại giao."
