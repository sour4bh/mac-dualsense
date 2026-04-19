import CoreGraphics

enum DualSenseVisuals {
    static let frontResourceName = "DualSense_front"
    static let backResourceName = "DualSense_back"
    static let frontViewBox = CGRect(x: 55, y: 40, width: 590, height: 410)
    static let backViewBox = CGRect(x: 55, y: 450, width: 590, height: 305)

    // Back SVG parent group uses translate(0, 1205) scale(1, -1); apply it to hit paths.
    static let backFlipTransform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 1205)
}
