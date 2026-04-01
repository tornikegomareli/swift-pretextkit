import UIKit
import PretextKit

let isPad: Bool = UIDevice.current.userInterfaceIdiom == .pad

struct Orb {
    var position: CGPoint
    var velocity: CGPoint
    var radius: CGFloat
    var color: (r: Double, g: Double, b: Double)
}

struct FloatingElement {
    var frame: CGRect
    let cornerRadius: CGFloat
    let color: UIColor
    let label: String
    let fontSize: CGFloat
    let isCircle: Bool
    let padding: CGFloat
}
