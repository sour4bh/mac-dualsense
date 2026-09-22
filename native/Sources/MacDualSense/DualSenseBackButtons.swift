import SwiftUI

/// DualSense controller back view button definitions
struct DualSenseBackButtonProvider: ControllerButtonProvider {
    let viewBox = DualSenseVisuals.backViewBox

    var buttons: [String: ControllerButton] {
        Self.buttonDefinitions
    }

    // Back view shows L1, L2, R1, R2 from behind the controller
    private static let buttonDefinitions: [String: ControllerButton] = {
        var buttons: [String: ControllerButton] = [:]

        guard let url = Bundle.module.url(
            forResource: DualSenseVisuals.backResourceName,
            withExtension: "svg"
        ) else {
            fatalError("Missing back SVG resource for button extraction")
        }

        let extractedPaths = SVGButtonExtractor.extract(url: url)

        func addButton(id: String, label: String) {
            guard let path = extractedPaths[id] else {
                fatalError("Missing SVG path for button id: \(id)")
            }
            buttons[id] = ControllerButton(
                id: id,
                pathData: path,
                label: label,
                color: nil,
                transform: DualSenseVisuals.backFlipTransform
            )
        }

        addButton(id: "l2", label: "L2")
        addButton(id: "r2", label: "R2")
        addButton(id: "l1", label: "L1")
        addButton(id: "r1", label: "R1")

        return buttons
    }()
}
