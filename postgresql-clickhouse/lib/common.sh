# Shared settings and helpers, sourced by setup.sh, test.sh and sync.sh.

# Git Bash on Windows rewrites arguments that look like /paths. Docker needs them as-is.
export MSYS_NO_PATHCONV=1

PG_CONTAINER=uglc-lab-postgis
CH_CONTAINER=uglc-lab-clickhouse
DB_USER=uglc
DB_PASSWORD=uglc_dev_pw
DB_NAME=uglc

# psql inside the Postgres container, reading SQL from stdin:  pg < file.sql
pg() { docker exec -i "$PG_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 "$@"; }

# One Postgres query -> bare value(s), no headers. Never reads stdin, so it can't hang.
pg_val() { docker exec "$PG_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -At -c "$1" </dev/null; }

# clickhouse-client, reading SQL from stdin:  ch --multiquery < file.sql
ch() { docker exec -i "$CH_CONTAINER" clickhouse-client -u "$DB_USER" --password "$DB_PASSWORD" -d "$DB_NAME" "$@"; }

# One ClickHouse query:  ch_q -q "SELECT ..." [--param_x=...]. Never reads stdin.
ch_q() { docker exec "$CH_CONTAINER" clickhouse-client -u "$DB_USER" --password "$DB_PASSWORD" -d "$DB_NAME" "$@" </dev/null; }

step() { printf '\n==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
fail() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

require_docker() {
    command -v docker >/dev/null 2>&1 || fail "Docker is not installed (https://docs.docker.com/get-docker/)."
    docker info >/dev/null 2>&1 || fail "Docker is installed but not running (start Docker Desktop / the docker service)."
    docker compose version >/dev/null 2>&1 || fail "'docker compose' (Compose v2) is missing. Update Docker."
}

# The official postgis image is amd64-only; ARM machines (Apple Silicon) need this one
pick_postgis_image() {
    case "$(uname -m)" in
        arm64|aarch64) export POSTGIS_IMAGE=${POSTGIS_IMAGE:-imresamu/postgis:18-3.6} ;;
    esac
}

start_stack() {
    pick_postgis_image
    docker compose up -d --wait >/dev/null || fail "Containers didn't start. See: docker compose logs"
}

# True once setup.sh has finished completely (its last step writes this row)
setup_done() {
    [[ $(ch_q -q "SELECT count() FROM system.tables WHERE database = 'uglc' AND name = 'sync_log'" 2>/dev/null) == 1 ]] &&
    [[ $(ch_q -q "SELECT count() FROM sync_log WHERE reason = 'initial load'" 2>/dev/null) -ge 1 ]]
}

# SQL test files are split into sections by marker lines:  -- @NAME  description
# Names of all sections in a file, in order
sections() { grep -E '^-- @' "$1" | sed -E 's/^-- @([^ ]+).*/\1/'; }
# Description of one section
section_title() { grep -E "^-- @$2( |$)" "$1" | sed -E 's/^-- @[^ ]+ *//'; }
# SQL of one section (from its marker to the next one)
section_sql() { awk -v name="@$2" '/^-- @/ { p = ($2 == name) } p' "$1"; }
