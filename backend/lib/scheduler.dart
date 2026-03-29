import 'dart:async';

/// Simple job runner with error isolation and structured logging.
class Scheduler {
  final bool dryRun;

  Scheduler({this.dryRun = false});

  /// Run [job] immediately, catching all errors so the caller is not affected.
  /// Returns true if the job succeeded.
  Future<bool> runJob(String name, Future<void> Function() job) async {
    final start = DateTime.now();
    _log(name, 'starting${dryRun ? ' (dry run)' : ''}');
    try {
      await job();
      final elapsed = DateTime.now().difference(start).inSeconds;
      _log(name, 'completed in ${elapsed}s');
      return true;
    } catch (e, st) {
      final elapsed = DateTime.now().difference(start).inSeconds;
      _log(name, 'FAILED after ${elapsed}s: $e');
      _log(name, st.toString());
      return false;
    }
  }

  /// Schedule [job] to run periodically every [interval].
  /// The first run starts after [interval] (not immediately).
  Timer scheduleRecurring(
      String name, Duration interval, Future<void> Function() job) {
    return Timer.periodic(interval, (_) => runJob(name, job));
  }

  void _log(String job, String message) {
    final ts = DateTime.now().toUtc().toIso8601String().substring(0, 19);
    print('[$ts] [$job] $message');
  }
}
