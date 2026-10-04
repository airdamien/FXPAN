import SwiftUI

private struct HalfOpenKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The view is on the lower half of a half-open Duo. The upper half already shows the live panorama.
    var halfOpen: Bool {
        get { self[HalfOpenKey.self] }
        set { self[HalfOpenKey.self] = newValue }
    }
}

/// A live panorama on a settings screen. Half-open leaves it out, because that picture is already on the other half.
struct LivePanel<Content: View>: View {
    @Environment(\.halfOpen) private var halfOpen
    @ViewBuilder var content: () -> Content

    var body: some View {
        if !halfOpen {
            content()
        }
    }
}

/// The hinge in book posture. Top is the picture, the gap is the fold, and bottom is the controls.
struct BookSplit: Equatable {
    var top: CGFloat
    var hinge: CGFloat
    var bottom: CGFloat

    /// A real division from UIKit when the device is half folded. A window that is simply two panels tall, or the Duo's tall inner screen, uses the same split so the picture lands on top and the controls sit below.
    static func resolve(division: CGRect?, size: CGSize) -> BookSplit? {
        if let division, division.width > size.width * 0.55, division.height < size.height * 0.3 {
            let top = division.minY
            let bottom = size.height - division.maxY
            if top > 80, bottom > 80 {
                return BookSplit(top: top, hinge: max(division.height, 0), bottom: bottom)
            }
        }
        let book = size.width < 560 && size.height > size.width * 2.5
        let duo = size.width > 500 && size.width < 760 && size.height > size.width && size.height < size.width * 2.2
        guard book || duo else { return nil }
        let hinge: CGFloat = book ? 16 : 0
        let top = (size.height - hinge) / 2
        return BookSplit(top: top, hinge: hinge, bottom: size.height - top - hinge)
    }
}

/// Reads the fold reserved region. The band is the hinge; it is empty when the Duo is open or closed flat.
struct FoldProbe: UIViewRepresentable {
    @Binding var division: CGRect?

    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: Probe, context: Context) {
        uiView.onChange = { division = $0 }
        uiView.report()
    }

    final class Probe: UIView {
        var onChange: ((CGRect?) -> Void)?
        private var last: CGRect?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        func report() {
            let next = hinge()
            if next == last { return }
            last = next
            onChange?(next)
        }

        /// `reservedRegions(kind:)` exists only in the iOS 27.1 SDK. The selector is the same method, so a build from the previous Xcode still compiles and a Duo on 27.1 still reports the hinge.
        private func hinge() -> CGRect? {
            let list = NSSelectorFromString("reservedRegionsOfKind:")
            guard responds(to: list) else { return nil }
            guard let kindClass = NSClassFromString("UIViewReservedRegionKind") as? NSObject.Type else { return nil }
            let make = NSSelectorFromString("divisionRegionKind")
            guard (kindClass as AnyObject).responds(to: make) else { return nil }
            guard let kind = (kindClass as AnyObject).perform(make)?.takeUnretainedValue() else { return nil }
            guard let regions = perform(list, with: kind)?.takeUnretainedValue() as? [NSObject] else { return nil }
            for region in regions {
                guard (region.value(forKey: "active") as? Bool) == true else { continue }
                guard let box = (region.value(forKey: "frame") as? NSValue)?.cgRectValue else { continue }
                if box.width >= box.height, box.width > 40 { return box }
            }
            return nil
        }
    }
}
