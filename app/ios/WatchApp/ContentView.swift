import SwiftUI

struct ContentView: View {
  @EnvironmentObject var connectivity: WatchConnectivityManager
  @StateObject private var motion = MotionManager()
  @State private var hitFlash = false

  var body: some View {
    VStack(spacing: 6) {

      // Hole / par header
      HStack {
        statBlock(label: "HOLE", value: "\(connectivity.holeNumber)")
        Spacer()
        statBlock(label: "PAR", value: "\(connectivity.par)")
      }

      // Distance to pin
      if connectivity.distanceYards > 0 {
        Text("\(connectivity.distanceYards) y")
          .font(.system(size: 22, weight: .semibold, design: .rounded))
          .foregroundColor(.green)
      }

      Spacer()

      // Hit flash indicator
      Circle()
        .fill(hitFlash ? Color.cyan : Color.gray.opacity(0.25))
        .frame(width: 10, height: 10)
        .animation(.easeOut(duration: 0.4), value: hitFlash)

      // Manual hit button (fallback when motion detection misses)
      Button {
        triggerHit()
      } label: {
        Label("Hit", systemImage: "figure.golf")
          .font(.system(size: 14, weight: .bold))
      }
      .buttonStyle(.borderedProminent)
      .tint(.cyan)
    }
    .padding()
    .onAppear {
      motion.onSwingDetected = { triggerHit() }
      motion.start()
    }
    .onDisappear {
      motion.stop()
    }
  }

  private func triggerHit() {
    connectivity.sendHit()
    hitFlash = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      hitFlash = false
    }
  }

  @ViewBuilder
  private func statBlock(label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(label)
        .font(.system(size: 9, weight: .medium))
        .foregroundColor(.secondary)
      Text(value)
        .font(.system(size: 30, weight: .bold, design: .rounded))
    }
  }
}
