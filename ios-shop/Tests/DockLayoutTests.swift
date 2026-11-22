import XCTest
import SwiftUI
@testable import DressJetShop

/** Device-size layout gate: the Menu slot and the capsule must sit exactly on the screen's
 *  vertical centre line (430pt-wide window), expanded and minimised. */
final class DockLayoutTests: XCTestCase {
    final class Box { var f: [String: CGRect] = [:] }

    private func frames(mini: Bool, width: CGFloat) -> [String: CGRect] {
        let box = Box()
        let root = ZStack(alignment: .bottom) {
            Color.clear
            Dock(current: "home", bagCount: 3, dark: false, mini: mini, onHome: {}, onMenu: {}, onBag: {})
                .padding(.bottom, 18)
        }
        .frame(width: width, height: 932)
        .onPreferenceChange(DockFramesKey.self) { box.f = $0 }
        let vc = UIHostingController(rootView: root)
        let w = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 932))
        w.rootViewController = vc; w.makeKeyAndVisible()
        vc.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        return box.f
    }

    func testMenuAndCapsuleAreCentred() {
        for width in [393.0, 430.0] {
            for mini in [false, true] {
                let f = frames(mini: mini, width: width)
                let mid = width / 2
                guard let m = f["menu"], let c = f["capsule"] else { return XCTFail("no frames w=\(width) mini=\(mini)") }
                print("DOCKCHECK w=\(width) mini=\(mini) menuMidX=\(m.midX) capsuleMidX=\(c.midX) capsuleW=\(c.width) mid=\(mid)")
                XCTAssertEqual(m.midX, mid, accuracy: 0.75, "Menu off centre w=\(width) mini=\(mini)")
                XCTAssertEqual(c.midX, mid, accuracy: 0.75, "capsule off centre w=\(width) mini=\(mini)")
            }
        }
    }
}
