# Lộ trình tổng thể - An Cư

> Nguồn: Đặc tả sản phẩm v2 (`01-ideas/source/`) — mục 9.
> ⚠️ Bản gốc chứa sơ đồ embedded ("roadmap · 5 giai đoạn, 4 cổng") **không xuất ra được** khi export. Các giai đoạn và cổng dưới đây được dựng lại từ phần text của spec — **cần đối chiếu lại với sơ đồ gốc**. Chỉ Cổng C được spec mô tả rõ.

So với v1, ba thay đổi chính: thêm **Giai đoạn 0** cho dữ liệu và pháp lý; **tách bình luận** ra sau bản phát hành iOS đầu tiên; **Android native ở giai đoạn cuối**, chỉ làm khi đạt điều kiện (`02-specs/architecture.md` mục 2).

| Giai đoạn | Nội dung | Cổng ra |
| --- | --- | --- |
| 0. Dữ liệu & pháp lý | Chọn thành phố. Số hóa tuyến/ga, nhập dự án có `source_url`. Tư vấn luật (NĐ 147, PDPL, bản đồ). Kiểm tra hiển thị chủ quyền MapKit. Chốt ngưỡng điều kiện làm Android | **A** *(dựng lại)*: dữ liệu vùng MVP (TP.HCM + Bình Dương cũ + Đồng Nai) đã đối chiếu, có ý kiến luật sư |
| 1. Xây dựng iOS lõi + backend | Schema PostGIS + RLS + RPC. App: bản đồ, chi tiết, đăng nhập, lưu, theo dõi, kiểm tra điều kiện, push | **B** *(dựng lại)*: hoàn thành checklist App Store, test RLS, beta TestFlight |
| 2. Phát hành iOS (không bình luận) | Ra mắt App Store. Đo phễu, retention | **C**: kiểm duyệt đã được **thử tấn công** (red team) → mới mở bình luận |
| 3. Cộng đồng | Bình luận + ảnh, OTP, kiểm duyệt, báo cáo/chặn, trang quản trị | **D** *(dựng lại)*: đạt điều kiện bắt đầu Android: retention tuần 4 ≥ 20%, ≥ 30% người dùng hoạt động bật thông báo, ≥ 1.000 người dùng hoạt động/tháng trên iOS (đạt cả 3) |
| 4. Android native | Kotlin + Jetpack Compose, Google Maps SDK / Vietmap, FCM | — |

**Trang web công khai từng dự án:** làm sau bản iOS đầu tiên — thời điểm cụ thể chưa chốt.

**Cổng C là điểm quan trọng nhất:** app iOS ra mắt với bản đồ, theo dõi và kiểm tra điều kiện trước. Bình luận — nơi tập trung phần lớn rủi ro pháp lý và lừa đảo — chỉ mở khi kiểm duyệt đã được thử tấn công.
