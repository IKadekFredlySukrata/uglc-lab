-- [PostgreSQL] C1: a contributor submits a new report.
-- Committed (no BEGIN/ROLLBACK): the sync only sees committed rows. The reports stay as history;
-- find them with:  SELECT * FROM landslides WHERE notes LIKE 'TEST %';
-- test.sh passes :run_tag (the run's date-time).

-- Two test contributors. ON CONFLICT: after the first run they already exist.
INSERT INTO contributors (username, institution)
VALUES ('lab_contributor_a', 'UGLC Storage Lab'),
       ('lab_contributor_b', 'UGLC Storage Lab')
ON CONFLICT (username) DO NOTHING;

-- Contributor A submits a report. No id given: the sequence picks the next one.
INSERT INTO landslides (geom, source_dataset, submitted_by, country, start_date, end_date,
                        type, physical_factors, record_type, fatalities, injuries, notes)
VALUES (ST_SetSRID(ST_MakePoint(106.816, -6.595), 4326),                       -- Bogor (lon first)
        'Contributor portal',
        (SELECT id FROM contributors WHERE username = 'lab_contributor_a'),
        'Indonesia', CURRENT_DATE, CURRENT_DATE,
        'debris flow', 'rainfall (T)', 'event',
        3, 5,
        'TEST ' || :'run_tag' || ': report submitted by test.sh')
RETURNING id AS c1_id \gset

\echo C1_ID=:c1_id
