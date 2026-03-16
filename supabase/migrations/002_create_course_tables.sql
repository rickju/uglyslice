CREATE TABLE course_list (
  id    BIGINT PRIMARY KEY,   -- OSM element id
  name  TEXT NOT NULL,
  type  TEXT NOT NULL,        -- node / way / relation
  lat   DOUBLE PRECISION NOT NULL,
  lon   DOUBLE PRECISION NOT NULL
);

CREATE TABLE courses (
  id          TEXT PRIMARY KEY,   -- e.g. osm_747473941
  name        TEXT NOT NULL,
  course_doc  JSONB NOT NULL,
  holes_doc   JSONB NOT NULL,
  updated_at  TIMESTAMPTZ NOT NULL
);

ALTER PUBLICATION supabase_realtime ADD TABLE course_list;
ALTER PUBLICATION supabase_realtime ADD TABLE courses;
