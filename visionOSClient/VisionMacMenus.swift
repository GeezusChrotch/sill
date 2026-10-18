import SwiftUI
import UIKit

/// A native button with the upstream uncached deferred menu provider: fetch only opened branches.
struct VisionMacMenus: UIViewRepresentable {
    @ObservedObject var client: StreamClient
    @Binding var open: Bool

    func makeUIView(context: Context) -> VisionMacMenuButton {
        let button = VisionMacMenuButton(type: .system)
        button.showsMenuAsPrimaryAction = true
        button.preferredMenuElementOrder = .fixed
        button.configuration = .bordered()
        updateUIView(button, context: context)
        return button
    }
    func updateUIView(_ button: VisionMacMenuButton, context: Context) {
        button.setTitle("Mac menus", for: .normal)
        button.accessibilityLabel = "\(client.menus.app ?? "Mac") menus"
        button.isEnabled = client.menus.hasMenus
        let binding = $open
        button.changed = { value in DispatchQueue.main.async { binding.wrappedValue = value } }
        if button.top != client.menus.top {
            button.top = client.menus.top
            button.menu = UIMenu(children: MacMenuElements.topMenus(client, barIdentifiers: false))
        }
    }
}
