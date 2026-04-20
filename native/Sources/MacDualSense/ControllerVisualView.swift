import SwiftUI

// MARK: - Main View

struct ControllerVisualView: View {
    let controllerType: ControllerType
    let viewSide: ControllerViewSide
    let pressed: Set<String>
    let getAction: (String) -> ActionDef?
    let onEditButton: ((String) -> Void)?

    @State private var hoveredButton: String?

    private var buttonProvider: ControllerButtonProvider? {
        controllerType.buttonProvider(for: viewSide)
    }

    private var viewBox: CGRect? {
        controllerType.viewBox(for: viewSide)
    }

    private var backgroundResourceName: String? {
        controllerType.svgResourceName(for: viewSide)
    }

    var body: some View {
        Group {
            if let viewBox, let backgroundResourceName, let buttonProvider {
                GeometryReader { geo in
                    let scale = calculateScale(for: geo.size, viewBox: viewBox)
                    let scaledSize = CGSize(
                        width: viewBox.width * scale,
                        height: viewBox.height * scale
                    )
                    let transform = CGAffineTransform(scaleX: scale, y: scale)
                        .translatedBy(x: -viewBox.origin.x, y: -viewBox.origin.y)

                    ZStack(alignment: .topLeading) {
                        ControllerBackground(
                            resourceName: backgroundResourceName,
                            size: scaledSize
                        )

                        ButtonOverlayCanvas(
                            buttons: buttonProvider.buttons,
                            transform: transform,
                            pressed: pressed,
                            hoveredButton: hoveredButton,
                            getAction: getAction
                        )
                        .frame(width: scaledSize.width, height: scaledSize.height)

                        ButtonHitTestLayer(
                            buttons: buttonProvider.buttons,
                            transform: transform,
                            hitTestStrokeWidth: viewSide == .back ? 0 : 22,
                            hoveredButton: $hoveredButton,
                            onEditButton: onEditButton,
                            getAction: getAction
                        )
                        .frame(width: scaledSize.width, height: scaledSize.height)
                    }
                    .frame(width: scaledSize.width, height: scaledSize.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                UnsupportedControllerVisual(controllerType: controllerType)
            }
        }
        .onChange(of: viewSide) {
            hoveredButton = nil
        }
    }

    private func calculateScale(for size: CGSize, viewBox: CGRect) -> CGFloat {
        return min(size.width / viewBox.width, size.height / viewBox.height)
    }
}

private struct UnsupportedControllerVisual: View {
    let controllerType: ControllerType

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("\(controllerType.displayName) visual editor unavailable")
                .font(.headline)
            Text("Use the Keybinds tab to edit mappings while this controller is connected.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Controller Background

private struct ControllerBackground: View {
    let resourceName: String
    let size: CGSize

    var body: some View {
        Image(nsImage: loadSVGImage())
            .resizable()
            .frame(width: size.width, height: size.height)
    }

    private func loadSVGImage() -> NSImage {
        guard let url = Bundle.module.url(
            forResource: resourceName,
            withExtension: "svg"
        ) else {
            fatalError("Missing SVG resource: \(resourceName).svg")
        }
        guard let image = NSImage(contentsOf: url) else {
            fatalError("Failed to load SVG resource: \(url.path)")
        }
        return image
    }
}

// MARK: - Button Overlay Canvas (visual effects only)

private struct ButtonOverlayCanvas: View {
    let buttons: [String: ControllerButton]
    let transform: CGAffineTransform
    let pressed: Set<String>
    let hoveredButton: String?
    let getAction: (String) -> ActionDef?

    var body: some View {
        Canvas { context, size in
            for (buttonId, button) in buttons {
                let path = button.path.applying(transform)
                let color = button.color ?? .accentColor

                if pressed.contains(buttonId) {
                    // Pressed: solid fill with glow
                    context.fill(path, with: .color(color.opacity(0.7)))
                    context.stroke(path, with: .color(color.opacity(0.9)), lineWidth: 2)
                } else if hoveredButton == buttonId {
                    // Hovered: light fill + stroke
                    context.fill(path, with: .color(color.opacity(0.25)))
                    context.stroke(path, with: .color(color.opacity(0.6)), lineWidth: 2)
                }
                // Note: No fill when idle - buttons are invisible until interacted with
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Button Hit Test Layer

private struct ButtonHitTestLayer: View {
    let buttons: [String: ControllerButton]
    let transform: CGAffineTransform
    let hitTestStrokeWidth: CGFloat
    @Binding var hoveredButton: String?
    let onEditButton: ((String) -> Void)?
    let getAction: (String) -> ActionDef?

    // Cached hit test data
    @State private var sortedButtonIds: [String] = []
    @State private var transformedPaths: [String: Path] = [:]
    @State private var strokedPaths: [String: Path] = [:]
    @State private var boundingBoxes: [String: CGRect] = [:]

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .onContinuousHover(coordinateSpace: .local) { phase in
                    switch phase {
                    case .active(let location):
                        updateHover(at: location)
                    case .ended:
                        hoveredButton = nil
                    }
                }
                .onTapGesture(coordinateSpace: .local) { location in
                    handleTap(at: location)
                }
                .overlay {
                    // Tooltip for hovered button
                    if let buttonId = hoveredButton,
                       let bounds = boundingBoxes[buttonId],
                       let button = buttons[buttonId] {
                        ButtonTooltip(
                            label: button.label,
                            action: getAction(buttonId)
                        )
                        .position(x: bounds.midX, y: bounds.minY - 25)
                    }
                }
                .onAppear {
                    computeHitTestCache()
                }
                .onChange(of: transform) {
                    computeHitTestCache()
                }
        }
    }

    private func computeHitTestCache() {
        sortedButtonIds = buttons.keys.sorted(by: >)
        transformedPaths.removeAll(keepingCapacity: true)
        strokedPaths.removeAll(keepingCapacity: true)
        boundingBoxes.removeAll(keepingCapacity: true)

        for (id, button) in buttons {
            let path = button.path.applying(transform)
            transformedPaths[id] = path
            if hitTestStrokeWidth > 0 {
                let stroke = StrokeStyle(
                    lineWidth: hitTestStrokeWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
                strokedPaths[id] = path.strokedPath(stroke)
            }
            boundingBoxes[id] = path.boundingRect
        }
    }

    private func updateHover(at point: CGPoint) {
        for buttonId in sortedButtonIds {
            guard let bounds = boundingBoxes[buttonId] else { continue }
            // Early rejection: skip if point not in expanded bounding box
            let padding = max(hitTestStrokeWidth / 2, 0)
            let expandedBounds = bounds.insetBy(dx: -padding, dy: -padding)
            guard expandedBounds.contains(point) else { continue }

            guard let path = transformedPaths[buttonId] else { continue }
            let stroked = strokedPaths[buttonId]

            if path.contains(point) || (stroked?.contains(point) == true) {
                if hoveredButton != buttonId {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        hoveredButton = buttonId
                    }
                }
                return
            }
        }
        if hoveredButton != nil {
            withAnimation(.easeInOut(duration: 0.1)) {
                hoveredButton = nil
            }
        }
    }

    private func handleTap(at point: CGPoint) {
        for buttonId in sortedButtonIds {
            guard let bounds = boundingBoxes[buttonId] else { continue }
            let padding = max(hitTestStrokeWidth / 2, 0)
            let expandedBounds = bounds.insetBy(dx: -padding, dy: -padding)
            guard expandedBounds.contains(point) else { continue }

            guard let path = transformedPaths[buttonId] else { continue }
            let stroked = strokedPaths[buttonId]

            if path.contains(point) || (stroked?.contains(point) == true) {
                onEditButton?(buttonId)
                return
            }
        }
    }
}

// MARK: - Button Tooltip

private struct ButtonTooltip: View {
    let label: String
    let action: ActionDef?

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
            Text(ActionFormatter.format(action))
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(white: 0.15).opacity(0.95))
        .cornerRadius(6)
        .shadow(color: .black.opacity(0.3), radius: 4)
    }
}

// MARK: - Preview

#if DEBUG
struct ControllerVisualView_Previews: PreviewProvider {
    static var previews: some View {
        ControllerVisualView(
            controllerType: .dualSense,
            viewSide: .front,
            pressed: ["cross", "l1"],
            getAction: { _ in nil },
            onEditButton: nil
        )
        .frame(width: 600, height: 500)
        .background(Color(white: 0.15))
    }
}
#endif
