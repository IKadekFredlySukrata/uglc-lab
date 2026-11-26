#!/usr/bin/env bash
# Runs every test against the lab and writes the results to ../results/<date-time>/.
# Needs ./setup.sh to have run once. Takes a few minutes.
#
#   ./test.sh
#
# Results:  results/<date-time>/summary.md   the numbers, with NFR pass/fail
#           results/<date-time>/*.txt        full query plans and query results
#
# Every run adds one TEST report (as history) to both stores; see test/05_pg_c1_submit.sql.
set -euo pipefail
cd "$(dirname "$0")"
source lib/common.sh

require_docker
start_stack
setup_done || fail "The lab isn't set up yet. Run ./setup.sh first."

RUN=$(date +%Y%m%d-%H%M%S)
OUT=../results/$RUN
mkdir -p "$OUT"
SUMMARY=$OUT/summary.md
TIMEFILE=$OUT/.time
START=$SECONDS

# ---------- helpers ----------

# "✅" if a value (ms) is below a limit (ms), else "❌"
verdict() { awk -v v="$1" -v lim="$2" 'BEGIN { print (v != "" && v + 0 < lim) ? "✅" : "❌" }'; }
# 0.12 ms / 5 ms / 97 ms / 1.25 s (whole numbers stay whole: ClickHouse measures in whole ms)
fmt_ms() { awk -v v="$1" 'BEGIN { if (v == "") print "?"; else if (v < 10 && v != int(v)) printf "%.2f ms", v; else if (v < 1000) printf "%.0f ms", v; else printf "%.2f s", v / 1000 }'; }
# How many times faster b is than a (before -> after)
ratio() { awk -v a="$1" -v b="$2" 'BEGIN { if (a != "" && b > 0) printf "%.0f×", a / b; else print "?" }'; }
# Which store won, and by how much
winner() { awk -v p="$1" -v c="$2" 'BEGIN { if (p == "" || c == "" || p <= 0 || c <= 0) print "?"; else if (c < p) printf "ClickHouse, %.1f×", p / c; else printf "PostgreSQL, %.1f×", c / p }'; }

# Run one PostgreSQL EXPLAIN ANALYZE section twice (warm-up, then measured) and append the
# measured plan to a log. Prints "<execution ms>|<scan used>".
pg_section() {
    local file=$1 name=$2 log=$3 sql out ms plan
    sql=$(section_sql "$file" "$name")
    pg <<<"$sql" >/dev/null
    out=$(pg <<<"$sql")
    printf '===== %s: %s =====\n%s\n\n' "$name" "$(section_title "$file" "$name")" "$out" >> "$log"
    ms=$(grep -oE 'Execution Time: [0-9.]+' <<<"$out" | grep -oE '[0-9.]+$' | tail -1 || true)
    plan=$(grep -m1 -oE '(Index Only Scan|Index Scan|Bitmap Index Scan|Parallel Seq Scan|Seq Scan) (using|on) [a-z_]+' <<<"$out" || true)
    echo "${ms}|${plan:-?}"
}

# Run one ClickHouse section twice (warm-up, then measured) and append the result to a log.
# Prints the measured time in ms (clickhouse-client --time, printed on stderr).
ch_section() {
    local file=$1 name=$2 log=$3 sql out sec
    sql=$(section_sql "$file" "$name")
    ch --multiquery <<<"$sql" >/dev/null
    out=$(ch --multiquery --time --format PrettyCompactNoEscapes <<<"$sql" 2>"$TIMEFILE")
    sec=$(tail -1 "$TIMEFILE")
    printf '===== %s: %s =====\n%s\nTime: %s s\n\n' "$name" "$(section_title "$file" "$name")" "$out" "$sec" >> "$log"
    awk -v s="$sec" 'BEGIN { printf "%.0f", s * 1000 }'
}

# ---------- summary header ----------

docker_cpus=$(docker info --format '{{.NCPU}}')
docker_mem=$(docker info --format '{{.MemTotal}}' | awk '{ printf "%.1f GB", $1 / 1024 / 1024 / 1024 }')
{
    echo "# UGLC lab test run $RUN"
    echo
    echo "- Machine: $(uname -s) $(uname -m); Docker sees $docker_cpus CPUs and $docker_mem RAM"
    echo "- Rows at the start: PostgreSQL $(pg_val "SELECT COUNT(*) FROM landslides"), ClickHouse $(ch_q -q "SELECT count() FROM landslides FINAL")"
    echo "- Every query runs twice and the second (warm) run is reported."
    echo "  Full plans and results are in the .txt files next to this summary."
} > "$SUMMARY"

# ---------- 1. Visitor queries ----------

step "1/5 Visitor queries V1–V4 on PostgreSQL, before and after the indexes (NFR-1: < 1 s)"
LOG=$OUT/1_visitor_queries.txt
V_FILE=test/01_pg_visitor_queries.sql
IDX_FILE=test/02_pg_visitor_indexes.sql

pg -q <<<"$(section_sql "$IDX_FILE" drop)"
echo "########## BEFORE the visitor indexes ##########" >> "$LOG"
names=() before=() after=()
for v in $(sections "$V_FILE"); do
    names+=("$v")
    before+=("$(pg_section "$V_FILE" "$v" "$LOG")")
    info "before  $v  $(fmt_ms "${before[-1]%%|*}")  ${before[-1]#*|}"
done

SECONDS_BEFORE_IDX=$SECONDS
pg -q <<<"$(section_sql "$IDX_FILE" create)"
idx_time=$(( SECONDS - SECONDS_BEFORE_IDX ))
info "indexes created in ${idx_time}s"

echo "########## AFTER the visitor indexes ##########" >> "$LOG"
for v in "${names[@]}"; do
    after+=("$(pg_section "$V_FILE" "$v" "$LOG")")
    info "after   $v  $(fmt_ms "${after[-1]%%|*}")  ${after[-1]#*|}"
done

{
    echo
    echo "## 1. Visitor queries on PostgreSQL (NFR-1: < 1 s)"
    echo
    echo "| Query | Before indexes | Plan | After indexes | Plan | Speed-up | NFR-1 |"
    echo "|---|---|---|---|---|---|---|"
    for i in "${!names[@]}"; do
        b=${before[$i]%%|*} a=${after[$i]%%|*}
        echo "| ${names[$i]} $(section_title "$V_FILE" "${names[$i]}") | $(fmt_ms "$b") | ${before[$i]#*|} | $(fmt_ms "$a") | ${after[$i]#*|} | $(ratio "$b" "$a") | $(verdict "$a" 1000) |"
    done
    echo
    echo "Creating the 3 visitor indexes took ${idx_time} s."
} >> "$SUMMARY"

# ---------- 2. Dashboard queries ----------

step "2/5 Dashboard queries B1–B5 on ClickHouse (NFR-2: < 5 s)"
LOG=$OUT/2_dashboard_queries.txt
B_FILE=test/03_ch_dashboard_queries.sql
parts=$(ch_q -q "SELECT count() FROM system.parts WHERE database = 'uglc' AND table = 'landslides' AND active")
info "ClickHouse table has $parts active part(s) right now"
{
    echo
    echo "## 2. Dashboard queries on ClickHouse (NFR-2: < 5 s)"
    echo
    echo "The table had **$parts active part(s)** during these queries. Every sync writes a small new part,"
    echo "and FINAL deduplicates across parts while the query runs, so more parts means slower queries"
    echo "(measured: 1 part about 5 ms, 3 parts about 30 ms for a full count). Background merges bring it"
    echo "back to 1 part, so times vary between runs. That also affects section 3."
    echo
    echo "| Query | Time | NFR-2 |"
    echo "|---|---|---|"
} >> "$SUMMARY"
for b in $(sections "$B_FILE"); do
    ms=$(ch_section "$B_FILE" "$b" "$LOG")
    info "$b  $(fmt_ms "$ms")"
    echo "| $b $(section_title "$B_FILE" "$b") | $(fmt_ms "$ms") | $(verdict "$ms" 5000) |" >> "$SUMMARY"
done

# ---------- 3. B4 on both stores ----------

step "3/5 B4 on PostgreSQL vs ClickHouse (NFR-5)"
LOG=$OUT/3_b4_comparison.txt
{
    echo
    echo "## 3. B4 on PostgreSQL vs ClickHouse (NFR-5: dashboard load stays off the portal)"
    echo
    echo "| Scope | PostgreSQL | Plan | ClickHouse | Faster |"
    echo "|---|---|---|---|---|"
} >> "$SUMMARY"
for scope in $(sections test/04_pg_b4_comparison.sql); do
    echo "########## PostgreSQL ##########" >> "$LOG"
    p=$(pg_section test/04_pg_b4_comparison.sql "$scope" "$LOG")
    echo "########## ClickHouse ##########" >> "$LOG"
    c=$(ch_section test/04_ch_b4_comparison.sql "$scope" "$LOG")
    info "$scope  PostgreSQL $(fmt_ms "${p%%|*}")  ClickHouse $(fmt_ms "$c")"
    echo "| $(section_title test/04_pg_b4_comparison.sql "$scope") | $(fmt_ms "${p%%|*}") | ${p#*|} | $(fmt_ms "$c") | $(winner "${p%%|*}" "$c") |" >> "$SUMMARY"
done
{
    echo
    echo "PostgreSQL time = server execution time (EXPLAIN ANALYZE); ClickHouse time = clickhouse-client --time."
    echo "The global query is the heavy dashboard case: on PostgreSQL it reads the whole portal table."
    echo "For one country PostgreSQL can win: it has a country index, while ClickHouse's table is sorted"
    echo "by id (so edits replace correctly) and can't skip to one country's rows. Both are far below 1 s."
} >> "$SUMMARY"

# ---------- 4. Contributors and sync ----------

step "4/5 Contributors (C1, C2) and the sync to ClickHouse (NFR-3, NFR-4)"
LOG=$OUT/4_contributors_sync.txt

c1_out=$(pg -v run_tag="$RUN" < test/05_pg_c1_submit.sql)
printf '##### C1 #####\n%s\n\n' "$c1_out" >> "$LOG"
id=$(grep -oE 'C1_ID=[0-9]+' <<<"$c1_out" | cut -d= -f2 || true)
[[ -n $id ]] || fail "C1 didn't return a report id. See $LOG"
visible=$(pg_val "SELECT COUNT(*) FROM landslides WHERE id = $id")   # a separate connection
info "C1: report $id committed, visible from another connection: $visible"

./sync.sh once >> "$LOG"
ch_after_c1=$(ch_q -q "SELECT fatalities FROM landslides FINAL WHERE id = $id")
info "sync: report $id in ClickHouse with fatalities = ${ch_after_c1:-missing}"

c2_out=$(pg -v c1_id="$id" < test/06_pg_c2_update.sql)
printf '##### C2 #####\n%s\n\n' "$c2_out" >> "$LOG"
owner=$(grep -A1 '^OWNER$' <<<"$c2_out" | tail -1)
other=$(grep -A1 '^OTHER$' <<<"$c2_out" | tail -1)
info "C2: owner -> $owner, other contributor -> $other"

./sync.sh once >> "$LOG"
versions=$(ch_q -q "SELECT count() FROM landslides WHERE id = $id")
ch_after_c2=$(ch_q -q "SELECT fatalities FROM landslides FINAL WHERE id = $id")
info "sync: $versions version(s) stored, FINAL shows fatalities = $ch_after_c2"

# Lag: run the sync loop with demo settings, touch the report, time until ClickHouse shows it
echo "##### Lag test: sync loop with CHECK_EVERY=1 MIN_ROWS=1 #####" >> "$LOG"
CHECK_EVERY=1 MIN_ROWS=1 INTERVAL=3600 ./sync.sh >> "$LOG" 2>&1 &
loop_pid=$!
trap 'kill "$loop_pid" 2>/dev/null || true' EXIT
sleep 3   # let the loop finish its first sync
lags=()
for run in 1 2 3; do
    ts=$(pg_val "UPDATE landslides SET updated_at = now() WHERE id = $id
                 RETURNING to_char(updated_at AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS.US')" | head -1)
    lag=""
    for _ in $(seq 1 60); do
        lag=$(ch_q -q "SELECT dateDiff('millisecond', toDateTime64('$ts', 6, 'UTC'), now64(6))
                       FROM landslides WHERE id = $id AND updated_at = toDateTime64('$ts', 6, 'UTC') LIMIT 1")
        [[ -n $lag ]] && break
        sleep 0.5
    done
    lags+=("$lag")
    info "lag run $run: commit -> visible in ClickHouse after $(fmt_ms "$lag")"
    sleep 2
done
kill "$loop_pid" 2>/dev/null || true
wait "$loop_pid" 2>/dev/null || true
trap - EXIT

./sync.sh once >> "$LOG"
pg_check=$(pg_val "SELECT COUNT(*) || ' rows, ' || SUM(fatalities) || ' fatalities' FROM landslides")
ch_check=$(ch_q -q "SELECT toString(count()) || ' rows, ' || toString(sum(fatalities)) || ' fatalities' FROM landslides FINAL")
info "PostgreSQL: $pg_check | ClickHouse: $ch_check"

yes_no() { [[ $1 == "$2" ]] && echo "✅" || echo "❌"; }
lag_text=""
for l in "${lags[@]}"; do lag_text+="$(fmt_ms "$l"), "; done
lag_ok="✅"
for l in "${lags[@]}"; do [[ $(verdict "$l" 300000) == "✅" ]] || lag_ok="❌"; done
{
    echo
    echo "## 4. Contributors and the sync (NFR-3, NFR-4)"
    echo
    echo "| Check | Result | |"
    echo "|---|---|---|"
    echo "| C1: report $id committed, visible from another connection right away (NFR-3) | $visible row | $(yes_no "$visible" 1) |"
    echo "| Sync: the new report reaches ClickHouse | fatalities = ${ch_after_c1:-missing} | $(yes_no "$ch_after_c1" 3) |"
    echo "| C2: contributor A edits own report | $owner | $(yes_no "$owner" "UPDATE 1") |"
    echo "| C2: contributor B edits A's report | $other | $(yes_no "$other" "UPDATE 0") |"
    echo "| Sync: edit replaces the old version (FINAL) | $versions version(s) stored, FINAL shows fatalities = $ch_after_c2 | $(yes_no "$ch_after_c2" 4) |"
    echo "| Commit → visible on the dashboard, 3 runs (NFR-4) | ${lag_text%, } | $lag_ok |"
    echo "| Both stores hold the same data | PostgreSQL: $pg_check / ClickHouse: $ch_check | $(yes_no "$pg_check" "$ch_check") |"
    echo
    echo "Lag measured with demo settings (check every 1 s, sync at 1 waiting row). With the defaults in"
    echo "sync.sh the dashboard lags at most INTERVAL = 5 minutes, which is the NFR-4 bound used above."
    echo "Versions > 1 is expected: ClickHouse merges them in the background; FINAL hides them now."
} >> "$SUMMARY"

# ---------- 5. Indonesia profile and clean-table conformance ----------

step "5/5 Profil tanah longsor Indonesia dan konformasi tabel clean"
LOG=$OUT/5_indonesia_profile.txt
I_FILE=analysis/indonesia_summary.sql

# Run every section once and keep the raw output for inspection.
{
    echo "===== Profil tanah longsor Indonesia (tanpa baris uji TEST %) ====="
    for s in $(sections "$I_FILE"); do
        printf '\n--- %s ---\n' "$s"
        pg -At -F'|' <<<"$(section_sql "$I_FILE" "$s")"
    done
} > "$LOG"

overview=$(pg -At -F'|' <<<"$(section_sql "$I_FILE" overview)")
IFS='|' read -r in_events in_known in_fatalities in_unknown_pct in_injuries in_max_fatalities <<<"$overview"

checks=$(pg -At -F'|' <<<"$(section_sql "$I_FILE" checks)")
IFS='|' read -r ch_cols ch_pk ch_fk ch_check ch_notnull ch_geom ch_srid \
    ch_sentinel ch_dates ch_dup ch_srid_bad ch_notpoint ch_id_geom <<<"$checks"

completeness=$(pg -At -F'|' <<<"$(section_sql "$I_FILE" completeness)")
IFS='|' read -r co_rows co_fat_pct co_type_null co_trig_null co_acc_zero \
    co_geom_null co_notes_null co_link_null <<<"$completeness"

duplicates=$(pg -At -F'|' <<<"$(section_sql "$I_FILE" duplicates)")
IFS='|' read -r dup_pairs dup_rows <<<"$duplicates"

known_pct=$(awk -v u="$in_unknown_pct" 'BEGIN { printf "%.1f", 100 - u }')
same() { [[ $1 == "$2" ]] && echo "✅" || echo "❌"; }
zero() { [[ $1 == 0 ]] && echo "✅" || echo "❌"; }

info "Indonesia: $in_events kejadian, $in_fatalities korban dari $in_known kejadian yang diketahui"
info "Konformasi: $ch_cols kolom, PK=$ch_pk FK=$ch_fk CHECK=$ch_check NOT NULL=$ch_notnull, geom=$ch_geom/$ch_srid"

{
    echo
    echo "## 5. Profil tanah longsor Indonesia dan konformasi tabel clean"
    echo
    echo "Baris uji C1 (\`notes LIKE 'TEST %'\`) dikecualikan; jumlah baris Indonesia yang dianalisis: **$in_events**."
    echo
    echo "### 5.1 Konformasi dengan \`CREATE TABLE landslides\`"
    echo
    echo "| Pemeriksaan | Nilai | Status |"
    echo "|---|---:|---|"
    echo "| Jumlah kolom | $ch_cols / 20 | $(same "$ch_cols" 20) |"
    echo "| Primary key | $ch_pk / 1 | $(same "$ch_pk" 1) |"
    echo "| Foreign key (\`submitted_by\`) | $ch_fk / 1 | $(same "$ch_fk" 1) |"
    echo "| CHECK (\`end_date >= start_date\`) | $ch_check / 1 | $(same "$ch_check" 1) |"
    echo "| Kolom NOT NULL | $ch_notnull / 6 | $(same "$ch_notnull" 6) |"
    echo "| Tipe geometri | $ch_geom | $(same "$ch_geom" Point) |"
    echo "| SRID | $ch_srid | $(same "$ch_srid" 4326) |"
    echo "| Baris dengan sentinel (\`ND\`, \`-99999\`) | $ch_sentinel | $(zero "$ch_sentinel") |"
    echo "| \`end_date < start_date\` | $ch_dates | $(zero "$ch_dates") |"
    echo "| \`id\` duplikat | $ch_dup | $(zero "$ch_dup") |"
    echo "| SRID selain 4326 | $ch_srid_bad | $(zero "$ch_srid_bad") |"
    echo "| Geometri selain POINT | $ch_notpoint | $(zero "$ch_notpoint") |"
    echo "| \`geom\` NULL untuk Indonesia | $ch_id_geom | $(zero "$ch_id_geom") |"
    echo
    echo "### 5.2 Gambaran umum"
    echo
    echo "| Indikator | Nilai |"
    echo "|---|---:|"
    echo "| Kejadian Indonesia (UGLC) | $in_events |"
    echo "| Kejadian dengan korban diketahui | $in_known ($known_pct%) |"
    echo "| Kejadian tanpa angka korban | $((in_events - in_known)) ($in_unknown_pct%) |"
    echo "| Total korban diketahui | $in_fatalities |"
    echo "| Korban terbanyak dalam satu kejadian | $in_max_fatalities |"
    echo "| Total luka-luka | $in_injuries |"
    echo
    echo "**Total korban adalah batas bawah**, karena $in_unknown_pct% baris tidak punya angka korban."
    echo
    echo "### 5.3 Sumber data"
    echo
    echo "| Sumber | Kejadian | Korban diketahui | Total korban |"
    echo "|---|---:|---:|---:|"
    while IFS='|' read -r src ev kn tot; do
        printf '| %s | %s | %s | %s |\n' "$src" "$ev" "$kn" "$tot"
    done < <(pg -At -F'|' <<<"$(section_sql "$I_FILE" sources)")
    echo
    echo "### 5.4 Trigger (\`physical_factors\`)"
    echo
    echo "| Trigger | Kejadian | Korban diketahui | Total korban |"
    echo "|---|---:|---:|---:|"
    while IFS='|' read -r trg ev kn tot; do
        printf '| %s | %s | %s | %s |\n' "$trg" "$ev" "$kn" "$tot"
    done < <(pg -At -F'|' <<<"$(section_sql "$I_FILE" triggers)")
    echo
    echo "### 5.5 Tipe longsor"
    echo
    echo "| Tipe | Kejadian | Korban diketahui | Total korban |"
    echo "|---|---:|---:|---:|"
    while IFS='|' read -r typ ev kn tot; do
        printf '| %s | %s | %s | %s |\n' "$typ" "$ev" "$kn" "$tot"
    done < <(pg -At -F'|' <<<"$(section_sql "$I_FILE" types)")
    echo
    echo "### 5.6 Kejadian paling mematikan (duplikat lintas sumber disembunyikan)"
    echo
    echo "| Tanggal | Tipe | Trigger | Korban | Luka |"
    echo "|---|---|---|---:|---:|"
    while IFS='|' read -r d typ trg fat inj; do
        printf '| %s | %s | %s | %s | %s |\n' "$d" "$typ" "$trg" "$fat" "$inj"
    done < <(pg -At -F'|' <<<"$(section_sql "$I_FILE" top)")
    echo
    echo "### 5.7 Kelengkapan dan duplikasi"
    echo
    echo "| Pemeriksaan | Nilai |"
    echo "|---|---:|"
    echo "| Baris dianalisis | $co_rows |"
    echo "| \`fatalities\` diketahui | $co_fat_pct% |"
    echo "| \`type\` NULL | $co_type_null |"
    echo "| \`physical_factors\` NULL | $co_trig_null |"
    echo "| \`accuracy_m = 0\` (kemungkinan tidak diketahui) | $co_acc_zero |"
    echo "| \`geom\` NULL | $co_geom_null |"
    echo "| \`notes\` NULL | $co_notes_null |"
    echo "| \`link\` NULL | $co_link_null |"
    echo "| Pasangan duplikat lintas sumber (tanggal + korban sama, <= 5 km) | $dup_pairs pasangan / $dup_rows baris |"
    echo
    echo "Angka di atas adalah **profil dataset UGLC**, bukan statistik resmi BNPB. Dataset ini"
    echo "menggabungkan tiga katalog dengan cakupan berbeda, dan satu inventaris gempa Palu 2018"
    echo "mendominasi jumlah baris tanpa mencatat korban. Query lengkap:"
    echo "\`postgresql-clickhouse/analysis/indonesia_summary.sql\`."
} >> "$SUMMARY"

rm -f "$TIMEFILE"
echo
echo "Done in $(( SECONDS - START ))s. Results: $OUT/"
echo
cat "$SUMMARY"
