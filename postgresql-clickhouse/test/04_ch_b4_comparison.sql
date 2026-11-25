-- [ClickHouse] B4 on the dashboard store, to compare with 04_pg_b4_comparison.sql (NFR-5).
-- ClickHouse stores data column by column, so it reads only the 4 columns this query uses.

-- @B4_global B4 for all countries
SELECT country,
       intDiv(start_year, 10) * 10 AS decade,
       physical_factors AS trigger,
       sum(fatalities) AS total_fatalities,
       count() AS events
FROM landslides FINAL
WHERE fatalities IS NOT NULL
GROUP BY country, decade, trigger
ORDER BY total_fatalities DESC
LIMIT 20;

-- @B4_indonesia B4 for Indonesia only
SELECT country,
       intDiv(start_year, 10) * 10 AS decade,
       physical_factors AS trigger,
       sum(fatalities) AS total_fatalities,
       count() AS events
FROM landslides FINAL
WHERE fatalities IS NOT NULL AND country = 'Indonesia'
GROUP BY country, decade, trigger
ORDER BY total_fatalities DESC
LIMIT 20;
