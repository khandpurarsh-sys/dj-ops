import Foundation

/** Dock flip geometry, pure for tests (Android MainActivity.dockStaysGlass parity): glass
 *  (over-video) only while the hero's bottom edge is still clear of the dock; solid navy
 *  the moment white content reaches it. The dock floats 18pt up; the 22pt margin absorbs
 *  scroll-frame/render lag - flip at 40pt before contact. */
func dockStaysGlass(heroBottom: CGFloat?, viewportEnd: CGFloat, dockTouchPx: CGFloat) -> Bool {
    guard let heroBottom else { return false }
    return heroBottom > viewportEnd - dockTouchPx
}
