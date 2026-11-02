-- [ClickHouse] 4. The dashboard table and the sync log.

-- ReplacingMergeTree(updated_at): among rows with the same ORDER BY key, keep the one with the
-- highest updated_at. So a synced C2 edit replaces the old version instead of being counted twice.
-- ORDER BY id (not country, start_year): an edit that changes country or date keeps the same
-- key, so the old version is still replaced.
-- Replacement happens during background merges: dashboard queries use FINAL to get it right now.
CREATE TABLE landslides
(
    id                  Int64,
    lon                 Nullable(Float64),                  -- 9 rows have no location
    lat                 Nullable(Float64),
    country             LowCardinality(Nullable(String)),   -- LowCardinality: few distinct values
    start_year          Int16,                              -- year only: UGLC dates go back to 1664
    type                LowCardinality(Nullable(String)),
    physical_factors    LowCardinality(Nullable(String)),
    fatalities          Nullable(Int32),
    injuries            Nullable(Int32),
    updated_at          DateTime64(6, 'UTC')
)
ENGINE = ReplacingMergeTree(updated_at)
ORDER BY id;

-- One row per sync. The next sync copies rows changed since max(started_at) (minus an overlap).
CREATE TABLE sync_log
(
    started_at   DateTime64(6, 'UTC'),
    finished_at  DateTime64(6, 'UTC'),
    watermark    DateTime64(6, 'UTC'),   -- rows with updated_at > watermark were copied
    rows_copied  UInt64,
    reason       String                  -- 'initial load', 'manual', 'interval', 'N rows waiting'
)
ENGINE = MergeTree
ORDER BY started_at;
