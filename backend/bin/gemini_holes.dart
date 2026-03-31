/// CLI tool: run the Gemini hole-estimate pass on courses with no OSM holes.
///
/// Usage:
///   dart run bin/gemini_holes.dart [--dry-run] [--course-id <id>]
///
/// Without --course-id, processes all courses in Supabase that have an empty
/// holes_doc. With --course-id, processes that one course only.
///
/// Requires GEMINI_API_KEY and SUPABASE_URL / SUPABASE_KEY env vars.
import 'package:ugly_slice_backend/enricher.dart';
import 'package:ugly_slice_backend/gemini_client.dart';

Future<void> main(List<String> args) async {
  final dryRun = args.contains('--dry-run');

  final courseIdIdx = args.indexOf('--course-id');
  final courseId =
      courseIdIdx >= 0 && courseIdIdx + 1 < args.length ? args[courseIdIdx + 1] : null;

  final nameIdx = args.indexOf('--name');
  final courseName =
      nameIdx >= 0 && nameIdx + 1 < args.length ? args[nameIdx + 1] : null;

  print('Gemini hole-estimate pass');
  print('  dry-run  : $dryRun');
  print('  course-id: ${courseId ?? "(all with no holes)"}');
  print('');

  final enricher = Enricher(gemini: GeminiClient());

  if (courseId != null) {
    if (courseName == null) {
      print('Error: --course-id requires --name <course name>');
      return;
    }
    await enricher.geminiEstimateOne(courseId, courseName, dryRun: dryRun);
  } else {
    await enricher.geminiEstimateAll(dryRun: dryRun);
  }
}
