-- Vùng phục vụ theo địa giới MỚI (sau sáp nhập 1/7/2025): TP.HCM + Đồng Nai, Tây Ninh, Đồng Tháp, Lâm Đồng
-- (data-strategy.md "Phạm vi địa lý MVP", plan Bước 8, 2026-11-08). Chạy được trên DB đang có dữ liệu (cloud):
-- 1) danh mục mới + mã cũ thành "đã gộp" (in_mvp = false, merged_into) — giữ để dữ liệu/lịch sử cũ không gãy;
-- 2) chuyển service_area ở mọi bảng đang dùng mã cũ; 3) thay ranh giới (mock, sinh từ src/data/geojson/service_areas.geojson).

-- ───── 1. Danh mục ─────
insert into public.lookup_items (category, code, label_vi, sort_order, attributes, center) values
  ('service_areas', 'tp_hcm', 'TP.HCM', 1, '{"in_mvp": "true", "gom": "TP.HCM cũ, Bình Dương cũ, Bà Rịa – Vũng Tàu cũ"}'::jsonb, 'SRID=4326;POINT(106.75 10.85)'::extensions.geography),
  ('service_areas', 'dong_nai', 'Đồng Nai', 2, '{"in_mvp": "true", "gom": "Đồng Nai cũ, Bình Phước cũ"}'::jsonb, 'SRID=4326;POINT(107.0 11.2)'::extensions.geography),
  ('service_areas', 'tay_ninh', 'Tây Ninh', 3, '{"in_mvp": "true", "gom": "Tây Ninh cũ, Long An cũ"}'::jsonb, 'SRID=4326;POINT(106.15 11.0)'::extensions.geography),
  ('service_areas', 'dong_thap', 'Đồng Tháp', 4, '{"in_mvp": "true", "gom": "Đồng Tháp cũ, Tiền Giang cũ"}'::jsonb, 'SRID=4326;POINT(105.95 10.45)'::extensions.geography),
  ('service_areas', 'lam_dong', 'Lâm Đồng', 5, '{"in_mvp": "true", "gom": "Lâm Đồng cũ, Đắk Nông cũ, Bình Thuận cũ"}'::jsonb, 'SRID=4326;POINT(108.05 11.65)'::extensions.geography),
  ('service_areas', 'ha_noi', 'Hà Nội', 6, '{"in_mvp": "false"}'::jsonb, 'SRID=4326;POINT(105.85 21.03)'::extensions.geography),
  ('service_areas', 'hcm_cu', 'TP.HCM cũ', 11, '{"in_mvp": "false", "merged_into": "tp_hcm"}'::jsonb, 'SRID=4326;POINT(106.7 10.8)'::extensions.geography),
  ('service_areas', 'binh_duong_cu', 'Bình Dương cũ', 12, '{"in_mvp": "false", "merged_into": "tp_hcm"}'::jsonb, 'SRID=4326;POINT(106.68 10.98)'::extensions.geography),
  ('service_areas', 'dong_nai_cu', 'Đồng Nai cũ', 13, '{"in_mvp": "false", "merged_into": "dong_nai"}'::jsonb, 'SRID=4326;POINT(106.92 10.86)'::extensions.geography),
  ('service_areas', 'ba_ria_vung_tau_cu', 'Bà Rịa – Vũng Tàu cũ', 14, '{"in_mvp": "false", "merged_into": "tp_hcm"}'::jsonb, 'SRID=4326;POINT(107.17 10.5)'::extensions.geography),
  ('service_areas', 'binh_phuoc_cu', 'Bình Phước cũ', 15, '{"in_mvp": "false", "merged_into": "dong_nai"}'::jsonb, 'SRID=4326;POINT(106.9 11.75)'::extensions.geography)
on conflict (category, code) do update set
  label_vi = excluded.label_vi, sort_order = excluded.sort_order, attributes = excluded.attributes, center = excluded.center;

-- ───── 2. Chuyển mã vùng ─────
create temporary table _area_map (old_code text primary key, new_code text not null) on commit drop;
insert into _area_map values
  ('hcm_cu', 'tp_hcm'), ('binh_duong_cu', 'tp_hcm'), ('ba_ria_vung_tau_cu', 'tp_hcm'),
  ('dong_nai_cu', 'dong_nai'), ('binh_phuoc_cu', 'dong_nai');

update public.administrative_units u set service_area = m.new_code from _area_map m where u.service_area = m.old_code;
update public.projects p set service_area = m.new_code from _area_map m where p.service_area = m.old_code;
update public.saved_places s set service_area = m.new_code from _area_map m where s.service_area = m.old_code;
-- Bản nháp đang chờ duyệt (đã duyệt/từ chối giữ nguyên làm lịch sử).
update ingest.project_candidates c set service_area = m.new_code
from _area_map m where c.service_area = m.old_code and c.review_status = 'pending';

-- ───── 2b. Bản nháp dự án chỉ nhận vùng đang phục vụ ─────
create or replace function ingest.validate_project()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  errors text[] := '{}';
begin
  if coalesce(trim(new.name), '') = '' then errors := array_append(errors, 'thiếu tên'); end if;
  if coalesce(trim(new.address), '') = '' then errors := array_append(errors, 'thiếu địa chỉ'); end if;
  -- Chỉ vùng ĐANG phục vụ (in_mvp): mã cũ đã gộp (hcm_cu, binh_duong_cu…) vẫn có trong danh mục nhưng bị từ chối.
  if not exists (select 1 from public.lookup_items l
                 where l.category = 'service_areas' and l.code = new.service_area and l.attributes ->> 'in_mvp' = 'true') then
    errors := array_append(errors, ('vùng ngoài phạm vi phục vụ: ' || coalesce(new.service_area, 'null')));
  end if;
  if not ingest._lookup_ok('project_statuses', new.status) then errors := array_append(errors, ('trạng thái lạ: ' || coalesce(new.status, 'null'))); end if;
  if not ingest._lookup_ok('legal_statuses', new.legal_status) then errors := array_append(errors, ('pháp lý lạ: ' || coalesce(new.legal_status, 'null'))); end if;
  if new.ward_code is not null and not exists (select 1 from public.administrative_units u where u.code = new.ward_code) then
    errors := array_append(errors, ('phường lạ: ' || new.ward_code));
  end if;
  if new.application_start is not null and new.application_end is not null and new.application_start > new.application_end then
    errors := array_append(errors, 'ngày bắt đầu sau ngày kết thúc');
  end if;
  if new.price_min is not null and new.price_min <= 0 or new.price_max is not null and new.price_max <= 0 then
    errors := array_append(errors, 'giá phải > 0');
  end if;
  if new.price_min is not null and new.price_max is not null and new.price_min > new.price_max then
    errors := array_append(errors, 'giá thấp nhất > cao nhất');
  end if;
  if new.unit_count is not null and new.unit_count <= 0 then errors := array_append(errors, 'số căn phải > 0'); end if;
  -- Dự án MỚI phải đủ cặp (dự án đã có: trống = giữ giá trị cũ, kiểm sau khi gộp lúc duyệt).
  if not exists (select 1 from public.projects p where p.id = new.id) then
    if (new.price_min is null) <> (new.price_max is null) then errors := array_append(errors, 'giá phải đủ thấp nhất và cao nhất'); end if;
    if (new.application_start is null) <> (new.application_end is null) then
      errors := array_append(errors, 'khung nhận hồ sơ phải đủ ngày bắt đầu và kết thúc');
    end if;
  end if;
  if coalesce(new.source_url, '') !~ '^https?://' then errors := array_append(errors, 'source_url không phải http(s)'); end if;
  if new.cover_image_url is not null and new.cover_image_url !~ '^https?://' then errors := array_append(errors, 'ảnh bìa không phải http(s)'); end if;
  -- Vị trí: được thiếu (needs_location); có thì phải nằm trong vùng MVP (± 3 km như saved_places).
  if new.location is not null and public.mvp_service_area_at(
       extensions.st_y(new.location::extensions.geometry), extensions.st_x(new.location::extensions.geometry)) is null then
    errors := array_append(errors, 'vị trí ngoài vùng MVP');
  end if;
  new.validation_errors := errors;
  return new;
end;
$$;

-- ───── 3. Ranh giới ─────
delete from public.service_area_boundaries;
insert into public.service_area_boundaries (code, geom, is_mock, source_url, verified_at) values
  ('tp_hcm', 'SRID=4326;MULTIPOLYGON(((107.12 10.66, 107.25 10.68, 107.45 10.75, 107.58 10.55, 107.5 10.45, 107.3 10.42, 107.15 10.38, 107.08 10.33, 107.05 10.4, 107.03 10.45, 106.98 10.38, 106.85 10.4, 106.78 10.48, 106.75 10.55, 106.72 10.62, 106.65 10.65, 106.55 10.62, 106.45 10.7, 106.38 10.8, 106.36 10.92, 106.38 11.06, 106.46 11.16, 106.4 11.25, 106.37 11.35, 106.45 11.45, 106.62 11.48, 106.74 11.45, 106.86 11.38, 106.98 11.3, 106.97 11.2, 106.9 11.1, 106.8 10.97, 106.8 10.88, 106.88 10.87, 106.89 10.8, 106.88 10.75, 106.85 10.67, 106.9 10.62, 107 10.58, 107.12 10.66)))'::extensions.geography, true, 'https://mock.ancu.vn/nguon/ranh-gioi/tp_hcm', '2026-11-08'),
  ('dong_nai', 'SRID=4326;MULTIPOLYGON(((107.5 11.4, 107.58 11.2, 107.55 10.95, 107.45 10.75, 107.25 10.68, 107.12 10.66, 107 10.58, 106.9 10.62, 106.85 10.67, 106.88 10.75, 106.89 10.8, 106.88 10.87, 106.8 10.88, 106.8 10.97, 106.9 11.1, 106.97 11.2, 106.98 11.3, 106.86 11.38, 106.74 11.45, 106.62 11.48, 106.45 11.45, 106.4 11.65, 106.45 11.85, 106.7 12.05, 107 12.25, 107.2 12.1, 107.45 11.8, 107.35 11.55, 107.5 11.4)))'::extensions.geography, true, 'https://mock.ancu.vn/nguon/ranh-gioi/dong_nai', '2026-11-08'),
  ('tay_ninh', 'SRID=4326;MULTIPOLYGON(((106.45 11.85, 106.3 11.98, 106.05 11.85, 105.9 11.55, 106.05 11.25, 105.95 11.05, 105.75 10.98, 105.45 10.95, 105.55 10.85, 105.8 10.62, 106 10.55, 106.3 10.48, 106.5 10.47, 106.78 10.48, 106.75 10.55, 106.72 10.62, 106.65 10.65, 106.55 10.62, 106.45 10.7, 106.38 10.8, 106.36 10.92, 106.38 11.06, 106.46 11.16, 106.4 11.25, 106.37 11.35, 106.45 11.45, 106.4 11.65, 106.45 11.85)))'::extensions.geography, true, 'https://mock.ancu.vn/nguon/ranh-gioi/tay_ninh', '2026-11-08'),
  ('dong_thap', 'SRID=4326;MULTIPOLYGON(((105.45 10.95, 105.15 10.95, 105.2 10.7, 105.35 10.4, 105.55 10.15, 105.85 10.22, 106.2 10.3, 106.55 10.25, 106.8 10.3, 106.85 10.4, 106.78 10.48, 106.5 10.47, 106.3 10.48, 106 10.55, 105.8 10.62, 105.55 10.85, 105.45 10.95)))'::extensions.geography, true, 'https://mock.ancu.vn/nguon/ranh-gioi/dong_thap', '2026-11-08'),
  ('lam_dong', 'SRID=4326;MULTIPOLYGON(((107.2 12.1, 107.4 12.35, 107.6 12.6, 107.85 12.8, 108.2 12.6, 108.55 12.25, 108.72 11.85, 108.9 11.45, 108.95 11.25, 108.65 11, 108.2 10.9, 107.95 10.68, 107.7 10.55, 107.58 10.55, 107.45 10.75, 107.55 10.95, 107.58 11.2, 107.5 11.4, 107.35 11.55, 107.45 11.8, 107.2 12.1)))'::extensions.geography, true, 'https://mock.ancu.vn/nguon/ranh-gioi/lam_dong', '2026-11-08');
