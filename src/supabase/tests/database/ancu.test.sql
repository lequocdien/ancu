-- pgTAP — chạy bằng `supabase test db` (cần `supabase start` và seed đã nạp).
-- Kiểm tra: RLS (chỗ dễ hổng nhất), contract RPC, trigger lịch sử + fan-out thông báo.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(30);

-- ───── Dữ liệu người dùng giả ─────
insert into auth.users (id, email, raw_user_meta_data)
values ('00000000-0000-0000-0000-00000000000a', 'a@test.vn', '{"full_name":"An"}'),
       ('00000000-0000-0000-0000-00000000000b', 'b@test.vn', '{}');

select is((select count(*)::int from public.profiles where id in ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b')),
          2, 'trigger tạo profile khi đăng ký');
select is((select display_name from public.profiles where id = '00000000-0000-0000-0000-00000000000a'),
          'An', 'profile lấy tên từ metadata');

-- ───── Dữ liệu seed & tính sẵn ─────
select is((select count(*)::int from public.projects), 15, 'seed: 15 dự án');
select ok((select count(*) from public.project_nearest_infra) >= 30, 'tính sẵn ga + nút giao gần nhất cho mọi dự án');

-- ───── Khách (anon) ─────
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select is((select count(*)::int from public.projects_in_bbox(106.5, 10.58, 107.1, 11.18)), 15, 'anon: projects_in_bbox vùng MVP');
select is((select count(*)::int from public.projects_in_bbox(106.5, 10.58, 107.1, 11.18, array['nhan_ho_so'])), 5, 'anon: lọc Đang nhận hồ sơ');
select is((select count(*)::int from public.projects_in_bbox(0, 0, 0.1, 0.1)), 0, 'anon: khung ngoài vùng → rỗng');
select ok((select jsonb_array_length(search_places('thu duc') -> 'places') > 0), 'search không dấu khớp tên cũ "Thủ Đức"');
select ok((public.project_detail((select id from public.projects order by name limit 1)) -> 'nearest_infra') is not null, 'project_detail có nearest_infra');
select throws_ok($$ select public.project_detail('00000000-0000-0000-0000-000000000000') $$, 'P0002', null, 'project_detail id lạ → P0002 (404)');
select ok(public.lookup_catalog() ? 'route_types', 'lookup_catalog nhóm theo category');
select is(jsonb_array_length(public.service_area_boundary('tp_hcm') -> 'polygons'), 7,
          'service_area_boundary: TP.HCM mới (ranh giới thật) = đất liền + Côn Đảo + đảo ven biển = 7 đa giác');
select is((select count(*)::int from public.projects p join public.service_area_boundaries b on b.code = p.service_area
           where not extensions.st_covers(b.geom, p.location)), 0, 'mọi dự án nằm trong ranh giới vùng của nó');
select is(public.service_area_boundary('ba_ria_vung_tau_cu'), null, 'vùng chưa có ranh giới → null');
select is(public.client_config() ->> 'min_supported_version', '0.1.0', 'client_config: min_supported_version theo nền tảng');
select is(public.client_config('android') ->> 'min_supported_version', '0.0.0', 'client_config: nền tảng chưa cấu hình → 0.0.0 (không chặn)');
select is((select count(*)::int from public.administrative_units_all() u where u ? 'center' and u -> 'center' ? 'lat'),
          (select count(*)::int from public.administrative_units), 'administrative_units_all: mọi phường/xã có center {lat, lng}');
select is((select count(*)::int from public.eligibility_rules_current() r where r ->> 'rule_key' = 'income_max_single_million'), 1,
          'eligibility_rules_current: mỗi key một bản hiện hành');
select throws_ok($$ insert into public.bookmarks (user_id, project_id) values ('00000000-0000-0000-0000-00000000000a', (select id from public.projects limit 1)) $$,
                 '42501', null, 'anon không ghi bookmark');
select throws_ok($$ select public.inbox() $$, '42501', null, 'anon không gọi được inbox()');
-- Không có policy UPDATE → RLS lọc im lặng (0 dòng), không ném lỗi.
select results_eq($$ with changed as (update public.projects set name = 'hack' returning 1) select count(*)::int from changed $$,
                  $$ values (0) $$, 'anon không sửa được dự án (RLS lọc 0 dòng)');

-- ───── Người dùng A ─────
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated"}';

select is(public.merge_guest_bookmarks(array(select id from public.projects order by name limit 2) || '00000000-0000-0000-0000-000000000000'::uuid),
          2, 'merge_guest_bookmarks bỏ qua id không tồn tại');
update public.bookmarks set notify_enabled = true;
select is((select count(*)::int from public.bookmarks), 2, 'A thấy 2 bookmark của mình');
select throws_ok($$ update public.profiles set role = 'admin' $$, '42501', null, 'A không tự nâng quyền');
select lives_ok($$ select public.report_data((select id from public.projects limit 1), 'Sai giá') $$, 'A gửi báo sai được');

-- ───── Người dùng B không thấy dữ liệu của A ─────
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000b","role":"authenticated"}';
select is((select count(*)::int from public.bookmarks), 0, 'B không thấy bookmark của A');
select is((select count(*)::int from public.data_reports), 0, 'B không thấy báo cáo của A');

-- ───── Trigger: đổi giá → lịch sử + thông báo (tối đa 1/ngày/dự án) ─────
reset role;
update public.projects set price_min = price_min + 1, price_max = price_max + 1
where id = (select id from public.projects order by name limit 1);
select is((select count(*)::int from public.project_updates where field in ('price_min', 'price_max')), 2, 'ghi lịch sử 2 trường giá');
select is((select count(*)::int from public.notifications where user_id = '00000000-0000-0000-0000-00000000000a'), 1,
          'đổi 2 trường cùng lúc → chỉ 1 thông báo/ngày/dự án');

-- ───── Xóa tài khoản ─────
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select public.delete_my_account();
reset role;
select is((select count(*)::int from public.bookmarks where user_id = '00000000-0000-0000-0000-00000000000a'), 0,
          'xóa tài khoản cascade bookmark');

select * from finish();
rollback;
