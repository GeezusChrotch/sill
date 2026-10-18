import SwiftUI

struct VisionHelp: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Connect") { Text("Open Sill on your Mac and allow Screen Recording and Accessibility. Select the Mac here. Pair with the code shown on the Mac, an address and code, or a sill pairing link. Remote access needs a paired Mac and its VPN or internet route enabled in Sill on the Mac.") }
                Section("Windows and apps") { Text("Choose a window preview or Desktop in the sidebar. Use Apps to launch installed Mac apps. Window Actions offers minimize, full screen, close and order controls. The Mac host shares one active source with its other Sill clients.") }
                Section("Pointer") { Text("Click pinches at the picture. Drag holds the mouse while your hand moves. Scroll moves the content. Trackpad moves the pointer relatively; enable Drag while moving for a relative drag. Right click changes the mouse button. A click or key consumes the on-screen modifiers.") }
                Section("Keyboard") { Text("Tap Keyboard in the toolbar to show the system keyboard and direct typing to the Mac. Tap it again to release typing. A compatible Mac host can also open it after confirming that your latest click targeted an editable field. Command, Control and Option combine with a single typed shortcut key. Local search, forms, sheets and menus suspend forwarding. Test your keyboard layout, IME and dictation on a headset before relying on them.") }
                Section("Settings and privacy") { Text("Mac settings changes are acknowledged by the host and may restart its stream. Text size changes resize the Mac window. Clipboard sharing is off initially; enable it in Settings. Mac text is written only locally and expires after ten minutes. Sending this device’s clipboard requires tapping Paste. A receipt confirms the Mac received it.") }
                Section("Current limits") { Text("Camera QR scanning, Pencil and Duo fold layouts have no equivalent here. Audio and independent streams for each spatial window are not supported by the current host. Hardware mouse/trackpad hover, wheel and secondary-button recognizers are included; their coexistence with spatial gestures still needs physical acceptance.") }
            }
            .navigationTitle("Using Sill in your space")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.frame(minWidth: 500, idealWidth: 600, minHeight: 500, idealHeight: 680)
    }
}
