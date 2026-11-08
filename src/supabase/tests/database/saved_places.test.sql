-- pgTAP cho migration 13: địa điểm đã lưu, ghi chú bookmark, đề xuất thêm dự án.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(33);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000d1', 'd1@test.vn'),
  ('00000000-0000-0000-0000-0000000000d2', 'd2@test.vn');

-- Danh mục có sẵn từ migration (cloud không chạy seed)
select is((select count(*)::int from public.lookup_items where category = 'place_kinds'), 3, 'place_kinds có 3 loại');

-- Khách
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';
select throws_ok($$ select public.my_saved_places() $$, '42501', null, 'anon không đọc được địa điểm');
select throws_ok($$ select public.create_saved_place('X', 10.8, 106.7, 'khac') $$, '42501', null, 'anon không lưu được địa điểm');
select throws_ok($$ select public.suggest_project('X', 10.8, 106.7) $$, '42501', null, 'anon không đề xuất được');

-- Người dùng D1
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000d1","role":"authenticated"}';

select is(public.create_saved_place('Vinhomes Grand Park', 10.8423, 106.8287, 'thuong_mai', ' Long Bình, Thủ Đức ', ' giá 45tr/m² ') ->> 'service_area',
          'tp_hcm', 'lưu trong TP.HCM → server gán vùng tp_hcm');
select is((select p ->> 'note' from public.my_saved_places() p limit 1), 'giá 45tr/m²', 'ghi chú được trim');
select is((select p ->> 'address' from public.my_saved_places() p limit 1), 'Long Bình, Thủ Đức', 'địa chỉ được trim');
select is((select (p -> 'location' ->> 'lat')::numeric from public.my_saved_places() p limit 1), 10.8423::numeric, 'trả vị trí dạng point_json');

select throws_ok($$ select public.create_saved_place('Hà Nội', 21.03, 105.85, 'khac') $$, 'AC403', null, 'ngoài vùng MVP → AC403');
select throws_ok($$ select public.create_saved_place('Cần Thơ', 10.03, 105.78, 'khac') $$, 'AC403', null,
                 'tỉnh ngoài 5 tỉnh phục vụ (Cần Thơ) → AC403');
-- Đỉnh nam ranh giới Đồng Tháp mock ở (10.15, 105.55) — biên NGOÀI của vùng phục vụ: ~2,2 km ra ngoài vẫn nhận
-- (dung sai 3 km), ~6,6 km thì không.
select lives_ok($$ select public.create_saved_place('Sát biên', 10.13, 105.55, 'khac') $$, 'ngoài ranh giới ≤ 3 km → nhận');
select throws_ok($$ select public.create_saved_place('Xa biên', 10.09, 105.55, 'khac') $$, 'AC403', null, 'ngoài ranh giới > 3 km → AC403');

select throws_ok($$ select public.create_saved_place('X', 10.8, 106.7, 'biet_thu') $$, '22023', null, 'loại lạ → 22023');
select throws_ok($$ select public.create_saved_place('   ', 10.8, 106.7, 'khac') $$, '22023', null, 'tên rỗng → 22023');
select throws_ok($$ select public.create_saved_place('X', 10.8, 106.7, 'khac', null, repeat('a', 2001)) $$, '22023', null,
                 'ghi chú > 2000 ký tự → 22023');
select throws_ok($$ select public.create_saved_place('X', 95, 106.7, 'khac') $$, '22023', null, 'vĩ độ sai → 22023');

select throws_ok($$ insert into public.saved_places (user_id, name, location, kind, service_area)
                    values (auth.uid(), 'X', 'SRID=4326;POINT(106.7 10.8)', 'khac', 'tp_hcm') $$, '42501', null,
                 'ghi thẳng bảng bị chặn (chỉ qua RPC)');

-- Giới hạn 200: đã có 2 → thêm 198 = 200, cái thứ 201 bị chặn.
select is((select count(*)::int from (select public.create_saved_place('P' || g, 10.8, 106.7, 'khac') from generate_series(1, 198) g) x),
          198, 'lưu tới đủ 200 địa điểm');
select throws_ok($$ select public.create_saved_place('P201', 10.8, 106.7, 'khac') $$, 'AC409', null, 'địa điểm thứ 201 → AC409');

select is(public.update_saved_place((select (p ->> 'id')::uuid from public.my_saved_places() p where p ->> 'name' = 'Sát biên'),
                                    'Chỗ làm', 'khac', '') ->> 'name', 'Chỗ làm', 'sửa tên được');
select is((select p ->> 'note' from public.my_saved_places() p where p ->> 'name' = 'Chỗ làm'), null, 'ghi chú rỗng → xóa (null)');

-- Ghi chú bookmark
select lives_ok($$ select public.set_bookmark_note((select id from public.projects order by name limit 1), ' gần chỗ làm ') $$,
                'ghi chú cho dự án chưa lưu → tự lưu');
select is((select b ->> 'note' from public.my_bookmarks() b), 'gần chỗ làm', 'my_bookmarks trả ghi chú');
select lives_ok($$ select public.set_bookmark_note((select id from public.projects order by name limit 1), '') $$, 'xóa ghi chú');
select is((select count(*)::int from public.my_bookmarks() b where b ->> 'note' is null), 1, 'bỏ ghi chú nhưng vẫn giữ bookmark');
select throws_ok($$ select public.set_bookmark_note((select id from public.projects limit 1), repeat('a', 2001)) $$, '22023', null,
                 'ghi chú bookmark > 2000 → 22023');

-- Đề xuất dự án: chung giới hạn 10/24h với báo sai
select lives_ok($$ select public.suggest_project('NOXH Mới ' || g, 10.85, 106.77, 'Thủ Đức') from generate_series(1, 9) g $$,
                '9 đề xuất OK');
select lives_ok($$ select public.report_data((select id from public.projects limit 1), 'Sai giá') $$, 'báo sai thứ 10 OK');
select throws_ok($$ select public.suggest_project('Thêm', 10.85, 106.77) $$, 'AC429', null, 'đề xuất thứ 11 → AC429 (chung giới hạn)');

select set_config('test.d1_place', (select p ->> 'id' from public.my_saved_places() p limit 1), true);

-- Người dùng D2: không thấy / không sửa được của D1
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000d2","role":"authenticated"}';
select is((select count(*)::int from public.my_saved_places()) + (select count(*)::int from public.saved_places), 0,
          'D2 không thấy địa điểm của D1 (RPC lẫn bảng)');
select throws_ok($$ select public.update_saved_place(current_setting('test.d1_place')::uuid, 'Của tôi', 'khac', null) $$,
                 'P0002', null, 'D2 sửa địa điểm của D1 → P0002');
select is(public.delete_saved_place(current_setting('test.d1_place')::uuid), false, 'D2 xóa địa điểm của D1 → không xóa');

-- Xóa tài khoản → xóa luôn địa điểm
select public.create_saved_place('Nhà bố mẹ', 10.95, 106.82, 'khac', null, 'riêng tư');
select public.delete_my_account();
reset role;
select is((select count(*)::int from public.saved_places where user_id = '00000000-0000-0000-0000-0000000000d2'), 0,
          'xóa tài khoản → địa điểm bị xóa theo');

select * from finish();
rollback;
