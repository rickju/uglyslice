-- Queue of courses needing enrichment (missing ratings, handicaps, etc.)
-- Populated by the audit job; processed by the enrich job.
CREATE TABLE enrich_queue (
  id          SERIAL PRIMARY KEY,
  course_id   TEXT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  course_name TEXT NOT NULL,
  fields      JSONB NOT NULL,   -- e.g. ["tee_ratings","hole_handicaps"]
  status      TEXT NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending', 'in_progress', 'done', 'failed')),
  attempts    INT NOT NULL DEFAULT 0,
  last_error  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ON enrich_queue (status);
CREATE UNIQUE INDEX ON enrich_queue (course_id) WHERE status IN ('pending', 'in_progress');
