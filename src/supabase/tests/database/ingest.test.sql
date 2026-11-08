-- pgTAP cho migration 16: staging `ingest` → duyệt → bảng chính.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(32);

-- Người dùng theo dõi một dự án có sẵn (để kiểm tra thông báo khi duyệt).
insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000f1', 'f1@test.vn');
insert into public.bookmarks (user_id, project_id, notify_enabled)
select '00000000-0000-0000-0000-0000000000f1', id, true from public.projects order by name limit 1;
select set_config('test.project', (select id::text from public.projects order by name limit 1), true);

-- ── Quyền: app (anon/authenticated) không chạm được staging ──
set local role anon;
select throws_ok($$ select * from ingest.batches $$, '42501', null, 'anon không đọc được ingest');
reset role;
set local role authenticated;
select throws_ok($$ select * from ingest.pending_review $$, '42501', null, 'authenticated không đọc được ingest');
select throws_ok($$ select ingest.approve_batch(gen_random_uuid()) $$, '42501', null, 'authenticated không duyệt được');
reset role;

select is((select geometry_accuracy from public.infrastructure_routes limit 1), 'minh_hoa', 'tuyến cũ mặc định minh_hoa');
select ok((select r ? 'geometry_accuracy' from public.routes() r limit 1), 'routes() trả geometry_accuracy');

-- ── Đợt 1 (silent): tuyến mới + ga mới thuộc tuyến đó + dự án mới thiếu vị trí ──
insert into ingest.batches (id, source, contract_version, silent) values
  ('00000000-0000-0000-0000-00000000b001', 'qgis_manual', 1, true);

insert into ingest.route_candidates (batch_id, id, name, type, status, expected_year, color_hex, geom, geometry_accuracy, source_url) values
  ('00000000-0000-0000-0000-00000000b001', '00000000-0000-0000-0000-00000000a001', 'Metro thử', 'metro', 'dang_thi_cong', 2030, '#2563EB',
   'SRID=4326;MULTILINESTRING((106.70 10.77, 106.72 10.79))', 'gan_dung', 'https://maur.hochiminhcity.gov.vn/thu');
insert into ingest.node_candidates (batch_id, id, route_id, name, type, location, geometry_accuracy) values
  ('00000000-0000-0000-0000-00000000b001', '00000000-0000-0000-0000-00000000a002', '00000000-0000-0000-0000-00000000a001',
   'Ga thử', 'ga_metro', 'SRID=4326;POINT(106.71 10.78)', 'gan_dung');
insert into ingest.project_candidates (batch_id, id, name, address, service_area, status, legal_status, price_min, price_max, source_url) values
  ('00000000-0000-0000-0000-00000000b001', '00000000-0000-0000-0000-00000000a003', 'NOXH thử', 'Phường Thủ Đức', 'hcm_cu',
   'sap_mo', 'chu_truong_dau_tu', 18, 20, 'https://soxaydung.hochiminhcity.gov.vn/thu');

select is((select validation_errors from ingest.route_candidates where id = '00000000-0000-0000-0000-00000000a001'), '{}'::text[], 'tuyến hợp lệ');
select is((select validation_errors from ingest.node_candidates where id = '00000000-0000-0000-0000-00000000a002'), '{}'::text[],
          'ga trỏ tới tuyến đang chờ cùng đợt → hợp lệ');
select ok((select needs_location from ingest.project_candidates where id = '00000000-0000-0000-0000-00000000a003'), 'dự án thiếu vị trí → needs_location');
select is((select count(*)::int from ingest.pending_review where batch_id = '00000000-0000-0000-0000-00000000b001'), 3, 'pending_review thấy 3 bản nháp');

-- Bản nháp lỗi: kiểm ngay khi ghi
insert into ingest.route_candidates (batch_id, id, name, type, status, color_hex, geometry_accuracy, source_url) values
  ('00000000-0000-0000-0000-00000000b001', '00000000-0000-0000-0000-00000000a009', '', 'tau_bay', 'quy_hoach', 'xanh', 'chac_chan', 'ftp://x');
select is(cardinality((select validation_errors from ingest.route_candidates where id = '00000000-0000-0000-0000-00000000a009')), 6,
          'bản nháp lỗi ghi đủ 6 lỗi (tên, loại, màu, hình học, độ chính xác, url)');

insert into ingest.batches (id, source, contract_version) values ('00000000-0000-0000-0000-00000000b009', 'so_xay_dung_hcm', 1);
insert into ingest.project_candidates (batch_id, id, name, address, service_area, status, legal_status, price_max, source_url) values
  ('00000000-0000-0000-0000-00000000b009', '00000000-0000-0000-0000-00000000a008', 'Mới thiếu giá', 'X', 'hcm_cu', 'sap_mo', 'chu_truong_dau_tu', 20, 'https://x.vn');
select ok((select 'giá phải đủ thấp nhất và cao nhất'::text = any (validation_errors) from ingest.project_candidates where id = '00000000-0000-0000-0000-00000000a008'),
          'dự án MỚI chỉ có một nửa cặp giá → lỗi ngay khi ghi');

-- approve_batch all-or-nothing: còn bản lỗi → không áp dụng gì
select throws_ok($$ select * from ingest.approve_batch('00000000-0000-0000-0000-00000000b001') $$, '22023', null,
                 'đợt còn bản lỗi → từ chối cả đợt');
select is((select count(*)::int from public.infrastructure_routes where id = '00000000-0000-0000-0000-00000000a001'), 0,
          'all-or-nothing: tuyến hợp lệ cũng chưa vào bảng chính');

select throws_ok($$ select ingest.reject('route', (select candidate_id from ingest.route_candidates where id = '00000000-0000-0000-0000-00000000a009'), '') $$,
                 '22023', null, 'từ chối phải có lý do');
select lives_ok($$ select ingest.reject('route', (select candidate_id from ingest.route_candidates where id = '00000000-0000-0000-0000-00000000a009'), 'dữ liệu rác') $$,
                'từ chối bản lỗi');

-- Dự án thiếu vị trí: approve_batch dừng ở dự án
select throws_ok($$ select * from ingest.approve_batch('00000000-0000-0000-0000-00000000b001') $$, '22023', null,
                 'dự án thiếu vị trí chặn approve_batch');
select lives_ok($$ select ingest.approve_route((select candidate_id from ingest.route_candidates where id = '00000000-0000-0000-0000-00000000a001')) $$,
                'duyệt tuyến');
select lives_ok($$ select ingest.approve_node((select candidate_id from ingest.node_candidates where id = '00000000-0000-0000-0000-00000000a002')) $$,
                'duyệt ga (tuyến đã có)');
select throws_ok($$ select ingest.approve_project((select candidate_id from ingest.project_candidates where id = '00000000-0000-0000-0000-00000000a003')) $$,
                 '22023', null, 'duyệt dự án thiếu vị trí → lỗi');
select throws_ok($$ select ingest.approve_project((select candidate_id from ingest.project_candidates where id = '00000000-0000-0000-0000-00000000a003'), 21.0, 105.8) $$,
                 '22023', null, 'vị trí admin đặt ngoài vùng MVP → lỗi');
select lives_ok($$ select ingest.approve_project((select candidate_id from ingest.project_candidates where id = '00000000-0000-0000-0000-00000000a003'), 10.85, 106.77, 'đặt ghim theo địa chỉ') $$,
                'duyệt dự án kèm vị trí admin đặt');

select is((select verified_at from public.projects where id = '00000000-0000-0000-0000-00000000a003'), (now() at time zone 'Asia/Ho_Chi_Minh')::date,
          'verified_at = ngày duyệt');
select is((select geometry_accuracy from public.infra_nodes where id = '00000000-0000-0000-0000-00000000a002'), 'gan_dung', 'ga mang geometry_accuracy');
select ok((select count(*) > 0 from public.project_nearest_infra where project_id = '00000000-0000-0000-0000-00000000a003'),
          'dự án mới có khoảng cách tới ga (trigger)');
select is((select review_status || '|' || reviewed_by from ingest.project_candidates where id = '00000000-0000-0000-0000-00000000a003'),
          'applied|' || session_user, 'ghi người duyệt');

-- ── Cập nhật dự án có người theo dõi: silent không thông báo, thường thì có ──
insert into ingest.batches (id, source, contract_version, silent) values
  ('00000000-0000-0000-0000-00000000b002', 'so_xay_dung_hcm', 1, true),
  ('00000000-0000-0000-0000-00000000b003', 'so_xay_dung_hcm', 1, false);

insert into ingest.project_candidates (batch_id, id, name, address, service_area, location, status, legal_status, price_max, source_url)
select '00000000-0000-0000-0000-00000000b002', p.id, p.name, p.address, p.service_area, p.location, p.status, p.legal_status, p.price_max + 1, p.source_url
from public.projects p where p.id = current_setting('test.project')::uuid;
select is((select changed_fields from ingest.pending_review where batch_id = '00000000-0000-0000-0000-00000000b002'), array['price_max'],
          'pending_review chỉ ra đúng trường đổi');

select lives_ok($$ select * from ingest.approve_batch('00000000-0000-0000-0000-00000000b002') $$, 'duyệt đợt silent');
select is((select count(*)::int from public.notifications where project_id = current_setting('test.project')::uuid), 0,
          'đợt silent: không thông báo');
select ok((select count(*) > 0 from public.project_updates where project_id = current_setting('test.project')::uuid and field = 'price_max'),
          'đợt silent: vẫn ghi lịch sử project_updates');

-- Đợt thường, cùng transaction (DBeaver tắt auto-commit): cờ silent không được lây sang
insert into ingest.project_candidates (batch_id, id, name, address, service_area, location, status, legal_status, source_url)
select '00000000-0000-0000-0000-00000000b003', p.id, p.name, p.address, p.service_area, p.location, 'nhan_ho_so', p.legal_status, p.source_url
from public.projects p where p.id = current_setting('test.project')::uuid;
select lives_ok($$ select * from ingest.approve_batch('00000000-0000-0000-0000-00000000b003') $$, 'duyệt đợt thường');
select is((select count(*)::int from public.notifications where project_id = current_setting('test.project')::uuid), 1,
          'đợt thường: người theo dõi nhận thông báo (cờ silent không lây)');
select is((select price_max from public.projects where id = current_setting('test.project')::uuid) is not null, true,
          'trường trống trong bản nháp = giữ giá trị cũ (giá không bị xóa)');

select * from finish();
rollback;
