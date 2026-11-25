-- Runs once, on the first start of an EMPTY Postgres volume (/docker-entrypoint-initdb.d).
-- Metabase keeps its own settings in this database; the image only creates POSTGRES_DB (uglc).
CREATE DATABASE metabase;