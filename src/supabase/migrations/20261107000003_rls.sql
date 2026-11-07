-- An Cư — 3/5: Row Level Security.
-- Khách (anon) chỉ đọc dữ liệu công khai. Người dùng chỉ đọc/sửa dữ liệu của chính mình.
-- Ghi dữ liệu dự án/tuyến chỉ bằng service role (trang quản trị) — không có policy ghi cho anon/authenticated.

alter table public.lookup_items          enable row level security;
alter table public.administrative_units  enable row level security;
alter table public.projects              enable row level security;
alter table public.infrastructure_routes enable row level security;
alter table public.infra_nodes           enable row level security;
alter table public.project_nearest_infra enable row level security;
alter table public.project_updates       enable row level security;
alter table public.eligibility_rules     enable row level security;
alter table public.app_config            enable row level security;
alter table public.profiles              enable row level security;
alter table public.bookmarks             enable row level security;
alter table public.notifications         enable row level security;
alter table public.push_tokens           enable row level security;
alter table public.data_reports          enable row level security;

-- Dữ liệu công khai: đọc cho mọi người.
create policy "public read" on public.lookup_items          for select to anon, authenticated using (true);
create policy "public read" on public.administrative_units  for select to anon, authenticated using (true);
create policy "public read" on public.projects              for select to anon, authenticated using (true);
create policy "public read" on public.infrastructure_routes for select to anon, authenticated using (true);
create policy "public read" on public.infra_nodes           for select to anon, authenticated using (true);
create policy "public read" on public.project_nearest_infra for select to anon, authenticated using (true);
-- Lịch sử thay đổi công khai: minh bạch nguồn và thời điểm đổi thông tin.
create policy "public read" on public.project_updates       for select to anon, authenticated using (true);
create policy "public read" on public.eligibility_rules     for select to anon, authenticated using (true);
create policy "public read" on public.app_config            for select to anon, authenticated using (true);

-- Hồ sơ: chỉ đọc/sửa của mình; chỉ được sửa display_name (vai trò, xác thực SĐT do server đặt).
create policy "own profile read" on public.profiles
  for select to authenticated using (id = (select auth.uid()));
create policy "own profile update" on public.profiles
  for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));
revoke update on public.profiles from authenticated;
grant update (display_name) on public.profiles to authenticated;

-- Bookmark: toàn quyền trên dòng của mình.
create policy "own bookmarks" on public.bookmarks
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- Thông báo: đọc của mình; chỉ được đánh dấu đã đọc.
create policy "own notifications read" on public.notifications
  for select to authenticated using (user_id = (select auth.uid()));
create policy "own notifications mark read" on public.notifications
  for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
revoke update on public.notifications from authenticated;
grant update (read_at) on public.notifications to authenticated;

-- Push token: toàn quyền trên dòng của mình.
create policy "own push tokens" on public.push_tokens
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- Báo sai: gửi dưới tên mình, xem lại báo cáo của mình; không sửa/xóa (trạng thái do đội dữ liệu đặt).
create policy "own reports insert" on public.data_reports
  for insert to authenticated with check (reporter_id = (select auth.uid()));
create policy "own reports read" on public.data_reports
  for select to authenticated using (reporter_id = (select auth.uid()));
