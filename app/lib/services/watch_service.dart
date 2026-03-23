import 'dart:io';

import 'package:flutter/services.dart';

/// Bridges the native WatchConnectivity session to Flutter (iOS only).
///
/// The iOS AppDelegate forwards WCSession messages on the channel.
/// Call [listen] once (e.g. in initState) to receive hit events.
/// Call [sendContext] whenever the current hole or distance changes.
class WatchService {
  static const _channel = MethodChannel('ugly_slice/watch');

  static final WatchService instance = WatchService._();
  WatchService._();

  bool get isSupported => Platform.isIOS;

  /// Register callbacks for events coming from the Watch.
  void listen({required void Function() onHit}) {
    if (!isSupported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onHit') onHit();
    });
  }

  /// Push current hole info to the Watch face via application context.
  Future<void> sendContext({
    required int holeNumber,
    required int par,
    int distanceYards = 0,
  }) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('sendContext', {
        'holeNumber': holeNumber,
        'par': par,
        'distanceYards': distanceYards,
      });
    } on PlatformException {
      // Watch not paired / not reachable — silently ignore.
    }
  }
}
