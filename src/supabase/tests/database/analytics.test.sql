-- pgTAP analytics (migration 08): chỉ ghi qua RPC, không ai đọc được qua API, đầu vào xấu bị bỏ cả lô.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(9);

set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select is(public.track_events('00000000-0000-0000-0000-0000000000a1', '0.1.0', '27.0',
  '[{"name":"app_open","occurred_at":"2026-11-07T01:00:00Z"},{"name":"project_viewed","props":{"status":"nhan_ho_so"}}]'::jsonb),
  2, 'anon ghi được lô 2 sự kiện');
select throws_ok($$ select count(*) from public.analytics_events $$, '42501', null, 'anon không đọc được bảng');
select throws_ok($$ select * from public.analytics_weekly_retention $$, '42501', null, 'anon không đọc được view retention');
select throws_ok($$ insert into public.analytics_events (install_id, name, app_version, os_version, occurred_at)
                    values (gen_random_uuid(), 'x_x', '1', '1', now()) $$, '42501', null, 'anon không insert trực tiếp');
select throws_ok($$ select public.track_events(gen_random_uuid(), '1', '1', '[{"name":"DROP TABLE"}]') $$, '22023', null,
                 'tên sự kiện sai định dạng → bỏ cả lô');
select throws_ok($$ select public.track_events(gen_random_uuid(), '1', '1', '[]') $$, '22023', null, 'lô rỗng bị từ chối');
select throws_ok($$ select public.track_events(gen_random_uuid(), '1', '1',
                    (select jsonb_agg(jsonb_build_object('name', 'app_open')) from generate_series(1, 51))) $$,
                 '22023', null, 'lô > 50 bị từ chối');

reset role;
select is((select count(*)::int from public.analytics_events where install_id = '00000000-0000-0000-0000-0000000000a1'), 2,
          'đúng 2 dòng, lô lỗi không ghi gì');
select ok((select occurred_at > now() - interval '8 days' from public.analytics_events
           where install_id = '00000000-0000-0000-0000-0000000000a1' and name = 'app_open'),
          'occurred_at bị kẹp trong 7 ngày gần nhất');

select * from finish();
rollback;
