import SwiftUI

/// Small helper to allow configuring the UINavigationController from SwiftUI
/// Usage: .background(NavigationConfigurator { nav in nav.interactivePopGestureRecognizer?.isEnabled = false })
struct NavigationConfigurator: UIViewControllerRepresentable {
    var configure: (UINavigationController) -> Void = { _ in }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if let nc = uiViewController.navigationController {
            configure(nc)
        }
    }
}
