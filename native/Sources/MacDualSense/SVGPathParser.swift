import SwiftUI
import OSLog

private let svgLogger = os.Logger(subsystem: "com.sour4bh.cc-controller", category: "SVGPathParser")

/// Parses SVG path `d` attribute into SwiftUI Path
struct SVGPathParser {
    private static func parseDouble(_ token: String, at index: Int, command: String) -> Double {
        guard let value = Double(token) else {
            fatalError("Failed to parse coordinate '\(token)' at index \(index) in command '\(command)'")
        }
        return value
    }

    static func parse(_ pathData: String) -> Path {
        var path = Path()
        let commands = tokenize(pathData)
        var currentPoint = CGPoint.zero
        var lastControlPoint: CGPoint?
        var startPoint = CGPoint.zero

        var i = 0
        while i < commands.count {
            let cmd = commands[i]
            i += 1

            switch cmd {
            case "M": // Absolute moveto
                let x = parseDouble(commands[i], at: i, command: "M"); i += 1
                let y = parseDouble(commands[i], at: i, command: "M"); i += 1
                currentPoint = CGPoint(x: x, y: y)
                startPoint = currentPoint
                path.move(to: currentPoint)
                // Subsequent pairs are implicit lineto
                while i < commands.count, let x = Double(commands[i]) {
                    i += 1
                    let y = parseDouble(commands[i], at: i, command: "M"); i += 1
                    currentPoint = CGPoint(x: x, y: y)
                    path.addLine(to: currentPoint)
                }

            case "m": // Relative moveto
                let dx = parseDouble(commands[i], at: i, command: "m"); i += 1
                let dy = parseDouble(commands[i], at: i, command: "m"); i += 1
                currentPoint = CGPoint(x: currentPoint.x + dx, y: currentPoint.y + dy)
                startPoint = currentPoint
                path.move(to: currentPoint)

            case "L": // Absolute lineto
                while i < commands.count, let x = Double(commands[i]) {
                    i += 1
                    let y = parseDouble(commands[i], at: i, command: "L"); i += 1
                    currentPoint = CGPoint(x: x, y: y)
                    path.addLine(to: currentPoint)
                }

            case "l": // Relative lineto
                while i < commands.count, let dx = Double(commands[i]) {
                    i += 1
                    let dy = parseDouble(commands[i], at: i, command: "l"); i += 1
                    currentPoint = CGPoint(x: currentPoint.x + dx, y: currentPoint.y + dy)
                    path.addLine(to: currentPoint)
                }

            case "H": // Absolute horizontal
                let x = parseDouble(commands[i], at: i, command: "H"); i += 1
                currentPoint = CGPoint(x: x, y: currentPoint.y)
                path.addLine(to: currentPoint)

            case "h": // Relative horizontal
                let dx = parseDouble(commands[i], at: i, command: "h"); i += 1
                currentPoint = CGPoint(x: currentPoint.x + dx, y: currentPoint.y)
                path.addLine(to: currentPoint)

            case "V": // Absolute vertical
                let y = parseDouble(commands[i], at: i, command: "V"); i += 1
                currentPoint = CGPoint(x: currentPoint.x, y: y)
                path.addLine(to: currentPoint)

            case "v": // Relative vertical
                let dy = parseDouble(commands[i], at: i, command: "v"); i += 1
                currentPoint = CGPoint(x: currentPoint.x, y: currentPoint.y + dy)
                path.addLine(to: currentPoint)

            case "C": // Absolute cubic bezier
                while i + 5 < commands.count, let x1 = Double(commands[i]) {
                    i += 1
                    let y1 = parseDouble(commands[i], at: i, command: "C"); i += 1
                    let x2 = parseDouble(commands[i], at: i, command: "C"); i += 1
                    let y2 = parseDouble(commands[i], at: i, command: "C"); i += 1
                    let x = parseDouble(commands[i], at: i, command: "C"); i += 1
                    let y = parseDouble(commands[i], at: i, command: "C"); i += 1
                    let control1 = CGPoint(x: x1, y: y1)
                    let control2 = CGPoint(x: x2, y: y2)
                    currentPoint = CGPoint(x: x, y: y)
                    lastControlPoint = control2
                    path.addCurve(to: currentPoint, control1: control1, control2: control2)
                    // Check if next token is a number (implicit continuation)
                    if i >= commands.count || Double(commands[i]) == nil { break }
                }

            case "c": // Relative cubic bezier
                while i + 5 < commands.count, let dx1 = Double(commands[i]) {
                    i += 1
                    let dy1 = parseDouble(commands[i], at: i, command: "c"); i += 1
                    let dx2 = parseDouble(commands[i], at: i, command: "c"); i += 1
                    let dy2 = parseDouble(commands[i], at: i, command: "c"); i += 1
                    let dx = parseDouble(commands[i], at: i, command: "c"); i += 1
                    let dy = parseDouble(commands[i], at: i, command: "c"); i += 1
                    let control1 = CGPoint(x: currentPoint.x + dx1, y: currentPoint.y + dy1)
                    let control2 = CGPoint(x: currentPoint.x + dx2, y: currentPoint.y + dy2)
                    currentPoint = CGPoint(x: currentPoint.x + dx, y: currentPoint.y + dy)
                    lastControlPoint = control2
                    path.addCurve(to: currentPoint, control1: control1, control2: control2)
                    if i >= commands.count || Double(commands[i]) == nil { break }
                }

            case "S": // Smooth cubic bezier (absolute)
                while i + 3 < commands.count, let x2 = Double(commands[i]) {
                    i += 1
                    let y2 = parseDouble(commands[i], at: i, command: "S"); i += 1
                    let x = parseDouble(commands[i], at: i, command: "S"); i += 1
                    let y = parseDouble(commands[i], at: i, command: "S"); i += 1
                    // Reflect last control point
                    let control1 = lastControlPoint.map {
                        CGPoint(x: 2 * currentPoint.x - $0.x, y: 2 * currentPoint.y - $0.y)
                    } ?? currentPoint
                    let control2 = CGPoint(x: x2, y: y2)
                    currentPoint = CGPoint(x: x, y: y)
                    lastControlPoint = control2
                    path.addCurve(to: currentPoint, control1: control1, control2: control2)
                    if i >= commands.count || Double(commands[i]) == nil { break }
                }

            case "s": // Smooth cubic bezier (relative)
                while i + 3 < commands.count, let dx2 = Double(commands[i]) {
                    i += 1
                    let dy2 = parseDouble(commands[i], at: i, command: "s"); i += 1
                    let dx = parseDouble(commands[i], at: i, command: "s"); i += 1
                    let dy = parseDouble(commands[i], at: i, command: "s"); i += 1
                    let control1 = lastControlPoint.map {
                        CGPoint(x: 2 * currentPoint.x - $0.x, y: 2 * currentPoint.y - $0.y)
                    } ?? currentPoint
                    let control2 = CGPoint(x: currentPoint.x + dx2, y: currentPoint.y + dy2)
                    currentPoint = CGPoint(x: currentPoint.x + dx, y: currentPoint.y + dy)
                    lastControlPoint = control2
                    path.addCurve(to: currentPoint, control1: control1, control2: control2)
                    if i >= commands.count || Double(commands[i]) == nil { break }
                }

            case "Q": // Quadratic bezier (absolute)
                let x1 = parseDouble(commands[i], at: i, command: "Q"); i += 1
                let y1 = parseDouble(commands[i], at: i, command: "Q"); i += 1
                let x = parseDouble(commands[i], at: i, command: "Q"); i += 1
                let y = parseDouble(commands[i], at: i, command: "Q"); i += 1
                let control = CGPoint(x: x1, y: y1)
                currentPoint = CGPoint(x: x, y: y)
                path.addQuadCurve(to: currentPoint, control: control)

            case "q": // Quadratic bezier (relative)
                let dx1 = parseDouble(commands[i], at: i, command: "q"); i += 1
                let dy1 = parseDouble(commands[i], at: i, command: "q"); i += 1
                let dx = parseDouble(commands[i], at: i, command: "q"); i += 1
                let dy = parseDouble(commands[i], at: i, command: "q"); i += 1
                let control = CGPoint(x: currentPoint.x + dx1, y: currentPoint.y + dy1)
                currentPoint = CGPoint(x: currentPoint.x + dx, y: currentPoint.y + dy)
                path.addQuadCurve(to: currentPoint, control: control)

            case "A": // Absolute arc - skip rendering but track endpoint
                while i + 6 < commands.count, Double(commands[i]) != nil {
                    // Skip: rx, ry, x-axis-rotation, large-arc-flag, sweep-flag
                    for _ in 0..<5 { i += 1 }
                    // Parse endpoint
                    let x = parseDouble(commands[i], at: i, command: "A"); i += 1
                    let y = parseDouble(commands[i], at: i, command: "A"); i += 1
                    currentPoint = CGPoint(x: x, y: y)
                    lastControlPoint = currentPoint
                    svgLogger.debug("Arc command skipped, endpoint: (\(x), \(y))")
                    if i >= commands.count || Double(commands[i]) == nil { break }
                }

            case "a": // Relative arc - skip rendering but track endpoint
                while i + 6 < commands.count, Double(commands[i]) != nil {
                    // Skip: rx, ry, x-axis-rotation, large-arc-flag, sweep-flag
                    for _ in 0..<5 { i += 1 }
                    // Parse relative endpoint
                    let dx = parseDouble(commands[i], at: i, command: "a"); i += 1
                    let dy = parseDouble(commands[i], at: i, command: "a"); i += 1
                    currentPoint = CGPoint(x: currentPoint.x + dx, y: currentPoint.y + dy)
                    lastControlPoint = currentPoint
                    svgLogger.debug("Relative arc command skipped, endpoint: (\(currentPoint.x), \(currentPoint.y))")
                    if i >= commands.count || Double(commands[i]) == nil { break }
                }

            case "Z", "z": // Close path
                path.closeSubpath()
                currentPoint = startPoint

            default:
                fatalError("Unsupported SVG path command: \(cmd)")
            }
        }

        return path
    }

    /// Tokenize SVG path data into commands and numbers
    private static func tokenize(_ pathData: String) -> [String] {
        var tokens: [String] = []
        var current = ""

        for char in pathData {
            if char.isLetter {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                tokens.append(String(char))
            } else if char == "," || char == " " || char == "\n" || char == "\t" {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else if char == "-" && !current.isEmpty && !current.hasSuffix("e") {
                // Negative number starts new token (unless after exponent)
                tokens.append(current)
                current = String(char)
            } else {
                current.append(char)
            }
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }
}
