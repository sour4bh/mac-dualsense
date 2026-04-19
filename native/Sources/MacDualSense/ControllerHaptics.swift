import CoreHaptics
import Foundation
import GameController

@MainActor
final class ControllerHaptics {
    struct Spec {
        let intensity: Float
        let durationSeconds: TimeInterval
        let repeatCount: Int
        let gapSeconds: TimeInterval

        init(intensity: Float, durationSeconds: TimeInterval, repeatCount: Int, gapSeconds: TimeInterval = 0.04) {
            self.intensity = intensity
            self.durationSeconds = durationSeconds
            self.repeatCount = repeatCount
            self.gapSeconds = gapSeconds
        }
    }

    private var engines: [String: CHHapticEngine] = [:]

    func play(
        controller: GCController?,
        enabled: Bool,
        pattern: CCHapticPattern?,
        fallback: Spec
    ) {
        guard enabled else { return }
        guard let controller else { return }

        let spec = Self.resolve(pattern: pattern, fallback: fallback)
        guard spec.durationSeconds > 0 else { return }

        let key = String(ObjectIdentifier(controller).hashValue)
        guard let engine = hapticEngine(for: controller, key: key) else { return }

        do {
            try engine.start()
            try play(spec: spec, engine: engine)
        } catch {
            Logger.shared.debug("Haptics error: \(error)")
            engines.removeValue(forKey: key)
        }
    }

    private func hapticEngine(for controller: GCController, key: String) -> CHHapticEngine? {
        if let cached = engines[key] {
            return cached
        }

        guard let haptics = controller.haptics else { return nil }
        guard let engine = haptics.createEngine(withLocality: .default) else { return nil }

        engine.playsHapticsOnly = true
        engine.isMutedForHaptics = false

        engine.stoppedHandler = { reason in
            Logger.shared.debug("Haptics engine stopped: \(reason.rawValue)")
        }

        engine.resetHandler = {
            Logger.shared.debug("Haptics engine reset")
            // Best-effort: patterns are created per-play, so no player recreation is needed here.
            // If the engine becomes unusable, the next `play()` call will recreate it.
        }

        engines[key] = engine
        return engine
    }

    private func play(spec: Spec, engine: CHHapticEngine) throws {
        let intensity = min(max(spec.intensity, 0.0), 1.0)
        let duration = max(0.0, spec.durationSeconds)
        let repeatCount = max(1, spec.repeatCount)
        let gap = max(0.0, spec.gapSeconds)

        let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity)
        let sharpnessParam = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)

        var events: [CHHapticEvent] = []
        for i in 0..<repeatCount {
            let start = (duration + gap) * Double(i)
            events.append(
                CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [intensityParam, sharpnessParam],
                    relativeTime: start,
                    duration: duration
                )
            )
        }

        let pattern = try CHHapticPattern(events: events, parameters: [])
        let player = try engine.makePlayer(with: pattern)
        try player.start(atTime: 0)
    }

    private static func resolve(pattern: CCHapticPattern?, fallback: Spec) -> Spec {
        guard let pattern else { return fallback }
        let rawIntensity = pattern.intensity ?? Int((fallback.intensity * 255.0).rounded())
        let intensity = Float(min(max(rawIntensity, 0), 255)) / 255.0
        let durationSeconds = TimeInterval(max(0, pattern.durationMs ?? Int(fallback.durationSeconds * 1000))) / 1000.0
        let repeatCount = max(1, pattern.repeatCount ?? fallback.repeatCount)
        return Spec(intensity: intensity, durationSeconds: durationSeconds, repeatCount: repeatCount, gapSeconds: fallback.gapSeconds)
    }
}
