-- Run from psql while connected to the default `postgres` database.
-- psql meta-commands make this script safely repeatable.
SELECT 'CREATE DATABASE manufacturing_yield'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'manufacturing_yield')\gexec

\connect manufacturing_yield

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS manufacturing;
CREATE SCHEMA IF NOT EXISTS analytics;
