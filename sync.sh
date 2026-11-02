#!/usr/bin/env bash
# Batch sync PostgreSQL -> ClickHouse: copies rows whose updated_at is newer than the last sync.
# Syncs every INTERVAL seconds, or sooner once MIN_ROWS changed rows are waiting.
#
#   ./sync.sh once                                   # one sync now
#   ./sync.sh                                        # loop with the defaults below (Ctrl+C stops)
#   INTERVAL=60 MIN_ROWS=1 CHECK_EVERY=5 ./sync.sh   # faster settings for a demo
set -euo pipefail
cd "$(dirname "$0")"
source lib/common.sh

INTERVAL=${INTERVAL:-300}      # X: sync at least every 5 minutes (the NFR-4 staleness bound)
MIN_ROWS=${MIN_ROWS:-50}       # Y: ...or as soon as 50 changed rows are waiting
CHECK_EVERY=${CHECK_EVERY:-10} # how often to count waiting rows (cheap: index-only scan)
OVERLAP=${OVERLAP:-300}        # seconds re-read before the last sync, see below

# Watermark = start of the last sync minus an overlap (default OVERLAP seconds).
# Why the overlap: updated_at = now() is the time a transaction STARTED. A slow transaction that
# commits after a sync began can carry an updated_at older than that sync. Re-reading a few
# minutes catches it; copying a row twice is harmless (ReplacingMergeTree keeps one version).
watermark() {
    ch_q -q "SELECT max(started_at) - INTERVAL ${1:-$OVERLAP} SECOND FROM sync_log"
}

# Rows in Postgres changed since a watermark (both stores run in UTC)
pending() {
    pg_val "SELECT COUNT(*) FROM landslides WHERE updated_at > '$1+00'"
}

sync_once() {
    local reason=$1 started wm rows
    started=$(ch_q -q "SELECT now64(6)")
    wm=$(watermark)
    rows=$(pending "$wm")

    # The WHERE is sent to Postgres, which answers it from landslides_updated_at_idx
    ch_q --param_wm="$wm" -q "
        INSERT INTO landslides
        SELECT id, lon, lat, country, toYear(start_date), type, physical_factors,
               fatalities, injuries, updated_at
        FROM postgresql('postgis:5432', 'uglc', 'landslides_clickhouse', 'uglc', 'uglc_dev_pw')
        WHERE updated_at > {wm:DateTime64(6)}"

    # INSERT ... SELECT, not VALUES: clickhouse-client would wait for VALUES rows on stdin
    ch_q --param_s="$started" --param_wm="$wm" --param_n="$rows" --param_r="$reason" -q "
        INSERT INTO sync_log
        SELECT {s:DateTime64(6)}, now64(6), {wm:DateTime64(6)}, {n:UInt64}, {r:String}"

    echo "$(date '+%F %T')  synced ${rows} row(s) changed since ${wm} UTC  (${reason})"
}

if [[ ${1:-} == once ]]; then
    sync_once manual
    exit 0
fi

echo "Sync loop: every ${INTERVAL}s, or when >= ${MIN_ROWS} rows wait (checked every ${CHECK_EVERY}s). Ctrl+C stops."
last=0
while true; do
    now=$(date +%s)
    if (( now - last >= INTERVAL )); then
        sync_once interval
        last=$now
    else
        n=$(pending "$(watermark 0)")   # only rows newer than the last sync, no overlap
        if (( n >= MIN_ROWS )); then
            sync_once "${n} rows waiting"
            last=$now
        fi
    fi
    sleep "$CHECK_EVERY"
done
