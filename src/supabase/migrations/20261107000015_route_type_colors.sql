-- Màu tuyến THEO LOẠI (architecture.md 5.6, 2026-11-07): app vẽ mọi tuyến cùng loại một màu, lấy từ `route_types.color_hex`.
-- Metro đỏ → xanh dương (đỏ cạnh cam Vành đai khó phân biệt với người mù màu đỏ–lục);
-- Cao tốc tím → hồng đậm (tím trùng ghim dự án "Đang xây"). Vành đai cam, Quốc lộ xám giữ nguyên.
-- Cập nhật ở migration (không chỉ seed) để project cloud nhận ngay khi `db push --remote`.
update public.lookup_items set color_hex = '#2563EB' where category = 'route_types' and code = 'metro';
update public.lookup_items set color_hex = '#DB2777' where category = 'route_types' and code = 'cao_toc';
