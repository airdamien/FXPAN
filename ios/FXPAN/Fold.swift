import ObjectiveC
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
                if max(box.width, box.height) > 40 { return box }
            }
            return nil
        }
    }
}

/// Read from the scene-delegate block, which is not on the main actor.
private enum FoldLock {
    nonisolated(unsafe) static var halfOpen = false
    nonisolated(unsafe) static var pad = false
    nonisolated(unsafe) static var installed = false

    static func mask() -> UInt {
        if halfOpen { return UIInterfaceOrientationMask.portrait.rawValue | UIInterfaceOrientationMask.portraitUpsideDown.rawValue }
        if pad { return UIInterfaceOrientationMask.all.rawValue }
        return UIInterfaceOrientationMask.allButUpsideDown.rawValue
    }
}

/// Portrait only while the Duo is half open. A phone and the cover screen keep both landscapes.
@MainActor
enum FoldOrientation {
    static var halfOpen = false

    static var mask: UIInterfaceOrientationMask {
        if halfOpen { return [.portrait, .portraitUpsideDown] }
        return UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
    }

    /// SwiftUI installs its own scene delegate and ignores a replacement, so the orientation method has to be added there.
    static func install() {
        guard !FoldLock.installed else { return }
        guard let cls = NSClassFromString("SwiftUI.AppSceneDelegate") else { return }
        FoldLock.pad = UIDevice.current.userInterfaceIdiom == .pad
        let sel = NSSelectorFromString("supportedInterfaceOrientationsForWindowScene:")
        let block: @convention(block) (AnyObject, UIWindowScene) -> UInt = { _, _ in
            FoldLock.mask()
        }
        let imp = imp_implementationWithBlock(block)
        if let existing = class_getInstanceMethod(cls, sel) {
            method_setImplementation(existing, imp)
        } else {
            class_addMethod(cls, sel, imp, "Q@:@")
        }
        FoldLock.installed = true
    }

    static func update(halfOpen: Bool) {
        install()
        self.halfOpen = halfOpen
        FoldLock.halfOpen = halfOpen
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            let turned = scene.interfaceOrientation == .landscapeLeft || scene.interfaceOrientation == .landscapeRight
            guard halfOpen, turned else { continue }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
        }
    }
}

final class FoldScene: NSObject, UIWindowSceneDelegate {
    @available(iOS 27.0, *)
    func supportedInterfaceOrientations(for windowScene: UIWindowScene) -> UIInterfaceOrientationMask {
        FoldOrientation.mask
    }
}
