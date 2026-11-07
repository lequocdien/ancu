-- An Cư — Push: INSERT public.notifications → Edge Function send-push (qua pg_net, bất đồng bộ).
--
-- Tương đương "Database Webhook" của Dashboard nhưng tự viết để:
--   - URL + secret đọc từ Vault (không hardcode, mỗi môi trường một giá trị):
--       send_push_url             vd. https://<ref>.supabase.co/functions/v1/send-push
--       send_push_webhook_secret  trùng env PUSH_WEBHOOK_SECRET của function
--     Local: supabase/seeds/push_webhook_local.sql tạo sẵn khi `supabase db reset`.
--     Cloud: tạo bằng vault.create_secret (xem supabase/README.md).
--   - Không bao giờ làm INSERT thất bại: thiếu cấu hình → bỏ qua; lỗi khi xếp hàng → WARNING.
-- pg_net chỉ xếp hàng request trong transaction, worker gửi sau commit → rollback thì không gửi.
-- Không retry: lỗi gửi xem ở net._http_response (giữ ~6 giờ) + log function.

create extension if not exists pg_net with schema extensions;
create extension if not exists supabase_vault;

create or replace function public.notify_send_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  fn_url text;
  fn_secret text;
begin
  select decrypted_secret into fn_url from vault.decrypted_secrets where name = 'send_push_url';
  select decrypted_secret into fn_secret from vault.decrypted_secrets where name = 'send_push_webhook_secret';

  if coalesce(fn_url, '') = '' or coalesce(fn_secret, '') = '' then
    raise log 'notify_send_push: chưa cấu hình send_push_url / send_push_webhook_secret trong Vault — bỏ qua push %', new.id;
    return null;
  end if;

  begin
    perform net.http_post(
      url := fn_url,
      body := jsonb_build_object(
        'type', 'INSERT',
        'table', tg_table_name,
        'schema', tg_table_schema,
        'record', to_jsonb(new),
        'old_record', null
      ),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-webhook-secret', fn_secret
      ),
      timeout_milliseconds := 5000
    );
  exception when others then
    raise warning 'notify_send_push: không xếp hàng được push % (%: %)', new.id, sqlstate, sqlerrm;
  end;
  return null;
exception when others then
  -- Kể cả đọc Vault lỗi cũng không được chặn việc tạo thông báo trong app.
  raise warning 'notify_send_push: lỗi % (%: %)', new.id, sqlstate, sqlerrm;
  return null;
end;
$$;

create trigger notifications_send_push
  after insert on public.notifications
  for each row execute function public.notify_send_push();

revoke execute on function public.notify_send_push() from public, anon, authenticated;
