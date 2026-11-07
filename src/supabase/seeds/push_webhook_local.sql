-- CHỈ LOCAL (nạp sau seed.sql khi `supabase db reset`): cấu hình Vault cho trigger notifications_send_push.
-- URL đi trong mạng Docker của Supabase CLI (kong có alias "kong"); secret khớp
-- [edge_runtime.secrets] PUSH_WEBHOOK_SECRET trong config.toml. Không phải secret thật.
-- Cloud: KHÔNG dùng file này — tạo secret thật theo supabase/README.md.
do $$
declare
  cfg record;
begin
  for cfg in
    select * from (values
      ('send_push_url', 'http://kong:8000/functions/v1/send-push'),
      ('send_push_webhook_secret', 'local-dev-push-secret')
    ) as t(name, value)
  loop
    if exists (select 1 from vault.secrets where name = cfg.name) then
      perform vault.update_secret((select id from vault.secrets where name = cfg.name), cfg.value);
    else
      perform vault.create_secret(cfg.value, cfg.name);
    end if;
  end loop;
end;
$$;
