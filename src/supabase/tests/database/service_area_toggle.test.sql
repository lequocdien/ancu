-- pgTAP cho migration 18: cờ ẩn/hiện (tạm ngừng phục vụ) một tỉnh — ingest.set_service_area_active.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(17);

-- Một dự án giả ở Lâm Đồng (Đà Lạt) để kiểm tra ẩn khỏi bản đồ / tìm kiếm.
insert into public.projects (id, name, address, service_area, location, status, legal_status, source_url, verified_at)
values ('00000000-0000-0000-0000-0000000000d1', 'NOXH Đà Lạt thử', 'Đà Lạt', 'lam_dong',
        'SRID=4326;POINT(108.44 11.94)', 'sap_mo', 'chu_truong_dau_tu', 'https://x.vn', current_date);
select ok((select count(*) = 1 from public.projects_in_bbox(108.3, 11.8, 108.6, 12.1) r
           where r ->> 'id' = '00000000-0000-0000-0000-0000000000d1'), 'đang bật: dự án Lâm Đồng hiện trên bản đồ');

-- ── Quyền: app không gọi được ──
set local role authenticated;
select throws_ok($$ select ingest.set_service_area_active('lam_dong', false, 'x') $$, '42501', null, 'authenticated không bật/tắt được');
reset role;

-- ── Chặn thao tác sai ──
select throws_ok($$ select ingest.set_service_area_active('khong_co', false, 'x') $$, '22023', null, 'mã không có trong danh mục');
select throws_ok($$ select ingest.set_service_area_active('binh_duong_cu', true) $$, '22023', null, 'mã cũ đã gộp không bật được');
select throws_ok($$ select ingest.set_service_area_active('lam_dong', false) $$, '22023', null, 'tạm ngừng phải có lý do');
select throws_ok($$ select ingest.set_service_area_active('ha_noi', true) $$, '22023', null, 'Hà Nội chưa có ranh giới → không bật');

-- ── Tạm ngừng Lâm Đồng ──
select is(ingest.set_service_area_active('lam_dong', false, 'chưa có dự án') ->> 'projects', '1', 'trả về số dự án bị ảnh hưởng');
select is((select attributes ->> 'in_mvp' from public.lookup_items where category = 'service_areas' and code = 'lam_dong'),
          'false', 'in_mvp = false');
select is((select attributes ->> 'paused_reason' from public.lookup_items where category = 'service_areas' and code = 'lam_dong'),
          'chưa có dự án', 'ghi lý do tạm ngừng');
select ok((select count(*) = 0 from public.projects_in_bbox(108.3, 11.8, 108.6, 12.1)), 'dự án Lâm Đồng ẩn khỏi bản đồ');
select is(public.search_places('Đà Lạt thử') -> 'projects', '[]'::jsonb, 'dự án Lâm Đồng ẩn khỏi tìm kiếm');
select ok((select count(*) = 1 from public.projects_by_ids(array['00000000-0000-0000-0000-0000000000d1'::uuid])),
          'bookmark vẫn mở được dự án (projects_by_ids)');
select is(public.mvp_service_area_at(11.94, 108.44), null, 'không lưu địa điểm mới ở Lâm Đồng (AC403)');
select ok((select count(*) > 0 from public.projects_in_bbox(106.5, 10.6, 107.0, 11.0)), 'tỉnh khác không ảnh hưởng');

-- Không tắt được vùng cuối cùng
select ingest.set_service_area_active(c, false, 'test')
from unnest(array['dong_nai', 'tay_ninh', 'dong_thap']) c;
select throws_ok($$ select ingest.set_service_area_active('tp_hcm', false, 'x') $$, '22023', null, 'không tắt được vùng phục vụ cuối cùng');

-- ── Bật lại ──
select lives_ok($$ select ingest.set_service_area_active('lam_dong', true) $$, 'bật lại Lâm Đồng');
select is((select attributes from public.lookup_items where category = 'service_areas' and code = 'lam_dong'),
          '{"in_mvp": "true", "gom": "Lâm Đồng cũ, Đắk Nông cũ, Bình Thuận cũ"}'::jsonb, 'bật lại xóa lý do/thời điểm tạm ngừng');

select * from finish();
rollback;
