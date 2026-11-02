-- [PostgreSQL] 1. Load UGLC_point.csv as-is into a staging table (everything is text).
-- A single bad value can't abort the 1M-row load; cleaning happens in the next step, in SQL.
-- COPY matches columns BY POSITION, so this order must follow the CSV header:
--   WKT_GEOM | NEW DATASET | ID | OLD DATASET | OLD ID | VERSION | COUNTRY | ACCURACY |
--   START DATE | END DATE | TYPE | PHYSICAL FACTORS | RELIABILITY | RECORD TYPE |
--   FATALITIES | INJURIES | NOTES | LINK

CREATE TABLE raw_points (
    wkt_geom          text,
    new_dataset       text,
    id                text,
    old_dataset       text,
    old_id            text,
    version           text,
    country           text,
    accuracy          text,
    start_date        text,
    end_date          text,
    type              text,
    physical_factors  text,
    reliability       text,
    record_type       text,
    fatality          text,
    injuries          text,
    notes             text,
    link              text
);

-- /data is the ./data folder mounted inside the container. Separator is "|".
\copy raw_points FROM '/data/UGLC_point.csv' WITH (FORMAT csv, DELIMITER '|', HEADER true)
