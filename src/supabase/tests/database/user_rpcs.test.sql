-- pgTAP cho RPC dữ liệu người dùng (migration 07): bookmark, báo sai có giới hạn, push token.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(19);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000c1', 'c1@test.vn'),
  ('00000000-0000-0000-0000-0000000000c2', 'c2@test.vn');

-- Khách
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';
select throws_ok($$ select public.my_bookmarks() $$, '42501', null, 'anon không gọi được my_bookmarks');
select throws_ok($$ select public.register_push_token(repeat('a', 64)) $$, '42501', null, 'anon không đăng ký push token');

-- Người dùng C1
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}';

select is(public.toggle_bookmark((select id from public.projects order by name limit 1)), true, 'toggle lần 1 → lưu');
select is(public.toggle_bookmark((select id from public.projects order by name limit 1)), false, 'toggle lần 2 → bỏ lưu');
select throws_ok($$ select public.toggle_bookmark('00000000-0000-0000-0000-000000000000') $$, 'P0002', null, 'toggle id lạ → P0002');

select lives_ok($$ select public.set_bookmark_notify((select id from public.projects order by name offset 1 limit 1), true) $$,
                'bật thông báo cho dự án chưa lưu');
select is((select count(*)::int from public.my_bookmarks() b where (b ->> 'notify_enabled')::boolean), 1,
          'bật thông báo → tự lưu kèm notify');
select lives_ok($$ select public.set_bookmark_notify((select id from public.projects order by name offset 2 limit 1), false) $$,
                'tắt thông báo cho dự án chưa lưu → không lỗi, không thêm');
select is((select count(*)::int from public.my_bookmarks()), 1, 'my_bookmarks chỉ có 1');

select lives_ok($$ select public.report_data((select id from public.projects limit 1), 'Sai ' || g) from generate_series(1, 10) g $$,
                '10 báo cáo trong 24h: OK');
select throws_ok($$ select public.report_data((select id from public.projects limit 1), 'lần 11') $$, 'AC429', null,
                 'báo cáo thứ 11 → AC429 (rate limit)');

select throws_ok($$ insert into public.data_reports (project_id, reporter_id, note)
                    values ((select id from public.projects limit 1), '00000000-0000-0000-0000-0000000000c1', 'ghi thẳng') $$,
                 '42501', null, 'không ghi thẳng bảng data_reports (né rate limit) — chỉ qua RPC');
select throws_ok($$ select public.register_push_token('khong-phai-token') $$, '22023', null, 'token sai định dạng bị từ chối');
select public.register_push_token(repeat('ab', 32), 'sandbox');

-- C2 đăng nhập trên cùng máy → token chuyển chủ
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c2","role":"authenticated"}';
select public.register_push_token(repeat('ab', 32), 'production');
reset role;
select is((select array_agg(user_id::text) from public.push_tokens where token = repeat('ab', 32)),
          array['00000000-0000-0000-0000-0000000000c2'], 'token chuyển sang C2, C1 không còn nhận thông báo trên máy này');
select is((select environment from public.push_tokens where token = repeat('ab', 32)), 'production', 'lưu môi trường APNs của token');

-- ───── Tùy chọn loại thông báo (migration 09) ─────
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}';
select throws_ok($$ select public.set_notification_prefs('{"quang_cao": true}') $$, '22023', null, 'key không phải notification_types → từ chối');
select throws_ok($$ select public.set_notification_prefs('{"doi_gia": "khong"}') $$, '22023', null, 'giá trị không phải boolean → từ chối');
select public.set_notification_prefs('{"doi_gia": false}');
select is(public.my_notification_prefs(), '{"doi_gia": false}'::jsonb, 'đọc lại tùy chọn');
reset role;
-- C1 đang bật thông báo cho dự án offset 1 (ở trên). Đổi giá → C1 đã tắt "doi_gia" nên không nhận.
update public.projects set price_min = price_min + 1 where id = (select id from public.projects order by name offset 1 limit 1);
select is((select count(*)::int from public.notifications where user_id = '00000000-0000-0000-0000-0000000000c1'), 0,
          'đã tắt "Thay đổi giá" → fan-out bỏ qua');

select * from finish();
rollback;
