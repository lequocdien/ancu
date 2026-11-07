-- pgTAP — trigger push (migration 20261107000010). Chạy bằng `supabase test db`.
-- Không gọi HTTP thật: pg_net chỉ xếp hàng vào net.http_request_queue, transaction rollback ở cuối.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(9);

select has_trigger('public', 'notifications', 'notifications_send_push', 'notifications có trigger send-push');
select trigger_is('public', 'notifications', 'notifications_send_push', 'public', 'notify_send_push', 'trigger gọi notify_send_push()');
select ok(not has_function_privilege('anon', 'public.notify_send_push()', 'execute'), 'anon không execute notify_send_push');
select ok(not has_function_privilege('authenticated', 'public.notify_send_push()', 'execute'), 'authenticated không execute notify_send_push');

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000c1', 'push@test.vn');

-- Đặt giá trị Vault (update nếu đã có, tạo nếu chưa). Rollback ở cuối → không ảnh hưởng cấu hình local.
create function pg_temp.set_secret(secret_name text, secret_value text) returns void language plpgsql as $f$
begin
  if exists (select 1 from vault.secrets where name = secret_name) then
    perform vault.update_secret((select id from vault.secrets where name = secret_name), secret_value);
  else
    perform vault.create_secret(secret_value, secret_name);
  end if;
end;
$f$;

-- Chuỗi rỗng = chưa cấu hình (trigger coi như thiếu).
select pg_temp.set_secret('send_push_url', '');
select pg_temp.set_secret('send_push_webhook_secret', '');
create temp table q0 as select coalesce(max(id), 0) as id from net.http_request_queue;

-- 1) Chưa cấu hình Vault → INSERT vẫn thành công, không xếp hàng request.
select lives_ok($$
  insert into public.notifications (user_id, project_id, type, title, body)
  values ('00000000-0000-0000-0000-0000000000c1', (select id from public.projects order by name limit 1), 'doi_gia', 'T1', 'B1')
$$, 'thiếu cấu hình Vault: insert notifications vẫn thành công');
select is((select count(*)::int from net.http_request_queue where id > (select id from q0)), 0, 'thiếu cấu hình: không gọi HTTP');

-- 2) Có cấu hình → xếp hàng đúng URL, header secret, payload kiểu Database Webhook.
select pg_temp.set_secret('send_push_url', 'http://kong:8000/functions/v1/send-push');
select pg_temp.set_secret('send_push_webhook_secret', 'test-secret');

select lives_ok($$
  insert into public.notifications (user_id, project_id, type, title, body)
  values ('00000000-0000-0000-0000-0000000000c1', (select id from public.projects order by name limit 1), 'doi_gia', 'T2', 'B2')
$$, 'có cấu hình: insert notifications thành công');

select results_eq($$
  select url, headers ->> 'x-webhook-secret', convert_from(body, 'utf8')::jsonb #>> '{record,title}',
         convert_from(body, 'utf8')::jsonb ->> 'type', convert_from(body, 'utf8')::jsonb ->> 'table'
  from net.http_request_queue where id > (select id from q0)
$$, $$ values ('http://kong:8000/functions/v1/send-push'::text, 'test-secret'::text, 'T2'::text, 'INSERT'::text, 'notifications'::text) $$,
'xếp hàng 1 POST: URL + x-webhook-secret + record từ Vault');

-- 3) URL rác → pg_net báo lỗi khi xếp hàng nhưng INSERT không được hỏng.
select pg_temp.set_secret('send_push_url', 'không phải url');
select lives_ok($$
  insert into public.notifications (user_id, project_id, type, title, body)
  values ('00000000-0000-0000-0000-0000000000c1', (select id from public.projects order by name limit 1), 'doi_gia', 'T3', 'B3')
$$, 'URL sai: insert notifications vẫn thành công');

select * from finish();
rollback;
