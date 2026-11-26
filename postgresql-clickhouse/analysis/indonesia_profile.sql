-- Profil tanah longsor Indonesia dari tabel clean `landslides` (PostgreSQL + PostGIS).
-- Jalankan dari folder postgresql-clickhouse:
--   docker exec -i uglc-lab-postgis psql -U uglc -d uglc -v ON_ERROR_STOP=1 < analysis/indonesia_profile.sql
--
-- Semua analisis mengecualikan baris uji C1 (notes LIKE 'TEST %'), sehingga
-- jumlah baris Indonesia yang dianalisis adalah 7.883 dari total 1.060.503 baris UGLC.

\pset pager off

\echo === 0. KONFORMASI SKEMA ===
SELECT column_name, data_type, udt_name, is_nullable, column_default,
       is_identity, identity_generation
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'landslides'
ORDER BY ordinal_position;

SELECT conname, contype, pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'public.landslides'::regclass
ORDER BY contype, conname;

SELECT postgis_typmod_type(atttypmod) AS geometry_type,
       postgis_typmod_srid(atttypmod) AS srid
FROM pg_attribute
WHERE attrelid = 'public.landslides'::regclass AND attname = 'geom';

\echo === 1. JUMLAH BARIS DAN PEMERIKSAAN KEBERSIHAN ===
SELECT count(*) AS total_rows,
       count(*) FILTER (WHERE country = 'Indonesia') AS indonesia_rows,
       count(*) FILTER (WHERE notes LIKE 'TEST %') AS test_rows,
       count(*) FILTER (WHERE country = 'Indonesia' AND notes NOT LIKE 'TEST %') AS indonesia_uglc
FROM landslides;

SELECT
  count(*) FILTER (WHERE country IS NULL) AS country_null,
  count(*) FILTER (WHERE start_date IS NULL OR end_date IS NULL) AS date_null,
  count(*) FILTER (WHERE end_date < start_date) AS end_before_start,
  count(*) FILTER (WHERE geom IS NULL) AS geom_null,
  count(*) FILTER (WHERE geom IS NOT NULL AND ST_SRID(geom) <> 4326) AS wrong_srid,
  count(*) FILTER (WHERE geom IS NOT NULL AND GeometryType(geom) <> 'POINT') AS not_point,
  count(*) FILTER (WHERE type = 'ND') AS type_ND,
  count(*) FILTER (WHERE physical_factors = 'ND') AS trigger_ND,
  count(*) FILTER (WHERE notes = 'ND') AS notes_ND,
  count(*) FILTER (WHERE link IN ('Source: ND', 'Source: ''ND''', 'Source: Unknown')) AS link_sentinel,
  count(*) FILTER (WHERE fatalities = -99999) AS fatalities_sentinel,
  count(*) FILTER (WHERE injuries = -99999) AS injuries_sentinel,
  count(*) FILTER (WHERE accuracy_m = -99999) AS accuracy_sentinel,
  count(*) - count(DISTINCT id) AS duplicate_ids
FROM landslides;

\echo === 2. GAMBARAN UMUM INDONESIA ===
SELECT count(*) AS events,
       min(start_date) AS first_date,
       max(start_date) AS last_date,
       count(DISTINCT EXTRACT(YEAR FROM start_date)) AS years_covered,
       count(*) FILTER (WHERE fatalities IS NOT NULL) AS events_with_fatalities,
       round(100.0 * count(fatalities) / count(*), 1) AS fatalities_known_pct,
       sum(fatalities) AS total_fatalities,
       round(avg(fatalities) FILTER (WHERE fatalities IS NOT NULL), 2) AS avg_fatalities_per_known_event,
       max(fatalities) AS max_fatalities,
       sum(injuries) AS total_injuries,
       count(injuries) AS events_with_injuries,
       max(injuries) AS max_injuries
FROM landslides
WHERE country = 'Indonesia' AND notes NOT LIKE 'TEST %';

\echo === 3. SUMBER DATA ===
SELECT source_dataset, record_type, count(*) AS events,
       count(fatalities) AS known_fatalities,
       sum(fatalities) AS total_fatalities,
       round(100.0 * count(*) / 7883, 1) AS event_pct
FROM landslides
WHERE country = 'Indonesia' AND notes NOT LIKE 'TEST %'
GROUP BY source_dataset, record_type
ORDER BY events DESC;

\echo === 4. TRIGGER (physical_factors) ===
SELECT physical_factors AS trigger, count(*) AS events,
       round(100.0 * count(*) / 7883, 1) AS event_pct,
       count(fatalities) AS known_fatalities,
       sum(fatalities) AS total_fatalities,
       round(100.0 * sum(fatalities) / 7559, 1) AS fatality_pct,
       round(avg(fatalities) FILTER (WHERE fatalities IS NOT NULL), 1) AS avg_per_known
FROM landslides
WHERE country = 'Indonesia' AND notes NOT LIKE 'TEST %'
GROUP BY physical_factors
ORDER BY events DESC;

\echo === 5. TIPE LONGSOR ===
SELECT type, count(*) AS events,
       round(100.0 * count(*) / 7883, 1) AS event_pct,
       count(fatalities) AS known_fatalities,
       sum(fatalities) AS total_fatalities,
       round(100.0 * sum(fatalities) / 7559, 1) AS fatality_pct,
       round(avg(fatalities) FILTER (WHERE fatalities IS NOT NULL), 2) AS avg_per_known
FROM landslides
WHERE country = 'Indonesia' AND notes NOT LIKE 'TEST %'
GROUP BY type
ORDER BY events DESC;

\echo === 6. TREN TAHUNAN ===
SELECT EXTRACT(YEAR FROM start_date)::int AS year, count(*) AS events,
       count(fatalities) AS known_fatalities,
       sum(fatalities) AS total_fatalities
FROM landslides
WHERE country = 'Indonesia' AND notes NOT LIKE 'TEST %'
GROUP BY 1 ORDER BY 1;

\echo === 7. TREN PER DEKADE ===
SELECT (EXTRACT(YEAR FROM start_date)::int / 10) * 10 AS decade,
       count(*) AS events, count(fatalities) AS known_fatalities,
       sum(fatalities) AS total_fatalities
FROM landslides
WHERE country = 'Indonesia' AND notes NOT LIKE 'TEST %'
GROUP BY 1 ORDER BY 1;

\echo === 8. MUSIM (RAINFALL-TRIGGERED SAJA) ===
SELECT EXTRACT(MONTH FROM start_date)::int AS month, count(*) AS events,
       count(fatalities) AS known_fatalities,
       sum(fatalities) AS total_fatalities
FROM landslides
WHERE country = 'Indonesia' AND notes NOT LIKE 'TEST %'
  AND physical_factors = 'rainfall (T)'
GROUP BY 1 ORDER BY 1;

\echo === 9. DISTRIBUSI KORBAN ===
SELECT CASE WHEN fatalities IS NULL THEN 'unknown'
            WHEN fatalities = 0 THEN '0'
            WHEN fatalities BETWEEN 1 AND 9 THEN '1-9'
            WHEN fatalities BETWEEN 10 AND 99 THEN '10-99'
            WHEN fatalities BETWEEN 100 AND 999 THEN '100-999'
            ELSE '1000+' END AS bucket,
       count(*) AS events
FROM landslides
WHERE country = 'Indonesia' AND notes NOT LIKE 'TEST %'
GROUP BY 1 ORDER BY 1;

\echo === 10. HOTSPOT 1x1 DERAJAT (TANPA INVENTARIS PALU) ===
SELECT floor(ST_Y(geom))::int AS lat_cell, floor(ST_X(geom))::int AS lon_cell,
       count(*) AS events, count(fatalities) AS known_fatalities,
       sum(fatalities) AS total_fatalities
FROM landslides
WHERE country = 'Indonesia' AND notes NOT LIKE 'TEST %' AND geom IS NOT NULL
  AND source_dataset <> 'Earthquake-Triggered Ground-Failure Inventories'
GROUP BY 1, 2 ORDER BY events DESC LIMIT 12;

\echo === 11. HOTSPOT 1x1 DERAJAT (SEMUA DATA) ===
SELECT floor(ST_Y(geom))::int AS lat_cell, floor(ST_X(geom))::int AS lon_cell,
       count(*) AS events, count(fatalities) AS known_fatalities,
       sum(fatalities) AS total_fatalities
FROM landslides
WHERE country = 'Indonesia' AND notes NOT LIKE 'TEST %' AND geom IS NOT NULL
GROUP BY 1, 2 ORDER BY events DESC LIMIT 12;

\echo === 12. KEJADIAN PALING MEMATIKAN (DUPLIKAT LINTAS SUMBER PERSIS DISEMBUNYIKAN) ===
SELECT a.id, a.start_date, a.type, a.physical_factors AS trigger,
       a.fatalities, a.injuries, a.record_type, a.source_dataset,
       round(ST_Y(a.geom)::numeric, 3) AS lat,
       round(ST_X(a.geom)::numeric, 3) AS lon
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
LIMIT 12;

\echo === 13. INDIKASI DUPLIKASI LINTAS SUMBER ===
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
SELECT count(*) AS pairs,
       count(DISTINCT id1) + count(DISTINCT id2) AS distinct_rows
FROM pairs;

\echo === 14. KELENGKAPAN KOLOM ===
SELECT count(*) AS rows,
  round(100.0 * count(geom) / count(*), 1) AS geom_pct,
  round(100.0 * count(accuracy_m) / count(*), 1) AS accuracy_pct,
  round(100.0 * count(type) / count(*), 1) AS type_pct,
  round(100.0 * count(physical_factors) / count(*), 1) AS trigger_pct,
  round(100.0 * count(reliability) / count(*), 1) AS reliability_pct,
  round(100.0 * count(record_type) / count(*), 1) AS record_type_pct,
  round(100.0 * count(fatalities) / count(*), 1) AS fatalities_pct,
  round(100.0 * count(injuries) / count(*), 1) AS injuries_pct,
  round(100.0 * count(notes) / count(*), 1) AS notes_pct,
  round(100.0 * count(link) / count(*), 1) AS link_pct,
  round(100.0 * count(source_id) / count(*), 1) AS source_id_pct,
  round(100.0 * count(source_version) / count(*), 1) AS source_version_pct
FROM landslides
WHERE country = 'Indonesia' AND notes NOT LIKE 'TEST %';
