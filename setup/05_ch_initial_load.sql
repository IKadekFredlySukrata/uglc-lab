-- [ClickHouse] 5. Copy everything from Postgres once.
-- postgresql(...) reads a Postgres table/view over the network ("postgis" = the Postgres service).
-- Columns match BY POSITION; start_date becomes start_year with toYear().

INSERT INTO landslides
SELECT id, lon, lat, country, toYear(start_date), type, physical_factors, fatalities, injuries, updated_at
FROM postgresql('postgis:5432', 'uglc', 'landslides_clickhouse', 'uglc', 'uglc_dev_pw');

-- The initial load counts as the first sync, so the first real sync starts from now instead of
-- re-copying all 1M rows. (INSERT ... SELECT, not VALUES: clickhouse-client would wait for VALUES
-- rows on stdin.)
INSERT INTO sync_log
SELECT now64(6), now64(6), toDateTime64(0, 6, 'UTC'), count(), 'initial load'
FROM landslides;
