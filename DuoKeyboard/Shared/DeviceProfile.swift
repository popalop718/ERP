import UIKit

/// Physical description of the screen the keyboard is on, with exact profiles for
/// iPhone Duo (from apple.com/iphone-duo/specs):
///   • Inner: 7.6" folding OLED, 1878 × 2670 px, 430 ppi — unfolded 164.6 × 117.8 mm.
///   • Outer: 5.4" OLED, 1398 × 2034 px, 460 ppi — folded 84.1 × 117.8 mm.
/// The hinge folds the inner display across the middle of its long side, so the
/// crease is perpendicular to the long axis at its midpoint in every orientation.
struct DeviceProfile: Equatable {
    enum Display: String { case duoInner, duoOuter, other }

    enum Crease: Equatable {
        /// Inner display held wide (book pose): crease runs top-to-bottom at screen x.
        case vertical(x: CGFloat)
        /// Inner display held tall (tabletop/laptop pose): crease runs across at screen y.
        case horizontal(y: CGFloat)
    }

    let display: Display
    let ppi: CGFloat
    /// Points per millimetre on this screen (accounts for Display Zoom).
    let pointsPerMM: CGFloat

    static let duoInnerPixels = (short: CGFloat(1878), long: CGFloat(2670))
    static let duoOuterPixels = (short: CGFloat(1398), long: CGFloat(2034))

    static func current(for screen: UIScreen) -> DeviceProfile {
        let n = screen.nativeBounds.size
        let short = min(n.width, n.height), long = max(n.width, n.height)
        func matches(_ p: (short: CGFloat, long: CGFloat)) -> Bool { abs(short - p.short) <= 4 && abs(long - p.long) <= 4 }
        let display: Display
        let ppi: CGFloat
        if matches(duoInnerPixels) { display = .duoInner; ppi = 430 }
        else if matches(duoOuterPixels) { display = .duoOuter; ppi = 460 }
        else { display = .other; ppi = UIDevice.current.userInterfaceIdiom == .pad ? 264 : 460 }
        let scale = max(screen.nativeScale, 1)
        return DeviceProfile(display: display, ppi: ppi, pointsPerMM: ppi / 25.4 / scale)
    }

    var isDuo: Bool { display != .other }

    var displayName: String {
        switch display {
        case .duoInner: return "iPhone Duo — inner display (7.6\")"
        case .duoOuter: return "iPhone Duo — outer display (5.4\")"
        case .other: return "Not an iPhone Duo display"
        }
    }

    /// Where the fold is, in screen coordinates for the current orientation.
    func crease(screenBounds b: CGRect) -> Crease? {
        guard display == .duoInner else { return nil }
        return b.width >= b.height ? .vertical(x: b.midX) : .horizontal(y: b.midY)
    }

    func points(mm: CGFloat) -> CGFloat { mm * pointsPerMM }

    /// Converts a size designed for a 460 ppi @3x iPhone into the same physical size here.
    func physical(_ referencePoints: CGFloat) -> CGFloat {
        let referencePerMM: CGFloat = 460 / 25.4 / 3
        return referencePoints / referencePerMM * pointsPerMM
    }
}
