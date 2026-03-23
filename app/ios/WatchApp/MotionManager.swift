import CoreMotion
import Foundation

/// Detects golf swing gestures via the Watch's gyroscope.
///
/// A swing is inferred when the combined rotation rate magnitude exceeds
/// [threshold] rad/s. A [cooldown] prevents repeated triggers from one swing.
class MotionManager: ObservableObject {

  var onSwingDetected: (() -> Void)?

  private let cm = CMMotionManager()
  private var lastSwingTime: Date = .distantPast
  private let threshold: Double = 4.5   // rad/s — tuned for golf swing
  private let cooldown: TimeInterval = 2.0

  func start() {
    guard cm.isDeviceMotionAvailable else { return }
    cm.deviceMotionUpdateInterval = 1.0 / 30.0
    cm.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
      guard let self, let motion else { return }
      let r = motion.rotationRate
      let magnitude = sqrt(r.x * r.x + r.y * r.y + r.z * r.z)
      guard magnitude > self.threshold else { return }
      let now = Date()
      guard now.timeIntervalSince(self.lastSwingTime) > self.cooldown else { return }
      self.lastSwingTime = now
      self.onSwingDetected?()
    }
  }

  func stop() {
    cm.stopDeviceMotionUpdates()
  }
}
