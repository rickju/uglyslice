CREATE POLICY "Allow authenticated read" ON course_list
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "Allow authenticated read" ON courses
  FOR SELECT TO authenticated USING (true);
