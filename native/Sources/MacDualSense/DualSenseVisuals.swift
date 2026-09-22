import CoreGraphics

enum DualSenseVisuals {
    static let frontResourceName = "DualSense_front"
    static let backResourceName = "DualSense_back"
    static let frontViewBox = CGRect(x: 55, y: 40, width: 590, height: 410)
    static let backViewBox = CGRect(x: 55, y: 450, width: 590, height: 305)

    static let backFlipTransform = CGAffineTransform.identity
}
