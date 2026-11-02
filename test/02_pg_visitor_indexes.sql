-- [PostgreSQL] Indexes for V2–V4 (V1 already uses the primary key).
-- test.sh drops them first, so every run measures "before" and "after" the same way.

-- @drop Remove the visitor indexes (the "before" state)
SET client_min_messages = warning;   -- hide "does not exist, skipping" on the first run
DROP INDEX IF EXISTS landslides_start_date_idx;
DROP INDEX IF EXISTS landslides_country_idx;
DROP INDEX IF EXISTS landslides_geog_idx;
ANALYZE landslides;

-- @create Create the visitor indexes (the "after" state)
-- B-tree (the default): sorted values, good for ranges (V2) and exact matches (V3)
CREATE INDEX landslides_start_date_idx ON landslides (start_date);
CREATE INDEX landslides_country_idx ON landslides (country);
-- GiST on an expression (note the double parentheses): groups points into nested boxes on the map
CREATE INDEX landslides_geog_idx ON landslides USING GIST ((geom::geography));
ANALYZE landslides;
