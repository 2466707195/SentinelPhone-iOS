import SwiftUI
import UIKit

/// 全局方向锁：默认只允许竖屏；机位全屏预览打开时临时允许横竖屏。
final class OrientationLock: ObservableObject {

    static let shared = OrientationLock()

    private init() {}

    var isLandscapeAllowed = false {
        didSet {
            DispatchQueue.main.async {
                UIViewController.attemptRotationToDeviceOrientation()
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationLock.shared.isLandscapeAllowed ? .all : .portrait
    }
}
