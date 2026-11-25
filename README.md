# UGLC Storage Lab

Two ways to store and query the [Unified Global Landslide Catalogue (UGLC)](https://zenodo.org/records/18643456),
about 1.06 million landslide events, built so they can be compared on the same data and the same questions.
Made for a Big Data course group project.

| Folder | What it is | Storage | Query engine |
|---|---|---|---|
| [`postgresql-clickhouse/`](postgresql-clickhouse/) | **The main design.** An operational store for the public portal and contributors, plus an analytical copy for the BNPB dashboard, kept in step by a batch sync. | PostgreSQL 18 + PostGIS 3.6, synced to ClickHouse 26.8 | the two databases |
| [`hdfs-parquet/`](hdfs-parquet/) | **A baseline.** The same cleaned data as Parquet files on HDFS: one copy, no indexes, no updates. | HDFS 3.4 (1 namenode, 1 datanode), Parquet + snappy | Spark SQL 3.5, local mode |

Each part runs on its own (separate Docker Compose project, containers and ports) and has its own
README with the details. They share two folders: `data/` for the CSV, downloaded once, and `results/`
for test reports.

## Layout

```
uglc-lab/
├── postgresql-clickhouse/   setup.sh, test.sh, sync.sh and the SQL files (see its README)
├── hdfs-parquet/            setup.sh, test.sh and the Spark jobs in spark/ (see its README)
├── data/                    UGLC_point.csv, shared by both parts (downloaded by setup.sh, not in git)
└── results/                 test reports from both parts (not in git)
    ├── <date-time>/            from postgresql-clickhouse/test.sh
    └── hdfs-<date-time>/       from hdfs-parquet/test.sh
```

## The questions

| Code | Question | Main design answers it with |
|---|---|---|
| V1 | Show one landslide event (by id) | PostgreSQL |
| V2 | Landslides between date X and Y | PostgreSQL |
| V3 | Landslides in country X | PostgreSQL |
| V4 | Landslides within 20 km of a location | PostgreSQL (PostGIS) |
| C1 | Submit a new landslide report | PostgreSQL |
| C2 | Edit a report I submitted | PostgreSQL |
| B1 | Share of landslides per type | ClickHouse |
| B2 | Type of the deadliest landslide | ClickHouse |
| B3 | Where landslides are most frequent (country, 1° grid cell) | ClickHouse |
| B4 | Total fatalities per country per decade, by trigger | ClickHouse |
| B5 | Number of landslides per year | ClickHouse |

V = visitors of the public portal, C = contributors, B = the BNPB dashboard. The baseline answers all
of them with Spark SQL. The tests run B2, B4 and B5 for Indonesia (B4 also for all countries); B1 and
B3 are global.

| Target | |
|---|---|
| NFR-1 | Portal queries (V) take under 1 s |
| NFR-2 | Dashboard queries (B) take under 5 s |
| NFR-3 | An acknowledged submission is never lost and is visible right away |
| NFR-4 | The dashboard may lag by at most one sync interval |
| NFR-5 | Heavy dashboard queries must not slow down the portal |

## Quick start

You need **Docker** with Compose v2. On Windows, run the commands in Git Bash (details in
[postgresql-clickhouse/README.md](postgresql-clickhouse/README.md#requirements)).

```bash
git clone https://github.com/IKadekFredlySukrata/uglc-lab.git
cd uglc-lab
```

Main design:

```bash
cd postgresql-clickhouse
./setup.sh    # once: download the CSV, load and clean it in PostgreSQL, copy it to ClickHouse, check
./test.sh     # V1–V4, B1–B5, C1/C2 and the sync -> ../results/<date-time>/summary.md
```

Baseline:

```bash
cd hdfs-parquet
./setup.sh    # once: start HDFS + Spark, clean the CSV in Spark, write Parquet to HDFS, check
./test.sh     # the same questions on Parquet -> ../results/hdfs-<date-time>/summary.md
```

The order doesn't matter. Whichever `setup.sh` runs first downloads the CSV (337 MB, MD5-checked)
into `data/`, and the other one reuses it. Both parts can run at the same time.

Memory: the PostgreSQL + ClickHouse part needs about 8 GB RAM for Docker. The baseline adds a Spark
driver with 3 GB (set `SPARK_MEM` to change it).

## What runs where

| Compose project | Container | Reach it at |
|---|---|---|
| `uglc-lab` (postgresql-clickhouse) | `uglc-lab-postgis` | PostgreSQL `localhost:5433` |
| | `uglc-lab-clickhouse` | ClickHouse HTTP `localhost:8124`, native `localhost:9001` |
| | `uglc-lab-metabase` | Metabase `http://localhost:3001` |
| `uglc-lab-hdfs` (hdfs-parquet) | `uglc-lab-hdfs-nn` | HDFS namenode web UI `http://localhost:9871` |
| | `uglc-lab-hdfs-dn`, `uglc-lab-hdfs-spark` | no ports |

All ports listen on 127.0.0.1 only. Database user `uglc`, password `uglc_dev_pw`, database `uglc`:
local lab passwords only.

Stop either part with `docker compose stop` inside its folder. The baseline keeps no Docker volumes,
so `docker compose down` in `hdfs-parquet/` deletes the Parquet files; `./setup.sh --reset` builds
them again.

## One example run

One run of each `test.sh` on 2026-11-25 (Linux x86_64, Docker with 12 CPUs and 33.9 GB RAM). Each
query ran twice and the second (warm) run is shown.

| Query | PostgreSQL (with indexes) | ClickHouse | Spark on Parquet |
|---|---|---|---|
| V1 one event by id | 0.08 ms | – | 128 ms |
| V2 one year (2010) | 3.84 ms | – | 272 ms |
| V3 one country (Indonesia) | 1.82 ms | – | 129 ms |
| V4 within 20 km of Surabaya | 7.20 ms | – | 372 ms (95 ms with a bounding box first) |
| B1 share per type | – | 23 ms | 184 ms |
| B2 deadliest type (Indonesia) | – | 26 ms | 135 ms |
| B3.1 top countries | – | 77 ms | 105 ms |
| B3.2 top 1° grid cells | – | 44 ms | 306 ms |
| B4 Indonesia | 2.32 ms | 27 ms | 170 ms |
| B4 all countries | 164 ms | 29 ms | 176 ms |
| B5 per year (Indonesia, after 2010) | – | 83 ms | 136 ms |

Contributors:

- **PostgreSQL:** a new report (C1) is visible from another connection as soon as it commits. An
  edit (C2) by the owner changes 1 row; the same edit by another contributor changes 0. With demo
  sync settings (check every second), a commit reached the dashboard in 0.9–1.6 s. With the default
  settings the lag is at most 5 minutes.
- **Parquet:** there is no UPDATE. C1 appends a new file (0.83 s, plus 1.24 s to scan for the next
  id). C2 rewrites the whole dataset (2.92 s), and swapping in the new copy is not atomic.

The engines are timed differently: PostgreSQL by server execution time (`EXPLAIN ANALYZE`),
ClickHouse by `clickhouse-client --time`, and Spark by the time to run the whole plan, without its
3.6 s session start-up. Compare orders of magnitude, not decimals. ClickHouse had 3 unmerged parts
during this run, which makes its `FINAL` queries slower than with 1 part.

What this run shows:

- At this size, every engine met NFR-1 (< 1 s) and NFR-2 (< 5 s).
- For lookups and filters, PostgreSQL with indexes was 50–1,600× faster than Spark on Parquet, which
  has no indexes (V1 relies on Parquet min/max statistics, V4 has no spatial index).
- For dashboard aggregations, ClickHouse was 1.4–8× faster than Spark. B4 for all countries took
  164 ms on PostgreSQL because it reads the whole portal table; ClickHouse took 29 ms. That is why
  the dashboard has its own store (NFR-5).
- 1.06 million rows (about 340 MB of CSV) is far below the size where HDFS pays off. A one-node
  cluster measures the file format and the engine, not distributed storage.

## Data and credits

Data: UGLC point catalogue, [Zenodo record 18643456](https://zenodo.org/records/18643456) (v2), file
`UGLC_point.csv`, 1,060,503 rows, licence **CC BY-NC 4.0**. It isn't included in this repository;
`setup.sh` downloads it from the source. Both parts clean it with the same rules: "unknown" values
(`'ND'`, `-99999`, …) become `NULL`, 109 rows with the end date before the start date get their
dates swapped, and 9 rows with infinite coordinates get no location.

`hdfs-parquet/` started as a copy of [manggahijau/hdfs-thingy](https://github.com/manggahijau/hdfs-thingy)
at commit `a6fc7ae`.
