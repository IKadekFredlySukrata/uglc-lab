-- [ClickHouse] BNPB dashboard queries B1–B5 (NFR-2: < 5 s).
-- FINAL: landslides is a ReplacingMergeTree, and until a background merge runs, an edited report
-- exists in several versions. FINAL returns only the newest one, so nothing is counted twice.
-- B2, B4 and B5 focus on Indonesia; B1 and B3 are global.

-- @B1 Share of landslides per type (NULL = type unknown)
SELECT type,
       count() AS count,
       round(100 * count / sum(count) OVER (), 2) AS pct
FROM landslides FINAL
GROUP BY type
ORDER BY count DESC;

-- @B2 Deadliest type in Indonesia (average deaths per event where deaths are known)
SELECT type,
       count() AS type_count,
       count(fatalities) AS known_fatalities_count,
       round(avg(fatalities), 2) AS fatalities_per_landslide    -- avg() skips NULLs
FROM landslides FINAL
WHERE type IS NOT NULL AND country = 'Indonesia'
GROUP BY type
ORDER BY fatalities_per_landslide DESC
LIMIT 20;

-- @B3.1 Countries with the most landslides
SELECT country,
       count() AS events
FROM landslides FINAL
WHERE country IS NOT NULL
GROUP BY country
ORDER BY events DESC
LIMIT 20;

-- @B3.2 Areas with the most landslides (1x1 degree grid cells, about 100 km)
SELECT floor(lat) AS lat_cell,                  -- floor(): a cell is [lat, lat+1) x [lon, lon+1)
       floor(lon) AS lon_cell,
       count() AS events,
       topK(1)(country)[1] AS main_country      -- most common country in the cell
FROM landslides FINAL
WHERE lat IS NOT NULL
GROUP BY lat_cell, lon_cell
ORDER BY events DESC
LIMIT 20;

-- @B4 Total fatalities per decade, by trigger (Indonesia)
SELECT country,
       intDiv(start_year, 10) * 10 AS decade,   -- 1987 -> 1980
       physical_factors AS trigger,
       sum(fatalities) AS total_fatalities,
       count() AS events
FROM landslides FINAL
WHERE fatalities IS NOT NULL AND country = 'Indonesia'
GROUP BY country, decade, trigger
ORDER BY total_fatalities DESC
LIMIT 20;

-- @B5 Landslides and fatalities per year (Indonesia, after 2010)
SELECT start_year,
       sum(fatalities) AS fatalities_total,
       count() AS event_count
FROM landslides FINAL
WHERE country = 'Indonesia' AND start_year > 2010
GROUP BY start_year
ORDER BY start_year DESC
LIMIT 20;
