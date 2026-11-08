# Product Requirements Document (PRD) - An Cư (NOXH & Hạ Tầng Map)

> Nguồn: Đặc tả sản phẩm v2 (`01-ideas/source/`) — mục 1.3, 3, 4, 8, 9.
> Chi tiết kỹ thuật: `02-specs/`. Lộ trình: `03-plans/`.

## 1. Mục tiêu sản phẩm

Ra mắt app iOS (SwiftUI + MapKit) cho **một vùng — TP.HCM (gồm Bình Dương cũ) + Đồng Nai** với 3 giá trị theo thứ tự: bản đồ NOXH + hạ tầng → theo dõi đợt nhận hồ sơ + kiểm tra điều kiện mua → cộng đồng có kiểm duyệt. Trang web công khai cho từng dự án làm ở giai đoạn sau.

## 2. User Persona & User Stories

- **Người dùng chính:** người mua NOXH lần đầu, thu nhập trung bình–thấp, chưa quen thủ tục, tại TP.HCM, Bình Dương cũ, Đồng Nai (Hà Nội giai đoạn sau).
- **Kiểm duyệt viên / người phụ trách dữ liệu:** xử lý hàng chờ bình luận, báo cáo, cập nhật dữ liệu dự án.

User stories:
- Là người mua, tôi muốn xem dự án NOXH trên bản đồ cùng các tuyến Metro/Vành đai để đánh giá kết nối giao thông tương lai.
- Là người mua, tôi muốn được báo khi dự án tôi quan tâm mở nhận hồ sơ, đổi giá hoặc đổi trạng thái pháp lý để không lỡ đợt.
- Là người mua, tôi muốn tự kiểm tra mình có đủ điều kiện mua NOXH để biết có nên chuẩn bị hồ sơ không.
- Là người mua, tôi muốn so sánh 2–3 dự án cạnh nhau (giá, khoảng cách tới ga, trạng thái).
- Là người mua, tôi muốn lưu cả dự án **chưa có trong An Cư** (NOXH khác, chung cư thương mại, chỗ làm…) kèm **ghi chú riêng** để cân nhắc trên cùng một bản đồ hạ tầng. *(thêm 2026-11-07)*
- Là người mua, tôi muốn đọc trải nghiệm thật và xem ảnh công trường từ người khác, không lẫn môi giới.
- Là kiểm duyệt viên, tôi muốn xử lý hàng chờ `pending` và báo cáo trong 24 giờ.

## 3. Kiến trúc màn hình (3 tab)

### Tab 1: Bản đồ
- Thanh tìm kiếm theo tên dự án, quận/huyện, phường/xã. Nút "Gần tôi".
  - Kết quả 2 nhóm: **Dự án trong An Cư** (luôn trên) và **Địa điểm khác** (Apple Maps). Địa điểm ngoài vùng MVP hiện mờ, nhãn "Ngoài khu vực hỗ trợ", không lưu được.
- **Nhấn giữ trên bản đồ** → ghim tay một địa điểm (đặt tên, loại, ghi chú) khi tìm không ra.
- Thanh lớp: Metro, Vành đai, Cao tốc, Quốc lộ, Tất cả NOXH, Đã lưu. Bộ lọc nhanh "Đang nhận hồ sơ".
- Chú giải màu theo trạng thái tuyến (đã khai thác / đang thi công / quy hoạch) và năm dự kiến.
- Ghim NOXH tự gom cụm khi thu nhỏ. Màu ghim thể hiện trạng thái dự án.
- Bottom sheet chi tiết dự án:
  - Tên, địa chỉ, giá tham khảo, số căn, trạng thái pháp lý, khung thời gian nhận hồ sơ.
  - Khoảng cách tới ga Metro và nút giao Vành đai gần nhất, kèm năm dự kiến khai thác.
  - Dòng "Nguồn: … · Cập nhật: dd/mm/yyyy" và nút **Báo thông tin sai**.
  - Nút Lưu và nút Bật thông báo.
  - Bình luận + ảnh; mỗi bình luận có nút **Báo cáo** và **Chặn người này**.

### Tab 2: Theo dõi
- Danh sách thẻ dự án đã lưu, sắp xếp theo hạn nộp hồ sơ gần nhất.
- **Địa điểm của tôi**: dự án ngoài hệ thống người dùng tự lưu (mới sửa lên trên). Sửa tên/loại/ghi chú, xóa.
- **Ghi chú** cho mọi thứ đã lưu (dự án trong An Cư và địa điểm riêng), tối đa 2.000 ký tự, chỉ người dùng thấy.
- Chế độ so sánh 2–3 dự án: giá, khoảng cách tới ga, trạng thái.
- Hộp thông báo: mở nhận hồ sơ, đổi giá, đổi trạng thái, có phản hồi bình luận.
- Chưa đăng nhập: màn hình giới thiệu lợi ích + nút đăng nhập.

### Tab 3: Tài khoản
- Đăng nhập / đăng xuất, xác thực số điện thoại.
- **Kiểm tra điều kiện mua NOXH** (mục 4.5).
- Bình luận của tôi (kèm trạng thái duyệt), cài đặt thông báo.
- Quy tắc cộng đồng, chính sách quyền riêng tư, điều khoản sử dụng.
- **Xóa tài khoản** ngay trong app (bắt buộc với App Store; Google Play khi có Android).

## 4. Chi tiết tính năng

### 4.1. Chế độ khách & điểm yêu cầu đăng nhập
- Khách: xem bản đồ, bật/tắt lớp hạ tầng, xem chi tiết dự án, đọc bình luận.
- Yêu cầu đăng nhập khi: lưu dự án / bật lớp Đã lưu, bật thông báo, gửi bình luận, báo cáo nội dung, mở tab Theo dõi.
- Gửi bình luận cần thêm **xác thực số điện thoại (OTP)**.
- Khách có thể lưu dự án tạm trên máy; khi đăng nhập, danh sách được gộp vào tài khoản.
- **Địa điểm riêng + ghi chú: bắt buộc đăng nhập** (không lưu tạm cho khách — ghi chú là dữ liệu đáng giữ, có thể chứa thông tin cá nhân).

### 4.6. Địa điểm đã lưu (dự án ngoài hệ thống) *(thêm 2026-11-07)*
- **Riêng tư**: chỉ chủ tài khoản thấy; không hiển thị cho người khác, không kiểm duyệt, không dùng cho analytics (chỉ đếm sự kiện theo loại).
- Nguồn: tìm kiếm Apple Maps (`MKLocalSearch`) hoặc ghim tay. Loại: NOXH · Thương mại · Khác.
- **Icon tự chọn** *(2026-11-07)*: bộ ~16 icon có sẵn (nhà, chung cư, chỗ làm, trường học, bệnh viện, chợ, nhà bố mẹ…); không chọn = icon theo loại. Màu ghim vẫn theo loại.
- **Xem trên bản đồ trước khi lưu** *(2026-11-07)*: bấm kết quả tìm kiếm hoặc nhấn giữ → camera tới điểm, ghim **cố định theo tọa độ** (kéo/zoom bản đồ thoải mái, ghim không đổi), **kéo chính cái ghim để chỉnh vị trí**, nút "Đưa ghim vào giữa" khi ghim trôi khỏi màn hình (cũng là cách chỉnh cho VoiceOver) *(đổi 2026-11-07 theo góp ý: cần zoom trong lúc ghim)*; thẻ dưới đáy báo vùng (ngoài vùng → nút Lưu tắt) + "Hủy" / "Lưu tại đây" → mới mở form tên/loại/ghi chú. **Địa chỉ cập nhật theo vị trí ghim** (Apple reverse geocoding, tiếng Việt, tra khi dừng kéo 0,5 s). Dời ghim > 100 m khỏi kết quả Apple Maps → giữ tên, địa chỉ tra lại theo vị trí mới, bỏ mã Apple Maps. Khách xem trước được, đăng nhập khi bấm Lưu.
- **Chỉ trong vùng MVP** (TP.HCM, Bình Dương cũ, Đồng Nai cũ — dung sai 3 km quanh ranh giới vì ranh giới đang là mock). Ngoài vùng → thông báo, không lưu.
- **Chống trùng**: trong 300 m có dự án trong An Cư → gợi ý "Dự án này đã có trong An Cư — theo dõi để nhận thông báo?" (vẫn cho lưu riêng nếu người dùng muốn).
- Loại NOXH có nút **"Đề xuất An Cư thêm dự án này"** (người dùng chủ động; gửi tên, địa chỉ, vị trí — không gửi ghi chú; chung giới hạn 10/24h với "Báo thông tin sai").
- Giới hạn: 200 địa điểm/tài khoản. Không có thông báo cho địa điểm riêng (không có dữ liệu theo dõi). Không lưu vị trí GPS của máy (không có nút "lưu vị trí hiện tại").
- Hiển thị: tab Theo dõi + ghim kiểu riêng trên bản đồ trong lớp "Đã lưu". Để sau: so sánh khoảng cách ga/nút giao cho địa điểm riêng; phát hiện trùng khi dự án được thêm vào hệ thống sau này.

### 4.2. Bình luận & ảnh thực tế
- Tối đa 1.000 ký tự, 3 ảnh/bình luận. Tối đa 10 bình luận/tài khoản/ngày (thực thi phía server).
- Bình luận của chính mình hiển thị ngay với nhãn "Đang chờ duyệt"; người khác chỉ thấy bình luận đã duyệt. Realtime chỉ phát bình luận `approved`.
- Ảnh tải vào bucket riêng tư, chỉ chuyển công khai sau khi duyệt. Nén ảnh và **xóa GPS EXIF** trước khi tải lên.

### 4.3. Kiểm duyệt nội dung
Kiểm duyệt chạy hoàn toàn phía server, có cơ chế độ tin cậy theo tài khoản. Pipeline kỹ thuật: `02-specs/architecture.md` mục 4.1.
- Kết quả của luật là **điểm rủi ro**, không phải lệnh chặn cứng; chỉ trường hợp rất rõ ràng mới `rejected` ngay.
- Tài khoản mới luôn vào `pending`; từ 5 bình luận được duyệt trở lên thì tự duyệt nếu luật + AI đều sạch.
- Bình luận có ≥ 3 báo cáo tự ẩn, chờ kiểm duyệt viên xem lại.
- Trang quản trị đơn giản (web nội bộ hoặc Supabase Studio) xử lý hàng chờ và báo cáo, mục tiêu **trong 24 giờ**.
- Các ngưỡng 5 / 3 / 10 là giá trị khởi điểm, lưu thành cấu hình.

### 4.4. Thông báo
- Người dùng chọn theo dõi từng dự án. Khi trạng thái, khung nhận hồ sơ hoặc giá thay đổi → gửi push.
- Giai đoạn sau: "Dự án mới trong khu vực bạn quan tâm".
- Không gửi thông báo quảng cáo. Tối đa 1 thông báo/ngày/dự án.

### 4.5. Kiểm tra điều kiện mua NOXH
- Bảng hỏi 4 bước: đối tượng → nhà ở **tại tỉnh/thành có dự án** → hôn nhân (độc thân / độc thân nuôi con dưới 18 tuổi / đã kết hôn) → thu nhập bình quân 12 tháng.
- Logic dựa trên Luật Nhà ở 2023 (Điều 76, 77), NĐ 100/2024 sửa đổi bởi NĐ 261/2025, NĐ 54/2026, NĐ 136/2026. Từ 2026 không còn điều kiện cư trú/nơi làm việc (bỏ bước "nơi làm việc" của spec gốc). Trần thu nhập hiện hành: 25 / 35 / 50 triệu (độc thân / độc thân nuôi con / vợ chồng) — chưa đối chiếu nguyên văn. Ngưỡng và đối tượng lưu ở bảng `eligibility_rules` để cập nhật không cần phát hành app.
- Kết quả 3 mức: **Có thể đủ điều kiện / Cần kiểm tra thêm / Chưa đủ**, kèm trích dẫn điều khoản và miễn trừ: "Kết quả chỉ để tham khảo, cơ quan có thẩm quyền xét duyệt mới là căn cứ cuối cùng".
- Mặc định **không lưu** câu trả lời lên server; muốn lưu phải hỏi ý người dùng (dữ liệu cá nhân).

## 5. Scope MVP

### Trong Scope (LÀM) — bản iOS đầu tiên (trước Cổng C)
- [ ] Bản đồ NOXH + lớp hạ tầng + bottom sheet chi tiết (vùng TP.HCM + Bình Dương cũ + Đồng Nai)
- [ ] Đăng nhập Apple / Google / Facebook, chế độ khách
- [ ] Lưu dự án, tab Theo dõi, so sánh dự án
- [ ] Địa điểm đã lưu (ngoài hệ thống) + ghi chú (mục 4.6)
- [ ] Thông báo đẩy khi dự án thay đổi
- [ ] Kiểm tra điều kiện mua NOXH
- [ ] Nút "Báo thông tin sai"
- [ ] Xóa tài khoản trong app, các trang chính sách

### Ngoài Scope ở bản phát hành đầu
- Bình luận + ảnh — chỉ mở sau Cổng C, khi kiểm duyệt đã được thử tấn công
- Trang web công khai cho từng dự án (chia sẻ Zalo/Facebook, SEO, deep link mở app)
- Android native — chỉ làm khi đạt cả 3 ngưỡng: retention tuần 4 ≥ 20%, ≥ 30% người dùng hoạt động bật thông báo, ≥ 1.000 người dùng hoạt động/tháng trên iOS (đạt cả 3)
- Khoảng cách theo đường đi thực tế (MVP dùng đường chim bay, ghi rõ trên UI)
- Thông báo "dự án mới trong khu vực"
- Tin rao / quảng cáo dự án

## 6. Tiêu chí thành công

- Phễu đo được: mở app → bấm ghim → lưu → đăng nhập → bật thông báo.
- Ngưỡng bắt đầu Android (chốt 2026-11-07): retention tuần 4 ≥ 20%, ≥ 30% người dùng hoạt động bật thông báo, ≥ 1.000 người dùng hoạt động/tháng trên iOS (đạt cả 3).
- Dữ liệu: 100% bản ghi có `source_url` + `verified_at`; báo cáo "thông tin sai" xử lý trong 72 giờ.
- *(Ngưỡng cụ thể cần chốt trước khi ra mắt.)*

## 7. Rủi ro & cách giảm thiểu

Bốn rủi ro có thể làm sản phẩm thất bại: dữ liệu sai, cộng đồng không đủ đông, lừa đảo lọt kiểm duyệt, pháp lý — cần xử lý trước khi phát hành. Chỉ làm iOS là rủi ro thứ năm, chấp nhận có chủ đích.

| Rủi ro | Mức độ | Dấu hiệu sớm | Giảm thiểu |
| --- | --- | --- | --- |
| Dữ liệu dự án / tuyến sai, cũ | Cao | Nhiều báo cáo "thông tin sai", phản ánh trên nhóm | Một vùng (TP.HCM + Bình Dương cũ + Đồng Nai), hiển thị nguồn + ngày đối chiếu, người phụ trách dữ liệu, rà soát hằng tuần (`02-specs/data-strategy.md`) |
| Cộng đồng trống | Cao | < 1 bình luận/dự án/tuần sau 2 tháng | Lấy bản đồ + thông báo làm giá trị chính. Seed nhóm người mua thật. Chia sẻ link vào Zalo/Facebook |
| Lừa đảo, cò mồi lọt kiểm duyệt | Cao | Bình luận bị báo cáo chứa thông tin liên hệ, có người bị lừa | Chuẩn hóa + AI + độ tin cậy tài khoản + báo cáo cộng đồng. Cảnh báo cố định "NOXH không có suất ngoại giao" |
| Pháp lý: mạng xã hội, dữ liệu cá nhân, bản đồ | Cao | Store từ chối, yêu cầu từ cơ quan chức năng | Tư vấn luật trước phát hành, OTP, chính sách quyền riêng tư, bản đồ đúng chủ quyền (`02-specs/compliance.md`) |
| Chỉ có iOS, bỏ lỡ người dùng Android | Cao | Người dùng hỏi bản Android | Dồn logic về server, chốt trước điều kiện làm Android. Trang web công khai ở giai đoạn sau |
| Chủ đầu tư khiếu nại / dọa kiện | Trung bình | Email yêu cầu gỡ bài | Quy tắc cộng đồng phân biệt trải nghiệm thật vs cáo buộc chưa kiểm chứng. Lưu lịch sử kiểm duyệt. Quy trình tiếp nhận khiếu nại |
| Không có mô hình doanh thu | Trung bình | Chi phí tăng, chưa có nguồn thu | Gói hỗ trợ hồ sơ, tài trợ ngân hàng (gắn nhãn), dữ liệu tổng hợp. Tránh quảng cáo môi giới |
| Chi phí dịch vụ tăng (SMS OTP, Gemini, băng thông ảnh) | Trung bình | Chi phí / người dùng hoạt động tăng | Nén ảnh, chỉ gọi AI khi luật chưa quyết được, budget alert từng dịch vụ |
| Người dùng ở lại Facebook/Zalo | Trung bình | Cài đặt thấp dù xem link cao | Giai đoạn sau: trang web công khai + deep link mở thẳng app |
| Bản đồ chậm khi nhiều ghim/tuyến | Trung bình | Giật khi kéo, rating thấp | Gom cụm, giản lược tuyến theo zoom, chỉ tải trong khung nhìn. Android: test máy cấu hình thấp |
| Cấu hình RLS sai làm lộ dữ liệu | Trung bình | Phát hiện khi review bảo mật | Test các policy, không để khóa quản trị trong app, bật rate limit |
| Chính sách NOXH thay đổi | Thấp–TB | Nghị định / thông tư mới | `eligibility_rules` dạng cấu hình, theo dõi văn bản mỗi tháng |
| Nhà nước làm nền tảng NOXH (VNeID, phần mềm đăng ký NOXH như Hà Nội) | Trung bình–Cao | Thông báo triển khai chính thức cho TP.HCM/Đồng Nai | Định vị là lớp **khám phá + so sánh + hạ tầng** đứng trước khâu đăng ký; deep link sang cổng nhà nước thay vì cạnh tranh; dùng dữ liệu công bố của họ làm nguồn |
| App lớn (Guland, các sàn) thêm lớp NOXH | Thấp–TB | Đối thủ ra tính năng tương tự | Lợi thế nằm ở độ mới dữ liệu, thông báo đợt hồ sơ, độ tin cậy — không ở bản đồ |
| Phụ thuộc Supabase (vendor lock-in) | Thấp | Giá tăng mạnh, giới hạn gói, sự cố kéo dài | Dữ liệu là Postgres chuẩn, logic trong SQL function; Supabase tự host được. Repository Pattern phía iOS giữ đường lui (`02-specs/architecture.md` mục 5.0) |
