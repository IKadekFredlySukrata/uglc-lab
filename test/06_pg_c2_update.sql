-- [PostgreSQL] C2: contributors may only edit their own reports.
-- test.sh passes :c1_id (the report from 05_pg_c1_submit.sql, owned by contributor A).
-- updated_at = now() by hand: DEFAULT now() only fires on INSERT, and the sync needs it.

\echo OWNER
UPDATE landslides
SET    fatalities = 4,
       updated_at = now()
WHERE  id = :c1_id
  AND  submitted_by = (SELECT id FROM contributors WHERE username = 'lab_contributor_a');
-- expect UPDATE 1

\echo OTHER
UPDATE landslides
SET    fatalities = 99,
       updated_at = now()
WHERE  id = :c1_id
  AND  submitted_by = (SELECT id FROM contributors WHERE username = 'lab_contributor_b');
-- expect UPDATE 0: contributor B can't edit A's report
