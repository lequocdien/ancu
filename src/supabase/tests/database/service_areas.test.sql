-- pgTAP cho migration 17: vùng phục vụ theo địa giới MỚI (TP.HCM + Đồng Nai, Tây Ninh, Đồng Tháp, Lâm Đồng).
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(16);

select is((select array_agg(code order by sort_order) from public.lookup_items
           where category = 'service_areas' and attributes ->> 'in_mvp' = 'true'),
          array['tp_hcm', 'dong_nai', 'tay_ninh', 'dong_thap', 'lam_dong'], '5 vùng phục vụ theo thứ tự chip');
select is((select count(*)::int from public.lookup_items
           where category = 'service_areas' and attributes ->> 'in_mvp' = 'false' and attributes ? 'merged_into'), 5,
          '5 mã cũ còn trong danh mục, đánh dấu đã gộp');
select is((select attributes ->> 'merged_into' from public.lookup_items where category = 'service_areas' and code = 'binh_duong_cu'),
          'tp_hcm', 'Bình Dương cũ gộp vào TP.HCM');
select is((select array_agg(code order by code) from public.service_area_boundaries),
          array['dong_nai', 'dong_thap', 'lam_dong', 'tay_ninh', 'tp_hcm'], 'chỉ còn ranh giới 5 tỉnh mới');
select is((select count(*)::int from public.service_area_boundaries a join public.service_area_boundaries b on a.code < b.code
           -- ngưỡng 1.000 m²: cắt mock theo ranh giới thật để lại vệt số học ~0 (sai số dấu phẩy động)
           where extensions.st_area(extensions.st_intersection(a.geom, b.geom)) > 1000),
          0, 'các tỉnh không chồng lấn (> 1.000 m²)');
select is((select count(*)::int from public.projects where service_area not in ('tp_hcm', 'dong_nai', 'tay_ninh', 'dong_thap', 'lam_dong')),
          0, 'mọi dự án dùng mã vùng mới');

-- Thành phố quen thuộc → đúng tỉnh mới (cùng quy tắc với app: ServiceAreaLocator)
select is(public.mvp_service_area_at(10.35, 107.08), 'tp_hcm', 'Vũng Tàu → TP.HCM');
select is(public.mvp_service_area_at(10.98, 106.65), 'tp_hcm', 'Thủ Dầu Một → TP.HCM');
select is(public.mvp_service_area_at(11.53, 106.88), 'dong_nai', 'Đồng Xoài → Đồng Nai');
select is(public.mvp_service_area_at(10.53, 106.41), 'tay_ninh', 'Tân An → Tây Ninh');
select is(public.mvp_service_area_at(10.36, 106.36), 'dong_thap', 'Mỹ Tho → Đồng Tháp');
select is(public.mvp_service_area_at(11.94, 108.44), 'lam_dong', 'Đà Lạt → Lâm Đồng');
select is(public.mvp_service_area_at(10.93, 108.10), 'lam_dong', 'Phan Thiết → Lâm Đồng');
select is(public.mvp_service_area_at(10.03, 105.78), null, 'Cần Thơ → ngoài vùng');

-- Bản nháp dự án: mã cũ đã gộp bị từ chối, mã mới thì nhận
insert into ingest.batches (id, source, contract_version) values ('00000000-0000-0000-0000-00000000c001', 'so_xay_dung_hcm', 1);
insert into ingest.project_candidates (batch_id, id, name, address, service_area, status, legal_status, source_url) values
  ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-00000000c101', 'Cũ', 'X', 'binh_duong_cu', 'sap_mo', 'chu_truong_dau_tu', 'https://x.vn'),
  ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-00000000c102', 'Mới', 'X', 'lam_dong', 'sap_mo', 'chu_truong_dau_tu', 'https://x.vn');
select ok((select 'vùng ngoài phạm vi phục vụ: binh_duong_cu'::text = any (validation_errors)
           from ingest.project_candidates where id = '00000000-0000-0000-0000-00000000c101'), 'bản nháp mã cũ → lỗi vùng');
select is((select validation_errors from ingest.project_candidates where id = '00000000-0000-0000-0000-00000000c102'),
          '{}'::text[], 'bản nháp Lâm Đồng hợp lệ');

select * from finish();
rollback;
