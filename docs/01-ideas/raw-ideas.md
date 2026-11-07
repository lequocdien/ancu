# Ý tưởng thô & Brainstorming - An Cư (NOXH & Hạ Tầng Map)

> Nguồn: [Đặc tả sản phẩm v2](./source/Đặc%20tả%20sản%20phẩm%20–%20NOXH%20&%20Hạ%20Tầng%20Map%20(v2,%20iOS%20trước).md) — mục 1, 6.3.

## 1. Vấn đề giải quyết (Problem Statement)

App iOS (SwiftUI) giúp người mua nhà ở xã hội (NOXH) tại Hà Nội và TP.HCM:
- xem dự án nằm ở đâu so với hạ tầng giao thông tương lai,
- biết khi nào dự án mở nhận hồ sơ,
- tự kiểm tra mình có đủ điều kiện mua hay không.

**Bài toán thực tế:**
- Nhu cầu mua NOXH ở đô thị lớn rất cao nhưng thông tin phân mảnh. Xem quy hoạch phải dùng app đất đai nhiều thuật ngữ. Tiến độ, đợt nhận hồ sơ phải lướt hội nhóm Facebook/Zalo — đầy tin giả và môi giới "suất ngoại giao", "tiền chênh".
- Giá trị và độ tiện lợi của dự án NOXH phụ thuộc lớn vào kết nối giao thông sắp tới: Vành đai, Metro, quốc lộ mở rộng.
- Lưu ý địa giới: sau sắp xếp tỉnh 2025, Bình Dương đã nhập vào TP.HCM. Dữ liệu dùng tên đơn vị hành chính mới, đồng thời giữ tên cũ để vẫn tìm kiếm được.

## 2. Đối thủ và sản phẩm chồng lấn

Tra cứu lại ngày 2026-11-07: **chưa thấy app/web nào tại TP.HCM, Bình Dương, Đồng Nai làm "bản đồ NOXH + hạ tầng"**, và TP.HCM chưa có cổng đăng ký NOXH trực tuyến tập trung. Rủi ro lớn nhất đến từ phía nhà nước (dòng cuối).

| Nhóm / tên | Tình trạng 2026 | NOXH / bản đồ / thông báo đợt hồ sơ | Ghi chú |
| --- | --- | --- | --- |
| Guland | Hoạt động | Không có mục NOXH riêng; tin NOXH là tin rao môi giới | Bản đồ quy hoạch, bản đồ giá, AI định giá |
| Meey Map / Meey Land | Hoạt động (Sao Khuê 05/2026) | Không thấy tính năng NOXH | Tra quy hoạch thu phí, tích hợp tin rao |
| Batdongsan.com.vn | Hoạt động | Bài wiki tổng hợp NOXH TP.HCM (SEO); chưa xác minh có bản đồ/thông báo | Lẫn tin môi giới, nguồn "tiền chênh" |
| Sở Xây dựng TP.HCM | Hoạt động | Không có mục NOXH riêng, không bản đồ, không đăng ký trực tuyến; công bố từng dự án bằng công văn | **Nguồn dữ liệu chính** cho An Cư (đợt nhận hồ sơ, danh sách công khai ≥ 30 ngày) |
| Hệ thống thông tin nhà ở & thị trường BĐS (Bộ Xây dựng, NĐ 357/2025) | Có trên văn bản | Cơ sở dữ liệu, không bản đồ/thông báo cho người dân | URL hiện hành chưa xác minh |
| Cổng Dịch vụ công quốc gia | Hoạt động | Nộp hồ sơ xác nhận điều kiện / mua NOXH trực tuyến (NĐ 54/2026) | Kênh thủ tục, không giúp khám phá dự án |
| Phần mềm đăng ký NOXH Hà Nội | Đang xây dựng (09/2026) | Dự kiến trọn quy trình: công bố → đăng ký → xét duyệt | Chỉ Hà Nội; có thể nhân rộng sang TP.HCM |
| Đề xuất xét duyệt NOXH qua **VNeID** | Đề xuất (10/2026) | Nếu triển khai: nhà nước làm luôn tra cứu + đăng ký | **Rủi ro chiến lược** — xem prd.md mục 7 |
| Nhà Tốt, Alonhadat, cổng quy hoạch, hội nhóm FB/Zalo | Chưa xác minh lại | — | — |

Nguồn: guland.vn; theleader.vn (Sao Khuê 2026); wiki.batdongsan.com.vn; soxaydung.hochiminhcity.gov.vn; cafef.vn (phần mềm NOXH Hà Nội 13/09/2026; đề xuất VNeID 15/10/2026); mekongasean.vn (NĐ 54/2026).

## 3. Giải pháp & giá trị cốt lõi (theo thứ tự ưu tiên)

1. **Bản đồ NOXH + hạ tầng:** mỗi dự án hiển thị khoảng cách tới ga Metro và nút giao Vành đai gần nhất, kèm năm dự kiến khai thác của tuyến.
2. **Theo dõi đợt nhận hồ sơ:** thông báo khi dự án đã lưu mở nhận hồ sơ, đổi giá, đổi trạng thái pháp lý. Thêm công cụ tự kiểm tra điều kiện mua NOXH. Đây là lý do chính để đăng nhập và quay lại app.
3. **Cộng đồng có kiểm duyệt:** bình luận + ảnh thực tế tại từng dự án. Giá trị phụ ở giai đoạn đầu — cộng đồng chỉ có ích khi đủ đông.

**Nguyên tắc định vị:** app đứng về phía người mua. Không nhận tiền quảng cáo từ môi giới; mọi nội dung trả phí của chủ đầu tư phải gắn nhãn rõ ràng.

## 4. Câu hỏi còn mở

- [ ] Có hợp tác được với chủ đầu tư để họ tự cập nhật thông tin (tài khoản xác minh, gắn nhãn) mà không mất tính khách quan?
- [x] Mở rộng sang TP.HCM (và khu vực Bình Dương cũ) ngay sau MVP, hay chờ đạt ngưỡng người dùng? → Gộp vào MVP.
- [x] MVP chọn thành phố nào: Hà Nội hay TP.HCM (chọn nơi nắm rõ hơn)? → **TP.HCM (gồm Bình Dương cũ) + Đồng Nai** (2026-11-06). Hà Nội làm sau. Phạm vi chi tiết: `02-specs/data-strategy.md`.
- [ ] Mô hình doanh thu: gói hỗ trợ chuẩn bị hồ sơ / tài trợ ngân hàng cho vay NOXH (gắn nhãn) / dữ liệu tổng hợp cho nhà nghiên cứu?
- [x] ~~Ngưỡng bắt đầu làm Android?~~ → Chốt 2026-11-07: retention tuần 4 ≥ 20%, ≥ 30% người dùng hoạt động bật thông báo, ≥ 1.000 người dùng hoạt động/tháng trên iOS (đạt cả 3).
- [x] ~~Có chuyển backend Supabase → .NET không?~~ → Chốt 2026-11-07: **ở lại Supabase lâu dài**; chỉ xem xét lại khi có lý do cụ thể (chi phí, tích hợp hệ thống khác). Xem `02-specs/architecture.md` mục 5.0.
