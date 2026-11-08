-- Icon tự chọn cho địa điểm đã lưu (PRD 4.6). Lưu MÃ danh mục `place_icons` (vd `cho_lam`), không lưu tên SF Symbol:
-- Android sau này tự ánh xạ mã; server thêm icon mới (kèm sf_symbol) mà không cần phát hành app.
-- null = dùng icon theo loại (`place_kinds.sf_symbol`).

alter table public.lookup_items drop constraint lookup_items_category_check;
alter table public.lookup_items add constraint lookup_items_category_check check (category in (
  'project_statuses', 'legal_statuses', 'route_types', 'route_statuses', 'node_types',
  'service_areas', 'eligibility_subjects', 'housing_conditions', 'notification_types', 'place_kinds', 'place_icons'));

-- Chèn ở migration để cloud có ngay (cloud không chạy seed); seed ghi đè nhãn (on conflict).
insert into public.lookup_items (category, code, label_vi, sort_order, sf_symbol) values
  ('place_icons', 'nha', 'Nhà', 1, 'house.fill'),
  ('place_icons', 'chung_cu', 'Chung cư', 2, 'building.2.fill'),
  ('place_icons', 'cho_lam', 'Chỗ làm', 3, 'briefcase.fill'),
  ('place_icons', 'nha_bo_me', 'Nhà bố mẹ', 4, 'heart.fill'),
  ('place_icons', 'truong_hoc', 'Trường học', 5, 'graduationcap.fill'),
  ('place_icons', 'benh_vien', 'Bệnh viện', 6, 'cross.case.fill'),
  ('place_icons', 'cho', 'Chợ, siêu thị', 7, 'cart.fill'),
  ('place_icons', 'an_uong', 'Ăn uống', 8, 'fork.knife'),
  ('place_icons', 'cong_vien', 'Công viên', 9, 'tree.fill'),
  ('place_icons', 'the_thao', 'Thể thao', 10, 'figure.run'),
  ('place_icons', 'ga_ben_xe', 'Ga, bến xe', 11, 'tram.fill'),
  ('place_icons', 'san_bay', 'Sân bay', 12, 'airplane'),
  ('place_icons', 'ngan_hang', 'Ngân hàng', 13, 'banknote.fill'),
  ('place_icons', 'ton_giao', 'Chùa, nhà thờ', 14, 'building.columns.fill'),
  ('place_icons', 'yeu_thich', 'Yêu thích', 15, 'star.fill'),
  ('place_icons', 'ghim', 'Ghim', 16, 'mappin')
on conflict (category, code) do nothing;

alter table public.saved_places
  add column icon_category text generated always as ('place_icons') stored,
  add column icon text,
  add foreign key (icon_category, icon) references public.lookup_items (category, code);

create or replace function public.saved_place_json(p public.saved_places)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p.id, 'name', p.name, 'address', p.address, 'location', public.point_json(p.location),
    'kind', p.kind, 'icon', p.icon, 'service_area', p.service_area, 'note', p.note, 'external_ref', p.external_ref,
    'created_at', p.created_at, 'updated_at', p.updated_at);
$$;

-- Đổi chữ ký (thêm `icon`) → bỏ bản cũ: PostgREST không chọn được giữa hai bản trùng tên.
drop function public.create_saved_place(text, double precision, double precision, text, text, text, text);
drop function public.update_saved_place(uuid, text, text, text);

create or replace function public._check_place_icon(icon text)
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if icon is not null and not exists (select 1 from public.lookup_items l where l.category = 'place_icons' and l.code = icon) then
    raise exception 'unknown icon %', icon using errcode = '22023';
  end if;
end;
$$;

create or replace function public.create_saved_place(
  name text,
  lat double precision,
  lng double precision,
  kind text,
  address text default null,
  note text default null,
  external_ref text default null,
  icon text default null
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
  perform public._check_place_icon(create_saved_place.icon);
  area := public.mvp_service_area_at(lat, lng);
  if area is null then
    raise exception 'outside service area' using errcode = 'AC403';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('saved_places:' || auth.uid()::text, 0));
  if (select count(*) from public.saved_places p where p.user_id = auth.uid()) >= 200 then
    raise exception 'saved place limit reached' using errcode = 'AC409';
  end if;
  insert into public.saved_places (user_id, name, address, location, kind, icon, service_area, note, external_ref)
  values (
    auth.uid(), trim(create_saved_place.name), nullif(trim(create_saved_place.address), ''),
    extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326)::extensions.geography,
    create_saved_place.kind, create_saved_place.icon, area, nullif(trim(create_saved_place.note), ''),
    nullif(trim(create_saved_place.external_ref), '')
  )
  returning * into created;
  return public.saved_place_json(created);
exception
  when check_violation then
    raise exception 'invalid saved place' using errcode = '22023';
end;
$$;

-- `icon` null = về icon theo loại.
create or replace function public.update_saved_place(id uuid, name text, kind text, note text, icon text default null)
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
  perform public._check_place_icon(update_saved_place.icon);
  update public.saved_places p
  set name = trim(update_saved_place.name), kind = update_saved_place.kind, icon = update_saved_place.icon,
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

revoke execute on function public._check_place_icon(text) from public, anon, authenticated;
revoke execute on function public.create_saved_place(text, double precision, double precision, text, text, text, text, text) from public, anon;
revoke execute on function public.update_saved_place(uuid, text, text, text, text) from public, anon;
grant execute on function public.create_saved_place(text, double precision, double precision, text, text, text, text, text) to authenticated;
grant execute on function public.update_saved_place(uuid, text, text, text, text) to authenticated;
