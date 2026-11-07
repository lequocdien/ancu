-- Ranh giới vùng phục vụ để highlight khi chọn vùng trên bản đồ. Hiện là mock giản lược (is_mock).
-- Nguồn: src/data/geojson/service_areas.geojson → seed.sql.
create table public.service_area_boundaries (
  code          text primary key,
  code_category text generated always as ('service_areas') stored,
  geom          extensions.geography(MultiPolygon, 4326) not null,
  is_mock       boolean not null default true,
  source_url    text not null check (source_url ~ '^https?://'),
  verified_at   date not null,
  foreign key (code_category, code) references public.lookup_items (category, code)
);

alter table public.service_area_boundaries enable row level security;
create policy "public read" on public.service_area_boundaries for select to anon, authenticated using (true);

-- Đúng shape `service_area_boundaries.json` của app: polygons = danh sách vòng ngoài, bỏ điểm đóng lặp.
-- tolerance_degrees > 0 → giản lược (ranh giới thật từ crawl sẽ có hàng nghìn điểm).
create or replace function public.service_area_boundary(code text, tolerance_degrees double precision default 0)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'code', b.code, 'is_mock', b.is_mock, 'source_url', b.source_url, 'verified_at', b.verified_at,
    'polygons', (
      select coalesce(jsonb_agg(ring order by d.path), '[]'::jsonb)
      from extensions.st_dump(
        case when tolerance_degrees > 0
             then extensions.st_simplifypreservetopology(b.geom::extensions.geometry, tolerance_degrees)
             else b.geom::extensions.geometry end
      ) d
      cross join lateral (
        select jsonb_agg(jsonb_build_object('lat', extensions.st_y(pt.geom), 'lng', extensions.st_x(pt.geom)) order by pt.path) as ring
        from extensions.st_dumppoints(extensions.st_exteriorring(d.geom)) pt
        where pt.path[1] < extensions.st_npoints(extensions.st_exteriorring(d.geom))
      ) r
    )
  )
  from public.service_area_boundaries b
  where b.code = service_area_boundary.code;
$$;
