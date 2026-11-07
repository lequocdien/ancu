-- An Cư — 1/5: extension, chuẩn hóa tìm kiếm, danh mục (lookup), đơn vị hành chính.
--
-- Danh mục là BẢNG (không phải Postgres enum): thêm trạng thái mới = insert một dòng, không cần migration.
-- App cũ gặp code lạ thì map về `.unknown` (xem Domain/Models/Lookup.swift).

create extension if not exists postgis with schema extensions;
create extension if not exists unaccent with schema extensions;

-- Bỏ dấu, chữ thường, "đ" → "d": "thu duc" khớp "Thủ Đức". Khớp SearchNormalizer phía app.
create or replace function public.normalize_search(input text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select trim(lower(extensions.unaccent(
    'extensions.unaccent'::regdictionary,
    replace(replace(coalesce(input, ''), 'đ', 'd'), 'Đ', 'd')
  )));
$$;

create table public.lookup_items (
  category   text not null check (category in (
               'project_statuses', 'legal_statuses', 'route_types', 'route_statuses', 'node_types',
               'service_areas', 'eligibility_subjects', 'housing_conditions', 'notification_types')),
  code       text not null check (code ~ '^[a-z0-9_]+$'),
  label_vi   text not null,
  sort_order int  not null default 0,
  color_hex  text check (color_hex ~ '^#[0-9A-Fa-f]{6}$'),
  sf_symbol  text,
  -- line_style (route_statuses), new_province / in_mvp (service_areas)…
  attributes jsonb not null default '{}'::jsonb check (jsonb_typeof(attributes) = 'object'),
  center     extensions.geography(point, 4326),
  primary key (category, code)
);

comment on table public.lookup_items is 'Danh mục dùng chung. Nhãn/màu/icon đổi từ đây, không cần phát hành app.';

-- Phường/xã theo địa giới MỚI, giữ tên cũ để tìm kiếm.
create table public.administrative_units (
  code                  text primary key check (code ~ '^[a-z0-9_]+$'),
  name                  text not null,
  province              text not null,
  service_area          text not null,
  service_area_category text generated always as ('service_areas') stored,
  old_names             text[] not null default '{}',
  center                extensions.geography(point, 4326) not null,
  foreign key (service_area_category, service_area) references public.lookup_items (category, code)
);

comment on column public.administrative_units.service_area is
  'Vùng phục vụ theo địa giới CŨ (hcm_cu, binh_duong_cu…). Không lọc theo province mới: TP.HCM mới gồm cả Bà Rịa – Vũng Tàu cũ.';
