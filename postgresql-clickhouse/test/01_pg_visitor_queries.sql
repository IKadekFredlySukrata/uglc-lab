-- [PostgreSQL] Visitor portal queries V1–V4 (NFR-1: < 1 s).
-- test.sh runs each section twice (warm-up, then measured): once without and once with the
-- indexes from 02_pg_visitor_indexes.sql. EXPLAIN ANALYZE runs the query and shows the plan:
-- Seq Scan = read the whole table, Index Scan / Bitmap Index Scan = jump to the matching rows.

-- @V1 Show one landslide event (by id)
EXPLAIN ANALYZE
SELECT * FROM landslides
WHERE id = 500000;

-- @V2 Landslides between two dates (the year 2010)
EXPLAIN ANALYZE
SELECT * FROM landslides
WHERE start_date >= '2010-01-01' AND start_date < '2011-01-01';

-- @V3 Landslides in one country (Indonesia)
EXPLAIN ANALYZE
SELECT * FROM landslides
WHERE country = 'Indonesia';

-- @V4 Landslides within 20 km of a location (Surabaya)
-- ST_MakePoint is LONGITUDE first. ::geography makes the distance metres. The expression
-- geom::geography must match the indexed expression exactly, or the index isn't used.
EXPLAIN ANALYZE
SELECT * FROM landslides
WHERE ST_DWithin(
    geom::geography,
    ST_SetSRID(ST_MakePoint(112.75083, -7.24917), 4326)::geography,
    20000
);
