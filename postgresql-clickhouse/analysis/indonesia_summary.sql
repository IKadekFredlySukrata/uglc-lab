-- Ringkasan untuk test.sh: satu baris/kelompok per section, dipakai untuk
-- menyusun bagian "Profil tanah longsor Indonesia" di summary.md.
-- Semua section memakai pemisah "|" dan hanya mengembalikan teks.

-- @overview events|known_fatalities|total_fatalities|unknown_pct|total_injuries|max_fatalities
SELECT count(*)::text,
       count(fatalities)::text,
       coalesce(sum(fatalities), 0)::text,
       round(100.0 * (count(*) - count(fatalities)) / count(*), 1)::text,
       coalesce(sum(injuries), 0)::text,
       coalesce(max(fatalities), 0)::text
FROM landslides
WHERE country = 'Indonesia' AND notes NOT LIKE 'TEST %';

-- @checks columns|primary_keys|foreign_keys|checks|not_null|geom_type|srid|sentinel_rows|end_before_start|duplicate_ids|wrong_srid|not_point|indonesia_null_geom
SELECT
  (SELECT count(*) FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'landslides')::text,
  (SELECT count(*) FROM pg_constraint
    WHERE conrelid = 'public.landslides'::regclass AND contype = 'p')::text,
  (SELECT count(*) FROM pg_constraint
    WHERE conrelid = 'public.landslides'::regclass AND contype = 'f')::text,
  (SELECT count(*) FROM pg_constraint
    WHERE conrelid = 'public.landslides'::regclass AND contype = 'c')::text,
  (SELECT count(*) FROM pg_attribute
    WHERE attrelid = 'public.landslides'::regclass
      AND attnum > 0 AND NOT attisdropped AND attnotnull)::text,
  (SELECT postgis_typmod_type(atttypmod) FROM pg_attribute
    WHERE attrelid = 'public.landslides'::regclass AND attname = 'geom')::text,
  (SELECT postgis_typmod_srid(atttypmod)::text FROM pg_attribute
    WHERE attrelid = 'public.landslides'::regclass AND attname = 'geom')::text,
  (SELECT count(*) FROM landslides
    WHERE type = 'ND' OR physical_factors = 'ND' OR notes = 'ND'
       OR link IN ('Source: ND', 'Source: ''ND''', 'Source: Unknown')
       OR fatalities = -99999 OR injuries = -99999 OR accuracy_m = -99999)::text,
  (SELECT count(*) FROM landslides WHERE end_date < start_date)::text,
  (SELECT count(*) - count(DISTINCT id) FROM landslides)::text,
  (SELECT count(*) FROM landslides
    WHERE geom IS NOT NULL AND ST_SRID(geom) <> 4326)::text,
  (SELECT count(*) FROM landslides
    WHERE geom IS NOT NULL AND GeometryType(geom) <> 'POINT')::text,
  (SELECT count(*) FROM landslides
    WHERE country = 'Indonesia' AND geom IS NULL)::text;

-- @sources source|events|known_fatalities|total_fatalities
SELECT source_dataset,
       count(*)::text,
       count(fatalities)::text,
       coalesce(sum(fatalities), 0)::text
FROM landslides
WHERE country = 'Indonesia' AND notes NOT LIKE 'TEST %'
GROUP BY source_dataset
ORDER BY count(*) DESC;

-- @triggers trigger|events|known_fatalities|total_fatalities
SELECT coalesce(physical_factors, '(NULL)'),
       count(*)::text,
       count(fatalities)::text,
       coalesce(sum(fatalities), 0)::text
FROM landslides
WHERE country = 'Indonesia' AND notes NOT LIKE 'TEST %'
GROUP BY physical_factors
ORDER BY count(*) DESC;

-- @types type|events|known_fatalities|total_fatalities
SELECT coalesce(type, '(NULL)'),
       count(*)::text,
       count(fatalities)::text,
       coalesce(sum(fatalities), 0)::text
FROM landslides
WHERE country = 'Indonesia' AND notes NOT LIKE 'TEST %'
GROUP BY type
ORDER BY count(*) DESC;

-- @completeness rows|fatalities_known_pct|type_null|trigger_null|accuracy_zero|geom_null|notes_null|link_null
SELECT count(*)::text,
       round(100.0 * count(fatalities) / count(*), 1)::text,
       (count(*) - count(type))::text,
       (count(*) - count(physical_factors))::text,
       count(*) FILTER (WHERE accuracy_m = 0)::text,
       (count(*) - count(geom))::text,
       (count(*) - count(notes))::text,
       (count(*) - count(link))::text
FROM landslides
WHERE country = 'Indonesia' AND notes NOT LIKE 'TEST %';

-- @duplicates pairs|distinct_rows
-- Tanggal + jumlah korban sama, sumber berbeda, jarak <= 5 km.
WITH pairs AS (
  SELECT a.id AS id1, b.id AS id2
  FROM landslides a
  JOIN landslides b
    ON a.id < b.id
   AND a.country = 'Indonesia' AND b.country = 'Indonesia'
   AND a.notes NOT LIKE 'TEST %' AND b.notes NOT LIKE 'TEST %'
   AND a.start_date = b.start_date
   AND a.fatalities IS NOT NULL AND a.fatalities = b.fatalities
   AND a.source_dataset <> b.source_dataset
   AND a.geom IS NOT NULL AND b.geom IS NOT NULL
   AND ST_DWithin(a.geom::geography, b.geom::geography, 5000)
)
SELECT count(*)::text,
       (count(DISTINCT id1) + count(DISTINCT id2))::text
FROM pairs;

-- @top date|type|trigger|fatalities|injuries
-- Duplikat lintas sumber yang persis (tanggal + korban sama, radius 5 km) disembunyikan.
SELECT a.start_date::text,
       coalesce(a.type, '(NULL)'),
       coalesce(a.physical_factors, '(NULL)'),
       a.fatalities::text,
       coalesce(a.injuries, 0)::text
FROM landslides a
WHERE a.country = 'Indonesia' AND a.notes NOT LIKE 'TEST %'
  AND a.fatalities IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM landslides b
    WHERE b.id < a.id
      AND b.country = 'Indonesia' AND b.notes NOT LIKE 'TEST %'
      AND b.start_date = a.start_date
      AND b.fatalities = a.fatalities
      AND b.source_dataset <> a.source_dataset
      AND b.geom IS NOT NULL AND a.geom IS NOT NULL
      AND ST_DWithin(b.geom::geography, a.geom::geography, 5000))
ORDER BY a.fatalities DESC, a.injuries DESC NULLS LAST, a.start_date
LIMIT 5;
