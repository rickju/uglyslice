import WatchConnectivity
import Combine

/// Manages the WatchConnectivity session on the Watch side.
/// Receives hole/par/distance context from the iPhone and sends hit events back.
class WatchConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {

  @Published var holeNumber: Int = 1
  @Published var par: Int = 4
  @Published var distanceYards: Int = 0

  override init() {
    super.init()
    guard WCSession.isSupported() else { return }
    WCSession.default.delegate = self
    WCSession.default.activate()
  }

  // MARK: - Watch → iPhone

  func sendHit() {
    guard WCSession.default.isReachable else { return }
    WCSession.default.sendMessage(["event": "hit"], replyHandler: nil, errorHandler: nil)
  }

  // MARK: - iPhone → Watch (application context)

  func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
    DispatchQueue.main.async {
      if let v = context["holeNumber"] as? Int { self.holeNumber = v }
      if let v = context["par"] as? Int { self.par = v }
      if let v = context["distanceYards"] as? Int { self.distanceYards = v }
    }
  }

  // MARK: - WCSessionDelegate boilerplate

  func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {}
}
