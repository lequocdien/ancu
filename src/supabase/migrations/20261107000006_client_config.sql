-- Cấu hình phía client (Phase 1 bước 4.8). Chỉ trả các key app cần — không lộ cấu hình nội bộ (vd `moderation`).
-- Shape: {"min_supported_version": "0.1.0", "app_store_url": "https://…" | null}
create or replace function public.client_config(platform text default 'ios')
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'min_supported_version',
      coalesce((select value ->> platform from public.app_config where key = 'min_supported_version'), '0.0.0'),
    'app_store_url',
      (select value ->> platform from public.app_config where key = 'store_url')
  );
$$;
