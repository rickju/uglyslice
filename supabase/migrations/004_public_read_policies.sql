ALTER TABLE course_list ENABLE ROW LEVEL SECURITY;
ALTER TABLE courses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow public read" ON course_list
  FOR SELECT TO anon USING (true);

CREATE POLICY "Allow public read" ON courses
  FOR SELECT TO anon USING (true);
