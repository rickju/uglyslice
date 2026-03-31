import 'dart:async';
import 'package:ugly_slice_backend/enricher.dart';
import 'package:ugly_slice_backend/gemini_client.dart';
import 'package:ugly_slice_backend/ingest_core.dart';
import 'package:ugly_slice_backend/scheduler.dart';

/// Global regions for discover/ingest jobs.
/// Each value is a named area passed to [ingestRegion].
const _regions = [
  'New Zealand',
  'Australia',
  'United States',
  'United Kingdom',
  'Canada',
  'Germany',
  'France',
  'Japan',
  'South Korea',
  'South Africa',
];

Future<void> main(List<String> args) async {
  final dryRun = args.contains('--dry-run');
  final runOnce = args.contains('--once');
  // --enrich-only: skip discover/ingest, only process the enrich queue.
  // Implied by --once to avoid hammering Overpass during development.
  final enrichOnly = args.contains('--enrich-only') || runOnce;
  // --gemini: enable the Gemini hole-estimate pass inside the enrich job.
  final useGemini = args.contains('--gemini');

  // --region <name>: restrict discover/ingest to a single named region.
  final regionIdx = args.indexOf('--region');
  final regionFilter =
      regionIdx >= 0 && regionIdx + 1 < args.length ? args[regionIdx + 1] : null;
  final activeRegions =
      regionFilter != null ? [regionFilter] : _regions;

  final scheduler = Scheduler(dryRun: dryRun);

  print('Ugly Slice backend daemon starting');
  print('  dry-run     : $dryRun');
  print('  once        : $runOnce');
  print('  enrich-only : $enrichOnly');
  print('  regions     : ${enrichOnly ? "n/a" : activeRegions.join(", ")}');
  print('  gemini      : $useGemini');
  print('');

  if (!enrichOnly) {
    await scheduler.runJob('discover', () => _discoverJob(activeRegions, dryRun: dryRun));
    await scheduler.runJob('ingest', () => _ingestJob(activeRegions, dryRun: dryRun));
    await scheduler.runJob('audit', () => _auditJob(dryRun: dryRun));
  }
  await scheduler.runJob('enrich', () => _enrichJob(dryRun: dryRun, useGemini: useGemini));

  if (runOnce) {
    print('\nDone (--once mode).');
    return;
  }

  // Schedule recurring jobs.
  if (!enrichOnly) {
    scheduler.scheduleRecurring('ingest', const Duration(hours: 24),
        () => _ingestJob(activeRegions, dryRun: dryRun));
    scheduler.scheduleRecurring('discover', const Duration(days: 7),
        () => _discoverJob(activeRegions, dryRun: dryRun));
  }
  scheduler.scheduleRecurring(
      'enrich', const Duration(hours: 6), () => _enrichJob(dryRun: dryRun, useGemini: useGemini));

  print('Daemon running. Press Ctrl+C to stop.');
  // Keep process alive.
  await Completer<void>().future;
}

/// Discover new and closed courses for the given regions.
Future<void> _discoverJob(List<String> regions, {bool dryRun = false}) async {
  print('Discover: checking ${regions.length} regions ...');
  for (final region in regions) {
    print('  → $region');
    if (!dryRun) {
      try {
        await ingestRegion(region);
      } catch (e) {
        print('  → $region FAILED: $e');
      }
    }
  }
}

/// Ingest (re-fetch + parse) all courses in the given regions.
/// Change detection skips courses whose Overpass data is unchanged.
Future<void> _ingestJob(List<String> regions, {bool dryRun = false}) async {
  print('Ingest: processing ${regions.length} regions ...');
  for (final region in regions) {
    print('\n--- Region: $region ---');
    if (!dryRun) {
      try {
        final result = await ingestRegion(region);
        print(
            'Region $region: total=${result.total}  ok=${result.succeeded}  fail=${result.failed}');
      } catch (e) {
        print('Region $region FAILED: $e');
      }
    }
  }
}

/// Run integrity audit on all courses already in Supabase.
Future<void> _auditJob({bool dryRun = false}) async {
  await auditAllCourses(dryRun: dryRun);
}

/// Process pending enrichment queue items.
Future<void> _enrichJob({bool dryRun = false, bool useGemini = false}) async {
  final enricher = Enricher(gemini: useGemini ? GeminiClient() : null);
  await enricher.processQueue(batchSize: 20, dryRun: dryRun);
}
