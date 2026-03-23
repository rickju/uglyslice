import Flutter
import UIKit
import WatchConnectivity

@main
@objc class AppDelegate: FlutterAppDelegate, WCSessionDelegate {

  private var watchChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller = window?.rootViewController as! FlutterViewController
    watchChannel = FlutterMethodChannel(
      name: "ugly_slice/watch",
      binaryMessenger: controller.binaryMessenger
    )

    // Handle sendContext calls from Flutter → Watch
    watchChannel?.setMethodCallHandler { [weak self] call, result in
      if call.method == "sendContext",
         let args = call.arguments as? [String: Any] {
        self?.pushContextToWatch(args)
      }
      result(nil)
    }

    if WCSession.isSupported() {
      WCSession.default.delegate = self
      WCSession.default.activate()
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - Watch → Flutter

  func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      switch message["event"] as? String {
      case "hit":
        self.watchChannel?.invokeMethod("onHit", arguments: nil)
      default:
        break
      }
    }
  }

  // MARK: - Flutter → Watch

  private func pushContextToWatch(_ context: [String: Any]) {
    guard WCSession.default.activationState == .activated else { return }
    try? WCSession.default.updateApplicationContext(context)
  }

  // MARK: - WCSessionDelegate boilerplate

  func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {}

  func sessionDidBecomeInactive(_ session: WCSession) {}

  func sessionDidDeactivate(_ session: WCSession) {
    WCSession.default.activate()
  }
}
