-- RPC cho dữ liệu của người dùng đăng nhập (Phase 1 bước 4.1–4.4, 3.6). App gọi RPC, không query bảng trực tiếp
-- (contract = RPC, architecture.md 5.2) → .NET sau này expose endpoint cùng shape.
-- Mã lỗi riêng: AC429 = vượt giới hạn (app map → RepositoryError.rateLimited).

-- ───── Bookmark ─────

create or replace function public.my_bookmarks()
returns setof jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object('project_id', b.project_id, 'notify_enabled', b.notify_enabled, 'created_at', b.created_at)
  from public.bookmarks b
  where b.user_id = auth.uid()
  order by b.created_at desc;
$$;

-- Lưu / bỏ lưu. Trả trạng thái mới (true = đang lưu). Id dự án không tồn tại → P0002.
create or replace function public.toggle_bookmark(project_id uuid)
returns boolean
language plpgsql
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  delete from public.bookmarks b where b.user_id = auth.uid() and b.project_id = toggle_bookmark.project_id;
  if found then
    return false;
  end if;
  if not exists (select 1 from public.projects p where p.id = toggle_bookmark.project_id) then
    raise exception 'project % not found', project_id using errcode = 'P0002';
  end if;
  insert into public.bookmarks (user_id, project_id) values (auth.uid(), toggle_bookmark.project_id);
  return true;
end;
$$;

-- Bật thông báo cho dự án chưa lưu → tự lưu (giống mock). Tắt cho dự án chưa lưu → không làm gì.
create or replace function public.set_bookmark_notify(project_id uuid, enabled boolean)
returns void
language plpgsql
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if enabled then
    insert into public.bookmarks (user_id, project_id, notify_enabled)
    values (auth.uid(), set_bookmark_notify.project_id, true)
    on conflict on constraint bookmarks_pkey do update set notify_enabled = true;
  else
    update public.bookmarks b set notify_enabled = false
    where b.user_id = auth.uid() and b.project_id = set_bookmark_notify.project_id;
  end if;
end;
$$;

-- ───── Báo thông tin sai: giới hạn 10 lần / 24 giờ / người (chống spam đội dữ liệu) ─────

create or replace function public.report_data(project_id uuid, note text)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  report_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if (select count(*) from public.data_reports r
      where r.reporter_id = auth.uid() and r.created_at > now() - interval '24 hours') >= 10 then
    raise exception 'report limit reached' using errcode = 'AC429';
  end if;
  insert into public.data_reports (project_id, reporter_id, note)
  values (report_data.project_id, auth.uid(), trim(note))
  returning id into report_id;
  return report_id;
end;
$$;

-- ───── Push token ─────
-- Token sandbox (bản Debug/Xcode) và production (TestFlight/App Store) gửi tới host APNs khác nhau.
-- send-push chọn host theo cột này → không xóa nhầm token chỉ vì gửi sai môi trường.
alter table public.push_tokens
  add column environment text not null default 'production' check (environment in ('sandbox', 'production'));

-- Đăng ký token cho người gọi. Một máy đổi tài khoản → token chuyển chủ (xóa bản ghi của người khác),
-- tránh người cũ nhận thông báo trên máy người mới. Cần SECURITY DEFINER vì RLS không cho xóa dòng của người khác.
create or replace function public.register_push_token(token text, environment text default 'production')
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if token !~ '^[0-9a-f]{64,200}$' then
    raise exception 'invalid token' using errcode = '22023';
  end if;
  delete from public.push_tokens t where t.token = register_push_token.token and t.user_id <> auth.uid();
  insert into public.push_tokens (user_id, token, platform, environment, updated_at)
  values (auth.uid(), register_push_token.token, 'ios', register_push_token.environment, now())
  on conflict on constraint push_tokens_pkey do update
    set environment = excluded.environment, updated_at = now();
end;
$$;

-- Gọi khi đăng xuất (trước khi bỏ phiên) để máy không còn nhận thông báo của tài khoản.
create or replace function public.unregister_push_token(token text)
returns void
language sql
set search_path = ''
as $$
  delete from public.push_tokens t where t.user_id = auth.uid() and t.token = unregister_push_token.token;
$$;

-- ───── Quyền ─────
revoke execute on function public.my_bookmarks() from public, anon;
revoke execute on function public.toggle_bookmark(uuid) from public, anon;
revoke execute on function public.set_bookmark_notify(uuid, boolean) from public, anon;
revoke execute on function public.report_data(uuid, text) from public, anon;
revoke execute on function public.register_push_token(text, text) from public, anon;
revoke execute on function public.unregister_push_token(text) from public, anon;
grant execute on function public.my_bookmarks() to authenticated;
grant execute on function public.toggle_bookmark(uuid) to authenticated;
grant execute on function public.set_bookmark_notify(uuid, boolean) to authenticated;
grant execute on function public.report_data(uuid, text) to authenticated;
grant execute on function public.register_push_token(text, text) to authenticated;
grant execute on function public.unregister_push_token(text) to authenticated;
