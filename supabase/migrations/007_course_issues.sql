-- Integrity issues detected by the audit job.
-- Auto-resolved (resolved_at set) when a re-ingest produces no issues.
CREATE TABLE course_issues (
  id          SERIAL PRIMARY KEY,
  course_id   TEXT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  severity    TEXT NOT NULL CHECK (severity IN ('error', 'warning')),
  message     TEXT NOT NULL,
  hole_number INT,             -- null = course-level issue
  detected_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at TIMESTAMPTZ      -- null = still open
);

CREATE INDEX ON course_issues (course_id, resolved_at);
CREATE INDEX ON course_issues (resolved_at) WHERE resolved_at IS NULL;
