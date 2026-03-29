import 'package:test/test.dart';
import 'package:ugly_slice_backend/scheduler.dart';

void main() {
  group('Scheduler.runJob', () {
    test('returns true when job succeeds', () async {
      final scheduler = Scheduler();
      final result = await scheduler.runJob('test', () async {});
      expect(result, isTrue);
    });

    test('returns false when job throws', () async {
      final scheduler = Scheduler();
      final result = await scheduler.runJob('failing', () async {
        throw Exception('boom');
      });
      expect(result, isFalse);
    });

    test('does not rethrow — caller is not affected', () async {
      final scheduler = Scheduler();
      // If this were to throw, the test itself would fail.
      await expectLater(
        scheduler.runJob('noisy', () async => throw StateError('nope')),
        completion(isFalse),
      );
    });

    test('runs multiple jobs independently', () async {
      final scheduler = Scheduler();
      final log = <String>[];
      await scheduler.runJob('a', () async => log.add('a'));
      await scheduler.runJob('b', () async => throw Exception('b failed'));
      await scheduler.runJob('c', () async => log.add('c'));
      expect(log, equals(['a', 'c']));
    });

    test('dry-run flag is reflected in constructor', () {
      final scheduler = Scheduler(dryRun: true);
      expect(scheduler.dryRun, isTrue);
    });
  });
}
