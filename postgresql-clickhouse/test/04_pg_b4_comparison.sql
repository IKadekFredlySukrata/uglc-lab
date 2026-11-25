-- [PostgreSQL] B4 on the portal database, to compare with ClickHouse (NFR-5).
-- Same question as 04_ch_b4_comparison.sql. Postgres has no start_year column, so the decade
-- comes from start_date; integer "/" already drops the remainder.

-- @B4_global B4 for all countries (reads the whole table)
EXPLAIN ANALYZE
SELECT country,
       (EXTRACT(YEAR FROM start_date)::int / 10) * 10 AS decade,
       physical_factors AS trigger,
       SUM(fatalities) AS total_fatalities,
       COUNT(*) AS events
FROM landslides
WHERE fatalities IS NOT NULL
GROUP BY country, decade, trigger
ORDER BY total_fatalities DESC
LIMIT 20;

-- @B4_indonesia B4 for Indonesia only (can use the country index)
EXPLAIN ANALYZE
SELECT country,
       (EXTRACT(YEAR FROM start_date)::int / 10) * 10 AS decade,
       physical_factors AS trigger,
       SUM(fatalities) AS total_fatalities,
       COUNT(*) AS events
FROM landslides
WHERE fatalities IS NOT NULL AND country = 'Indonesia'
GROUP BY country, decade, trigger
ORDER BY total_fatalities DESC
LIMIT 20;
