-- Địa điểm đã lưu + ghi chú (PRD 4.6, architecture.md 5.6, plan Bước 6).
-- - `saved_places`: dự án/địa điểm NGOÀI hệ thống người dùng tự lưu — riêng tư, chỉ trong vùng MVP, ≤ 200/người.
-- - `bookmarks.note`: ghi chú cho dự án TRONG hệ thống (luồng thông báo giữ nguyên).
-- - `data_reports`: thêm loại "đề xuất thêm dự án" (chung giới hạn 10/24h với báo sai).
-- Mọi thao tác ghi của người dùng đi qua RPC SECURITY DEFINER (bài học migration 11: policy ghi thẳng làm lọt giới hạn).
-- Mã lỗi riêng: AC403 = ngoài vùng hỗ trợ, AC409 = vượt giới hạn số địa điểm, AC429 = vượt giới hạn báo cáo/đề xuất.

-- ───── 1. Danh mục loại địa điểm ─────
alter table public.lookup_items drop constraint lookup_items_category_check;
alter table public.lookup_items add constraint lookup_items_category_check check (category in (
  'project_statuses', 'legal_statuses', 'route_types', 'route_statuses', 'node_types',
  'service_areas', 'eligibility_subjects', 'housing_conditions', 'notification_types', 'place_kinds'));

-- Chèn ở migration (không chỉ seed) để project cloud có ngay khi `db push --remote`. Seed ghi đè nhãn (on conflict).
insert into public.lookup_items (category, code, label_vi, sort_order, color_hex, sf_symbol) values
  ('place_kinds', 'noxh', 'Nhà ở xã hội', 1, '#10B981', 'house.fill'),
  ('place_kinds', 'thuong_mai', 'Thương mại', 2, '#0EA5E9', 'building.2.fill'),
  ('place_kinds', 'khac', 'Khác', 3, '#8B5CF6', 'mappin')
on conflict (category, code) do nothing;

-- ───── 2. Ghi chú cho bookmark ─────
alter table public.bookmarks
  add column note text check (note is null or char_length(note) between 1 and 2000);

create or replace function public.my_bookmarks()
returns setof jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object('project_id', b.project_id, 'notify_enabled', b.notify_enabled,
                            'note', b.note, 'created_at', b.created_at)
  from public.bookmarks b
  where b.user_id = auth.uid()
  order by b.created_at desc;
$$;

-- Ghi chú dự án đã lưu. Chưa lưu + có ghi chú → tự lưu (như set_bookmark_notify). Rỗng/khoảng trắng → xóa ghi chú.
create or replace function public.set_bookmark_note(project_id uuid, note text)
returns void
language plpgsql
set search_path = ''
as $$
declare
  cleaned text := nullif(trim(note), '');
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if char_length(cleaned) > 2000 then
    raise exception 'note too long' using errcode = '22023';
  end if;
  update public.bookmarks b set note = cleaned
  where b.user_id = auth.uid() and b.project_id = set_bookmark_note.project_id;
  if found or cleaned is null then
    return;
  end if;
  if not exists (select 1 from public.projects p where p.id = set_bookmark_note.project_id) then
    raise exception 'project % not found', project_id using errcode = 'P0002';
  end if;
  insert into public.bookmarks (user_id, project_id, note) values (auth.uid(), set_bookmark_note.project_id, cleaned);
end;
$$;

-- ───── 3. Vùng MVP tại một điểm ─────
-- Vùng phục vụ in_mvp chứa điểm, hoặc cách ranh giới ≤ tolerance_m (ranh giới đang là mock giản lược → dung sai 3 km).
-- Nhiều vùng thỏa → vùng gần nhất (điểm nằm trong vùng có khoảng cách 0). Không thuộc vùng nào → null.
create or replace function public.mvp_service_area_at(lat double precision, lng double precision, tolerance_m double precision default 3000)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  with pt as (
    select extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326)::extensions.geography as g
  )
  select b.code
  from public.service_area_boundaries b
  join public.lookup_items l on l.category = 'service_areas' and l.code = b.code and l.attributes ->> 'in_mvp' = 'true',
       pt
  where extensions.st_dwithin(b.geom, pt.g, tolerance_m)
  order by extensions.st_distance(b.geom, pt.g), b.code
  limit 1;
$$;

-- ───── 4. Địa điểm đã lưu ─────
create table public.saved_places (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  name          text not null check (char_length(trim(name)) between 1 and 200),
  address       text check (address is null or char_length(address) <= 500),
  location      extensions.geography(Point, 4326) not null,
  kind_category text generated always as ('place_kinds') stored,
  kind          text not null,
  area_category text generated always as ('service_areas') stored,
  service_area  text not null,
  note          text check (note is null or char_length(note) between 1 and 2000),
  external_ref  text check (external_ref is null or char_length(external_ref) <= 500),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  foreign key (kind_category, kind) references public.lookup_items (category, code),
  foreign key (area_category, service_area) references public.lookup_items (category, code)
);

create index saved_places_user_idx on public.saved_places (user_id, updated_at desc);

alter table public.saved_places enable row level security;
-- Chỉ đọc dòng của mình qua API; ghi chỉ qua RPC (thu hồi quyền ghi bảng → lỡ thêm policy ghi cũng không lọt giới hạn).
create policy "own saved places read" on public.saved_places
  for select to authenticated using (user_id = (select auth.uid()));
revoke all on public.saved_places from anon;
revoke insert, update, delete, truncate on public.saved_places from authenticated;

create or replace function public.saved_place_json(p public.saved_places)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p.id, 'name', p.name, 'address', p.address, 'location', public.point_json(p.location),
    'kind', p.kind, 'service_area', p.service_area, 'note', p.note, 'external_ref', p.external_ref,
    'created_at', p.created_at, 'updated_at', p.updated_at);
$$;

create or replace function public.my_saved_places()
returns setof jsonb
language sql
stable
set search_path = ''
as $$
  select public.saved_place_json(p) from public.saved_places p
  where p.user_id = auth.uid()
  order by p.updated_at desc, p.id;
$$;

create or replace function public.create_saved_place(
  name text,
  lat double precision,
  lng double precision,
  kind text,
  address text default null,
  note text default null,
  external_ref text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  area text;
  created public.saved_places;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if lat is null or lng is null or lat not between -90 and 90 or lng not between -180 and 180 then
    raise exception 'invalid coordinate' using errcode = '22023';
  end if;
  if not exists (select 1 from public.lookup_items l where l.category = 'place_kinds' and l.code = create_saved_place.kind) then
    raise exception 'unknown kind %', kind using errcode = '22023';
  end if;
  area := public.mvp_service_area_at(lat, lng);
  if area is null then
    raise exception 'outside service area' using errcode = 'AC403';
  end if;
  -- Khóa theo người dùng: hai lần lưu song song không cùng lọt qua ngưỡng 200.
  perform pg_advisory_xact_lock(hashtextextended('saved_places:' || auth.uid()::text, 0));
  if (select count(*) from public.saved_places p where p.user_id = auth.uid()) >= 200 then
    raise exception 'saved place limit reached' using errcode = 'AC409';
  end if;
  insert into public.saved_places (user_id, name, address, location, kind, service_area, note, external_ref)
  values (
    auth.uid(), trim(create_saved_place.name), nullif(trim(create_saved_place.address), ''),
    extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326)::extensions.geography,
    create_saved_place.kind, area, nullif(trim(create_saved_place.note), ''),
    nullif(trim(create_saved_place.external_ref), '')
  )
  returning * into created;
  return public.saved_place_json(created);
exception
  when check_violation then
    raise exception 'invalid saved place' using errcode = '22023';
end;
$$;

-- Sửa tên/loại/ghi chú. Vị trí không sửa (muốn đổi → xóa rồi ghim lại). Không phải của mình → P0002 (không lộ tồn tại).
create or replace function public.update_saved_place(id uuid, name text, kind text, note text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  updated public.saved_places;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not exists (select 1 from public.lookup_items l where l.category = 'place_kinds' and l.code = update_saved_place.kind) then
    raise exception 'unknown kind %', kind using errcode = '22023';
  end if;
  update public.saved_places p
  set name = trim(update_saved_place.name), kind = update_saved_place.kind,
      note = nullif(trim(update_saved_place.note), ''), updated_at = now()
  where p.id = update_saved_place.id and p.user_id = auth.uid()
  returning * into updated;
  if not found then
    raise exception 'saved place % not found', id using errcode = 'P0002';
  end if;
  return public.saved_place_json(updated);
exception
  when check_violation then
    raise exception 'invalid saved place' using errcode = '22023';
end;
$$;

create or replace function public.delete_saved_place(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  delete from public.saved_places p where p.id = delete_saved_place.id and p.user_id = auth.uid();
  return found;
end;
$$;

-- ───── 5. Đề xuất thêm dự án (dùng lại data_reports) ─────
alter table public.data_reports
  add column kind text not null default 'sai_thong_tin' check (kind in ('sai_thong_tin', 'de_xuat_du_an')),
  add column suggested_name text check (suggested_name is null or char_length(suggested_name) between 1 and 200),
  add column suggested_address text check (suggested_address is null or char_length(suggested_address) <= 500),
  add column suggested_location extensions.geography(Point, 4326),
  alter column project_id drop not null;

alter table public.data_reports add constraint data_reports_kind_shape check (
  (kind = 'sai_thong_tin' and project_id is not null)
  or (kind = 'de_xuat_du_an' and project_id is null and suggested_name is not null and suggested_location is not null)
);

-- Chỉ gửi tên/địa chỉ/vị trí — KHÔNG gửi ghi chú riêng của người dùng. Ngoài vùng MVP → AC403.
create or replace function public.suggest_project(name text, lat double precision, lng double precision, address text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  report_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if lat is null or lng is null or lat not between -90 and 90 or lng not between -180 and 180 then
    raise exception 'invalid coordinate' using errcode = '22023';
  end if;
  if public.mvp_service_area_at(lat, lng) is null then
    raise exception 'outside service area' using errcode = 'AC403';
  end if;
  if (select count(*) from public.data_reports r
      where r.reporter_id = auth.uid() and r.created_at > now() - interval '24 hours') >= 10 then
    raise exception 'report limit reached' using errcode = 'AC429';
  end if;
  insert into public.data_reports (kind, project_id, reporter_id, note, suggested_name, suggested_address, suggested_location)
  values (
    'de_xuat_du_an', null, auth.uid(), left('Đề xuất thêm dự án: ' || trim(suggest_project.name), 500),
    trim(suggest_project.name), nullif(trim(suggest_project.address), ''),
    extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326)::extensions.geography
  )
  returning id into report_id;
  return report_id;
exception
  when check_violation then
    raise exception 'invalid suggestion' using errcode = '22023';
end;
$$;

-- ───── Quyền ─────
revoke execute on function public.mvp_service_area_at(double precision, double precision, double precision) from public, anon, authenticated;
revoke execute on function public.saved_place_json(public.saved_places) from public, anon;

revoke execute on function public.set_bookmark_note(uuid, text) from public, anon;
revoke execute on function public.my_saved_places() from public, anon;
revoke execute on function public.create_saved_place(text, double precision, double precision, text, text, text, text) from public, anon;
revoke execute on function public.update_saved_place(uuid, text, text, text) from public, anon;
revoke execute on function public.delete_saved_place(uuid) from public, anon;
revoke execute on function public.suggest_project(text, double precision, double precision, text) from public, anon;

grant execute on function public.set_bookmark_note(uuid, text) to authenticated;
grant execute on function public.my_saved_places() to authenticated;
grant execute on function public.create_saved_place(text, double precision, double precision, text, text, text, text) to authenticated;
grant execute on function public.update_saved_place(uuid, text, text, text) to authenticated;
grant execute on function public.delete_saved_place(uuid) to authenticated;
grant execute on function public.suggest_project(text, double precision, double precision, text) to authenticated;
