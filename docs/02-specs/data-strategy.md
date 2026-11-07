# Chiến lược dữ liệu - An Cư

> Nguồn: Đặc tả sản phẩm v2 (`01-ideas/source/`) — mục 6.

Dữ liệu mới là sản phẩm thật, app chỉ là lớp hiển thị. MVP bắt đầu với **một vùng**: **TP.HCM (gồm Bình Dương cũ) + Đồng Nai** (chốt 2026-11-06), để đối chiếu thủ công từng dự án và giữ độ chính xác cao.

**Phạm vi địa lý MVP** — theo địa giới **cũ** vì địa giới mới rộng hơn mức cần:
- TP.HCM cũ + Bình Dương cũ (nay cùng thuộc TP.HCM).
- Đồng Nai cũ, trọng tâm Biên Hòa – Long Thành – Nhơn Trạch (nay thuộc Đồng Nai mới).
- **Ngoài phạm vi** dù cùng tỉnh mới: Bà Rịa – Vũng Tàu cũ (nay thuộc TP.HCM), Bình Phước cũ (nay thuộc Đồng Nai). Không lọc theo `province` mới; dùng cờ `in_mvp_area` hoặc polygon vùng phục vụ.

## 1. Nguồn dữ liệu

| Loại dữ liệu | Nguồn chính | Cách đưa vào hệ thống |
| --- | --- | --- |
| Danh sách dự án NOXH, khung nhận hồ sơ | Thông báo Sở Xây dựng, cổng Bộ Xây dựng, thông báo chính thức của chủ đầu tư | Nhập tay qua trang quản trị, kèm `source_url` |
| Giá, số căn | Quyết định phê duyệt giá, thông báo chủ đầu tư | Nhập tay. Chưa có giá phê duyệt → ghi rõ "Giá dự kiến" |
| Tuyến Metro, ga | Quy hoạch được phê duyệt, Ban QL đường sắt đô thị HN & TP.HCM | Số hóa bằng QGIS / geojson.io → GeoJSON → PostGIS |
| Vành đai, quốc lộ, nút giao | Quyết định phê duyệt dự án, quy hoạch giao thông | Như trên. Ghi chú "hướng tuyến minh họa" |
| Trạng thái thực tế, ảnh công trường | Cộng đồng người dùng | Bình luận đã kiểm duyệt + nút "Báo thông tin sai" |

**Không scrape** từ sàn bất động sản hay app quy hoạch khác: dễ vi phạm điều khoản sử dụng, bản quyền cơ sở dữ liệu, và kéo theo dữ liệu sai.

## 2. Quy trình duy trì

- Mỗi bản ghi có `source_url` và `verified_at`, cả hai **hiển thị công khai** trong app.
- Bản ghi quá **30 ngày** chưa đối chiếu lại → app hiện "Thông tin có thể đã cũ".
- **Hằng tuần** rà lại dự án ở trạng thái `nhan_ho_so` hoặc sắp mở nhận hồ sơ.
- Báo cáo "thông tin sai" xử lý trong **72 giờ**.
- Mọi tuyến hạ tầng kèm miễn trừ: "Hướng tuyến mang tính minh họa theo quy hoạch được công bố, không dùng để xác định ranh giới đất."
- Cần ít nhất **một người phụ trách dữ liệu** (có thể bán thời gian) — chi phí vận hành cố định, tính vào kế hoạch từ đầu.
- Địa giới: dùng tên đơn vị hành chính mới sau 2025, giữ alias tên cũ (vd Bình Dương → TP.HCM) cho tìm kiếm.

## 3. Câu hỏi còn mở
- Hợp tác chủ đầu tư tự cập nhật (tài khoản xác minh, gắn nhãn) mà không mất khách quan?
- ~~Mở rộng TP.HCM (và Bình Dương cũ) ngay sau MVP hay chờ ngưỡng người dùng?~~ → Đã gộp vào MVP (2026-11-06).
- Mở rộng Hà Nội sau MVP khi nào (ngưỡng người dùng)?
