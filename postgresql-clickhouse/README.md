# UGLC Storage Lab

A runnable version of a two-store big data architecture for the
[Unified Global Landslide Catalogue (UGLC)](https://zenodo.org/records/18643456): about 1.06 million
landslide events.

| Store | Role | Answers |
|---|---|---|
| **PostgreSQL 18 + PostGIS 3.6** | Operational store, the source of truth | Visitor portal V1–V4, contributors C1–C2 |
| **ClickHouse 26.8** | Analytical copy, read-only | BNPB dashboard B1–B5 |

A batch sync copies new and edited reports from PostgreSQL to ClickHouse.

Two commands do everything: `./setup.sh` once, then `./test.sh` as often as you like.

## Requirements

- **Docker** with Compose v2: Docker Desktop on Windows and macOS, Docker Engine on Linux
- About **8 GB RAM** for Docker and **5 GB free disk**
- Internet for the first setup (container images plus the 337 MB dataset)
- **Windows:** run the commands in **Git Bash** (installed with [Git for Windows](https://git-scm.com/download/win)),
  not in PowerShell or cmd. Docker Desktop must be running.

## Quick start

```bash
git clone <this repo> uglc-lab
cd uglc-lab/postgresql-clickhouse
./setup.sh      # one time, about 5 minutes: download, start, load, check
./test.sh       # every test; prints a summary and saves it in ../results/
```

## What `./setup.sh` does

1. Downloads `UGLC_point.csv` from Zenodo into `../data/` (skipped if it's already there) and checks its MD5.
2. Starts the two containers. On ARM machines (such as Apple Silicon), it picks a PostGIS image that runs there.
3. **PostgreSQL** (`setup/01–03`): loads the CSV into a text-only staging table, cleans it into
   `landslides`, then creates the view ClickHouse reads and an index for the sync.
4. **ClickHouse** (`setup/04–05`): creates the tables and copies all rows from PostgreSQL.
5. Checks that both stores have the same row count and total fatalities.

You can run it again safely: it stops when the setup is already done. `./setup.sh --reset` deletes
the lab data (asking first) and builds everything again. The CSV is kept.

### Cleaning decisions (in `setup/02_pg_clean_load.sql`)

- Values that mean "unknown" (`'ND'`, `-99999`, `'Source: ND'`, …) become real `NULL`s.
- 109 rows have `end_date` before `start_date` (102 USGS, 7 PCLD). The two dates are swapped and the rows are kept.
- 9 USGS rows have `POINT (-Infinity -Infinity)`. Their location becomes `NULL` and the rows are kept.

## What `./test.sh` does

| Part | Store | What it measures | Target |
|---|---|---|---|
| 1 | PostgreSQL | V1–V4 **without** and **with** indexes (it drops the indexes first, so every run measures the same thing) | NFR-1 < 1 s |
| 2 | ClickHouse | B1–B5 | NFR-2 < 5 s |
| 3 | both | B4 on PostgreSQL vs ClickHouse | NFR-5 |
| 4 | both | C1 submit, C2 edit own report (`UPDATE 1`) and someone else's (`UPDATE 0`), sync, and the time from a commit until the dashboard shows it | NFR-3, NFR-4 |

Every query runs twice, and the second (warm) run is reported. Output goes to `../results/<date-time>/`:

- `summary.md`: all the numbers, with ✅/❌ per target
- `1_visitor_queries.txt` … `4_contributors_sync.txt`: full query plans and results

Each run **adds one test report** (its notes start with `TEST`) to both stores and keeps it, as
history. So the dashboard numbers grow very slightly between runs. To list the test reports:

```sql
SELECT id, notes, fatalities, updated_at FROM landslides WHERE notes LIKE 'TEST %';
```

## The sync

```bash
./sync.sh once                                   # one sync now
./sync.sh                                        # loop: every 5 min, or as soon as 50 rows changed
INTERVAL=60 MIN_ROWS=1 CHECK_EVERY=5 ./sync.sh   # faster settings for a demo
```

- It copies rows whose `updated_at` is newer than the last sync (the *watermark* in ClickHouse table
  `sync_log`), with a 5-minute overlap for transactions that commit late.
- ClickHouse's `landslides` table is a `ReplacingMergeTree(updated_at)`: an edited report replaces
  its old version. That happens during background merges, so **dashboard queries use `FINAL`**.
- It doesn't handle deletes: a report deleted in PostgreSQL stays in ClickHouse.

## Connecting by hand

| | Command | From other tools |
|---|---|---|
| PostgreSQL | `docker exec -it uglc-lab-postgis psql -U uglc -d uglc` | `localhost:5433` |
| ClickHouse | `docker exec -it uglc-lab-clickhouse clickhouse-client -u uglc --password uglc_dev_pw -d uglc` | HTTP `localhost:8124`, native `localhost:9001` |

User `uglc`, password `uglc_dev_pw`, database `uglc`. These are local lab passwords only.
In Git Bash, put `winpty` in front of `docker exec -it ...`.

Stop the lab with `docker compose stop` and start it again with `docker compose start` from `uglc-lab/postgresql-clickhouse`. The data is kept.

## Layout

```
setup.sh  test.sh  sync.sh     the three commands
lib/common.sh                  shared settings and helpers
setup/NN_<pg|ch>_*.sql         setup steps, in order; pg = PostgreSQL, ch = ClickHouse
test/NN_<pg|ch>_*.sql          test queries; "-- @NAME" lines split a file into timed sections
../data/                       UGLC_point.csv (downloaded, not in git)
../results/                    test output (not in git)
```

## Troubleshooting

- **Port already in use:** change the left-hand port in `docker-compose.yml` (5433, 8124, 9001).
- **`$'\r': command not found` on Windows:** the scripts got Windows line endings. Run
  `git config core.autocrlf false`, then clone again. (`.gitattributes` should prevent this.)
- **Download fails or the checksum doesn't match:** delete `../data/UGLC_point.csv` and run `./setup.sh` again.
- **Anything else:** `docker compose logs postgis` or `docker compose logs clickhouse`.

## Data licence

UGLC is published on Zenodo (record 18643456) under **CC BY-NC 4.0**. It isn't included in this
repository; `setup.sh` downloads it from the source.
