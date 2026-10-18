import SwiftUI
import UIKit
import StreamProtocol

/// An explicitly enabled keyboard destination, separate from local SwiftUI text fields.
/// It requests focus only on an enable transition/window attachment, never on every view update.
struct VisionKeyboardCapture: UIViewRepresentable {
    var enabled: Bool
    var source: StreamSource
    var modifiers: KeyModifiers = []
    var consumeModifiers: () -> Void = {}
    var send: (InputEvent) -> Void

    func makeUIView(context: Context) -> VisionKeyboardView {
        let view = VisionKeyboardView()
        view.modifiers = modifiers
        view.consumeModifiers = consumeModifiers
        view.send = send
        view.captureEnabled = enabled
        view.source = source
        return view
    }

    func updateUIView(_ view: VisionKeyboardView, context: Context) {
        // Releases must use the old destination before replacing its closure.
        if view.source != source { view.releaseKeys(); view.source = source }
        view.modifiers = modifiers
        view.consumeModifiers = consumeModifiers
        view.send = send
        view.setCaptureEnabled(enabled)
    }

    static func dismantleUIView(_ view: VisionKeyboardView, coordinator: ()) {
        view.setCaptureEnabled(false)
    }
}

final class VisionKeyboardView: UIView, UIKeyInput {
    var send: (InputEvent) -> Void = { _ in }
    var source: StreamSource = .none
    var captureEnabled = false
    private var forwarded = ForwardedKeys()
    var modifiers: KeyModifiers = []
    var consumeModifiers: () -> Void = {}
    override var canBecomeFirstResponder: Bool { captureEnabled }
    override var editingInteractionConfiguration: UIEditingInteractionConfiguration { .none }
    var hasText: Bool { true }
    @objc var autocorrectionType: UITextAutocorrectionType = .no
    @objc var autocapitalizationType: UITextAutocapitalizationType = .none
    @objc var smartQuotesType: UITextSmartQuotesType = .no
    @objc var smartDashesType: UITextSmartDashesType = .no

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, captureEnabled { becomeFirstResponder() }
        else { releaseKeys() }
    }

    func setCaptureEnabled(_ enabled: Bool) {
        guard captureEnabled != enabled else { return }
        captureEnabled = enabled
        if enabled, window != nil { becomeFirstResponder() }
        else if !enabled { releaseKeys(); resignFirstResponder() }
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { releaseKeys() }
        return resigned
    }

    func releaseKeys() { forwarded.releaseAll().forEach(send) }
    func insertText(_ text: String) {
        guard captureEnabled, isFirstResponder else { return }
        VisionTextInput.events(text, modifiers: modifiers).forEach(send)
        modifiers = []; consumeModifiers()
    }
    func deleteBackward() {
        guard captureEnabled, isFirstResponder else { return }
        if !modifiers.isDisjoint(with: .shortcutMakers) {
            KeyChord.press(0x2A, with: modifiers).forEach(send)
        } else { send(.text("\u{8}")) }
        modifiers = []; consumeModifiers()
    }

    // Escape may be intercepted by the text system before pressesBegan. Use the shared
    // deduplication path so systems delivering both channels still emit exactly one press.
    override var keyCommands: [UIKeyCommand]? {
        guard captureEnabled, isFirstResponder else { return super.keyCommands }
        return (super.keyCommands ?? []) + (0..<16).map { mask in
            var flags = UIKeyModifierFlags()
            for (bit, flag) in [UIKeyModifierFlags.shift, .control, .alternate, .command].enumerated()
                where mask & (1 << bit) != 0 { flags.insert(flag) }
            let command = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: flags,
                                       action: #selector(escapeCommand(_:)))
            command.wantsPriorityOverSystemBehavior = true
            return command
        }
    }

    @objc private func escapeCommand(_ command: UIKeyCommand) {
        guard captureEnabled, isFirstResponder else { return }
        forwarded.commanded(0x29, modifiers: UInt64(command.modifierFlags.rawValue),
                            at: ProcessInfo.processInfo.systemUptime).forEach(send)
    }

    private func forward(_ presses: Set<UIPress>, down: Bool) -> Set<UIPress> {
        guard captureEnabled, isFirstResponder else { return presses }
        var unhandled: Set<UIPress> = []
        for press in presses {
            guard let key = press.key else { unhandled.insert(press); continue }
            let usage = UInt16(key.keyCode.rawValue)
            let result = down
                ? forwarded.pressed(usage, modifiers: UInt64(key.modifierFlags.rawValue), at: press.timestamp)
                : forwarded.released(usage)
            switch result {
            case .send(let event): send(event)
            case .swallow: break
            case .text: unhandled.insert(press)
            }
        }
        return unhandled
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let rest = forward(presses, down: true)
        if !rest.isEmpty { super.pressesBegan(rest, with: event) }
    }
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let rest = forward(presses, down: false)
        if !rest.isEmpty { super.pressesEnded(rest, with: event) }
    }
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let rest = forward(presses, down: false)
        releaseKeys()
        if !rest.isEmpty { super.pressesCancelled(rest, with: event) }
    }
}
