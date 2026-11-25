#!/usr/bin/env bash
# One-time setup: downloads the data, starts both databases and loads them.
#
#   ./setup.sh           build everything (safe to rerun: it stops if setup is already done)
#   ./setup.sh --reset   delete all lab data and build again from zero (the CSV is kept)
set -euo pipefail
cd "$(dirname "$0")"
source lib/common.sh

CSV=../data/UGLC_point.csv
CSV_URL="https://zenodo.org/records/18643456/files/UGLC_point.csv?download=1"
CSV_MD5=bb7cbd816944b6398a5e5bcd3a6b4bb5
EXPECTED_ROWS=1060503

require_docker

if [[ ${1:-} == --reset ]]; then
    echo "This deletes ALL lab data in both databases and rebuilds from zero. The CSV is kept."
    read -r -p "Type yes to continue: " answer
    [[ $answer == yes ]] || fail "Cancelled, nothing was deleted."
    docker compose down -v
fi

step "1/5 Data: UGLC_point.csv (Zenodo record 18643456, licence CC BY-NC 4.0)"
if [[ ! -f $CSV ]]; then
    command -v curl >/dev/null 2>&1 || fail "curl is needed to download the data."
    info "Downloading 337 MB from Zenodo..."
    curl -fL --progress-bar -o "$CSV.part" "$CSV_URL" || fail "Download failed. Rerun ./setup.sh to try again."
    mv "$CSV.part" "$CSV"
fi
if command -v md5sum >/dev/null 2>&1; then
    [[ $(md5sum "$CSV" | cut -d' ' -f1) == "$CSV_MD5" ]] ||
        fail "$CSV is damaged or a different version (checksum mismatch). Delete it and rerun ./setup.sh."
    info "OK, checksum verified"
else
    info "md5sum not found, skipping the checksum check"
fi

step "2/5 Starting containers (the first time this also downloads the images)"
start_stack
info "OK: $PG_CONTAINER on port 5433, $CH_CONTAINER on ports 8124 / 9001"

if setup_done; then
    echo
    echo "Setup was already done. Run ./test.sh, or ./setup.sh --reset to start over."
    exit 0
fi
if [[ $(pg_val "SELECT to_regclass('raw_points') IS NOT NULL") == t ]]; then
    fail "A previous setup didn't finish. Run ./setup.sh --reset to start over."
fi

step "3/5 PostgreSQL: load, clean, prepare for the sync (about 1-2 minutes)"
SECONDS=0
pg -q < setup/01_pg_raw_load.sql
raw=$(pg_val "SELECT COUNT(*) FROM raw_points")
[[ $raw == "$EXPECTED_ROWS" ]] || fail "raw_points has $raw rows, expected $EXPECTED_ROWS."
info "raw_points: $raw rows (staging, everything as text)"
pg -q < setup/02_pg_clean_load.sql >/dev/null
info "landslides: $(pg_val "SELECT COUNT(*) FROM landslides") rows (cleaned)"
pg -q < setup/03_pg_sync_support.sql
info "view landslides_clickhouse + index on updated_at  (${SECONDS}s)"

step "4/5 ClickHouse: create tables and copy everything from PostgreSQL"
SECONDS=0
ch --multiquery < setup/04_ch_tables.sql
ch --multiquery < setup/05_ch_initial_load.sql
info "landslides: $(ch_q -q "SELECT count() FROM landslides") rows  (${SECONDS}s)"

step "5/5 Checking that both stores hold the same data"
pg_check=$(pg_val "SELECT COUNT(*) || ' rows, ' || SUM(fatalities) || ' fatalities' FROM landslides")
ch_check=$(ch_q -q "SELECT toString(count()) || ' rows, ' || toString(sum(fatalities)) || ' fatalities' FROM landslides FINAL")
info "PostgreSQL: $pg_check"
info "ClickHouse: $ch_check"
[[ $pg_check == "$ch_check" ]] || fail "The two stores don't match."

echo
echo "Setup complete. Next: ./test.sh"
