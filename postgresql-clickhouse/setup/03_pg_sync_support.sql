-- [PostgreSQL] 3. What ClickHouse reads, and what the sync needs.
-- The visitor indexes (start_date, country, geography) are NOT created here on purpose:
-- ./test.sh measures V1–V4 without them first, then creates them (test/02_pg_visitor_indexes.sql).

-- ClickHouse doesn't understand PostGIS geometry, so it reads this view: geom split into plain
-- lon/lat numbers, and only the columns the dashboard (B1–B5) and the sync need.
CREATE VIEW landslides_clickhouse AS
SELECT id,
       ST_X(geom) AS lon,
       ST_Y(geom) AS lat,
       country,
       start_date,
       type,
       physical_factors,
       fatalities,
       injuries,
       updated_at
FROM landslides;

-- The sync asks "what changed since the last sync?" every few seconds. Without this index that
-- is a full scan of the portal's table each time (NFR-5); with it, an index-only scan.
CREATE INDEX landslides_updated_at_idx ON landslides (updated_at);

-- Clean up after the big load and collect statistics for the query planner
VACUUM ANALYZE landslides;
