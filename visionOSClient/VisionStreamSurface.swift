import SwiftUI
import StreamProtocol

/// Input positions use the letterboxed picture, not the surrounding spatial window.
struct VisionStreamSurface: View {
    @ObservedObject var client: StreamClient
    var captureEnabled = true
    var keyboardEnabled = false
    var textScale: Double? = nil
    @Environment(\.scenePhase) private var scenePhase
    @State private var mode = InputMode.click
    @State private var rightClick = false
    @State private var shift = false
    @State private var control = false
    @State private var option = false
    @State private var command = false
    @State private var lastPoint = CGPoint(x: 0.5, y: 0.5)
    @State private var pointerDown: PointerAction?
    @State private var heldModifiers: KeyModifiers = []
    @State private var scrolling = false
    @State private var tracking = false
    @State private var pad = PadCursor()
    @State private var trackpadDrag = false
    @State private var momentum = VisionScrollMomentum()
    @State private var viewportTask: Task<Void, Never>?
    @State private var lastTranslation = CGSize.zero
    @GestureState private var gestureActive = false

    private enum InputMode: String, CaseIterable, Identifiable {
        case click = "Click", drag = "Drag", scroll = "Scroll", trackpad = "Trackpad"
        var id: Self { self }
    }

    private var enabled: Bool { captureEnabled && !client.inputPaused && client.connected && scenePhase == .active }
    private var modifiers: KeyModifiers {
        var value: KeyModifiers = []
        if shift { value.insert(.shift) }
        if control { value.insert(.control) }
        if option { value.insert(.option) }
        if command { value.insert(.command) }
        return value
    }

    var body: some View {
        let inputSession = client.connectedAt
        VStack(spacing: 12) {
            GeometryReader { geometry in
                StreamView(client: client)
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { value in
                        guard enabled, mode == .click || mode == .trackpad else { return }
                        let point: CGPoint
                        if mode == .trackpad {
                            let feed = client.pointerFeedState
                            pad.catchUp(anchor: feed.anchor, reseeds: feed.reseeds)
                            point = pad.cursor
                        } else {
                            guard let hit = normalized(value.location, size: geometry.size, clamped: false) else { return }
                            point = hit
                        }
                        beginPointer(at: point)
                        releaseInput()
                    })
                    .simultaneousGesture(DragGesture(minimumDistance: mode == .drag ? 0 : 8)
                        .updating($gestureActive) { _, active, _ in active = true }
                        .onChanged { value in
                            guard enabled, mode != .click else { return }
                            if !tracking {
                                momentum.stop()
                                guard let start = normalized(value.startLocation, size: geometry.size, clamped: false) else { return }
                                lastTranslation = .zero
                                tracking = true
                                if mode == .trackpad {
                                    let feed = client.pointerFeedState
                                    pad.adopt(anchor: feed.anchor, reseeds: feed.reseeds)
                                    if trackpadDrag { beginPointer(at: pad.cursor); tracking = true }
                                } else if mode == .drag { beginPointer(at: start); tracking = true }
                                else {
                                    lastPoint = start
                                    scrolling = true
                                    client.sendInput(.scrollGesture(.began, x: start.x, y: start.y))
                                }
                            }
                            if mode == .trackpad {
                                let feed = client.pointerFeedState
                                pad.catchUp(anchor: feed.anchor, reseeds: feed.reseeds)
                                let rect = pictureRect(geometry.size)
                                guard rect.width > 0, rect.height > 0 else { return }
                                pad.move(dx: (value.translation.width - lastTranslation.width) / rect.width,
                                         dy: (value.translation.height - lastTranslation.height) / rect.height)
                                lastPoint = pad.cursor
                                client.setOwnPointer(lastPoint, from: .trackpad)
                                client.sendInput(.pointer(.move, x: lastPoint.x, y: lastPoint.y))
                                lastTranslation = value.translation
                                return
                            }
                            guard let point = normalized(value.location, size: geometry.size, clamped: true) else { return }
                            lastPoint = point
                            client.setOwnPointer(point, from: .trackpad)
                            if pointerDown != nil {
                                client.sendInput(.pointer(.move, x: point.x, y: point.y))
                            } else if scrolling {
                                let rect = pictureRect(geometry.size)
                                guard rect.width > 0, rect.height > 0 else { return }
                                let dx = (value.translation.width - lastTranslation.width) / rect.width
                                let dy = (value.translation.height - lastTranslation.height) / rect.height
                                client.sendInput(.scroll(x: point.x, y: point.y, dx: dx, dy: dy))
                            }
                            lastTranslation = value.translation
                        }
                        .onEnded { value in
                            let shouldCoast = enabled && mode == .scroll && scrolling
                            let point = lastPoint
                            let rect = pictureRect(geometry.size)
                            let session = client.connectedAt
                            releaseInput()
                            if shouldCoast, rect.width > 0, rect.height > 0 {
                                momentum.start(velocity: CGPoint(x: value.velocity.width, y: value.velocity.height), onBegin: {
                                    client.sendInput(.scrollGesture(.momentumBegan, x: point.x, y: point.y))
                                }, onStep: { delta in
                                    guard VisionSessionPolicy.acceptsCompletion(startedAt: session, currentAt: client.connectedAt, connected: client.connected), !client.inputPaused else { return }
                                    client.sendInput(.scroll(x: point.x, y: point.y, dx: delta.x / rect.width, dy: delta.y / rect.height))
                                }, onEnd: {
                                    guard VisionSessionPolicy.acceptsCompletion(startedAt: session, currentAt: client.connectedAt, connected: client.connected) else { return }
                                    client.sendInput(.scrollGesture(.momentumEnded, x: point.x, y: point.y))
                                })
                            }
                        }, including: mode == .click ? .none : .all)
                    .background {
                        VisionKeyboardCapture(enabled: enabled && keyboardEnabled, source: client.active,
                                              modifiers: modifiers, consumeModifiers: clearModifiers, send: { event in
                            send(event, for: inputSession)
                        })
                            .frame(width: 1, height: 1)
                            .accessibilityHidden(true)
                    }
                    .background {
                        VisionHardwarePointer(displayView: client.displayView, videoSize: client.videoSize,
                                              enabled: enabled, source: client.active, momentum: momentum, send: { event in
                            guard VisionSessionPolicy.acceptsCompletion(startedAt: inputSession, currentAt: client.connectedAt, connected: client.connected) else { return }
                            client.setOwnPointer(nil, from: .none)
                            client.sendInput(event)
                        }, pointerBegan: {
                            guard VisionSessionPolicy.acceptsCompletion(startedAt: inputSession, currentAt: client.connectedAt, connected: client.connected) else { return }
                            releaseInput()
                            heldModifiers = modifiers
                            KeyChord.modifiersDown(heldModifiers).forEach(client.sendInput)
                        }, pointerEnded: {
                            if VisionSessionPolicy.acceptsCompletion(startedAt: inputSession, currentAt: client.connectedAt, connected: client.connected) {
                                KeyChord.modifiersUp(heldModifiers).forEach(client.sendInput)
                            }
                            heldModifiers = []; clearModifiers()
                        }).frame(width: 1, height: 1).accessibilityHidden(true)
                    }
                    .onAppear { client.setPointerLayout(portrait: true); reportViewport(geometry.size) }
                    .onChange(of: client.connectedAt) { _, _ in reportViewport(geometry.size) }
                    .onChange(of: client.remoteRoute) { _, _ in reportViewport(geometry.size) }
                    .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in reportViewport(geometry.size) }
                    .onChange(of: geometry.size) { _, size in reportViewport(size) }
                    .onChange(of: textScale) { _, _ in reportViewport(geometry.size) }
                    .onChange(of: client.active) { _, _ in
                        releaseInput(); clearModifiers()
                        reportViewport(geometry.size)
                    }
            }
            .background(.black, in: RoundedRectangle(cornerRadius: 12))
            ViewThatFits(in: .horizontal) {
                HStack { pointerControls; modifierControls }
                VStack { pointerControls; modifierControls }
            }
            .disabled(!enabled)
            ScrollView(.horizontal) {
                HStack {
                    keyButton("Escape", usage: 0x29)
                    keyButton("Tab", usage: 0x2B)
                    keyButton("Return", usage: 0x28)
                    keyButton("Delete", usage: 0x2A)
                    keyButton("←", usage: 0x50, accessibility: "Left arrow")
                    keyButton("↑", usage: 0x52, accessibility: "Up arrow")
                    keyButton("↓", usage: 0x51, accessibility: "Down arrow")
                    keyButton("→", usage: 0x4F, accessibility: "Right arrow")
                }
            }
            .disabled(!enabled)
            Text("Click pinches once; Drag holds the mouse; Scroll moves content; Trackpad moves the pointer relative to your hand. Modifiers are consumed by the next click or key button.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: gestureActive) { _, active in if !active && tracking { releaseInput() } }
        .onChange(of: enabled) { _, active in if !active { releaseInput(); clearModifiers() } }
        .onChange(of: mode) { _, _ in releaseInput(); clearModifiers() }
        .onChange(of: rightClick) { _, _ in releaseInput() }
        .onDisappear { viewportTask?.cancel(); releaseInput(); client.setOwnPointer(nil, from: .none) }
        .padding(.horizontal)
    }

    private var pointerControls: some View {
        HStack {
            Picker("Pointer mode", selection: $mode) {
                ForEach(InputMode.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).frame(minWidth: 260)
            Toggle("Right click", isOn: $rightClick).toggleStyle(.button)
            if mode == .trackpad { Toggle("Drag while moving", isOn: $trackpadDrag).toggleStyle(.button) }
        }
    }

    private var modifierControls: some View {
        HStack {
            Toggle("Shift", isOn: $shift)
            Toggle("Control", isOn: $control)
            Toggle("Option", isOn: $option)
            Toggle("Command", isOn: $command)
        }
        .toggleStyle(.button)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pointer and key button modifiers")
    }

    private func keyButton(_ title: String, usage: UInt16, accessibility: String? = nil) -> some View {
        Button(title) {
            guard enabled else { return }
            releaseInput()
            KeyChord.press(usage, with: modifiers).forEach(client.sendInput)
            clearModifiers()
        }.accessibilityLabel(accessibility ?? title)
    }

    private func beginPointer(at point: CGPoint) {
        releaseInput()
        lastPoint = point
        client.setOwnPointer(point, from: .trackpad)
        heldModifiers = modifiers
        KeyChord.modifiersDown(heldModifiers).forEach(client.sendInput)
        client.sendInput(.pointer(.move, x: point.x, y: point.y))
        let down: PointerAction = rightClick ? .rightDown : .leftDown
        pointerDown = down
        client.sendInput(.pointer(down, x: point.x, y: point.y))
    }

    private func releaseInput() {
        momentum.stop()
        if let down = pointerDown {
            client.sendInput(.pointer(down == .rightDown ? .rightUp : .leftUp, x: lastPoint.x, y: lastPoint.y))
            pointerDown = nil
            clearModifiers()
        }
        if scrolling {
            client.sendInput(.scrollGesture(.ended, x: lastPoint.x, y: lastPoint.y))
            scrolling = false
        }
        KeyChord.modifiersUp(heldModifiers).forEach(client.sendInput)
        heldModifiers = []
        lastTranslation = .zero
        tracking = false
    }

    private func clearModifiers() { shift = false; control = false; option = false; command = false }

    private func pictureRect(_ size: CGSize) -> CGRect {
        guard client.videoSize.width > 0, client.videoSize.height > 0 else { return .zero }
        let scale = min(size.width / client.videoSize.width, size.height / client.videoSize.height)
        let width = client.videoSize.width * scale, height = client.videoSize.height * scale
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    private func normalized(_ point: CGPoint, size: CGSize, clamped: Bool) -> CGPoint? {
        let bounds = CGRect(origin: .zero, size: size)
        if !clamped { return VisionInputGeometry.normalized(point, bounds: bounds, videoSize: client.videoSize) }
        let rect = pictureRect(size)
        guard rect.width > 0, rect.height > 0 else { return nil }
        return CGPoint(x: min(max((point.x - rect.minX) / rect.width, 0), 1),
                       y: min(max((point.y - rect.minY) / rect.height, 0), 1))
    }

    private func send(_ event: InputEvent, for session: Date?) {
        guard VisionSessionPolicy.acceptsCompletion(startedAt: session, currentAt: client.connectedAt, connected: client.connected) else { return }
        client.sendInput(event)
    }

    private func reportViewport(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        viewportTask?.cancel()
        let session = client.connectedAt
        viewportTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, VisionSessionPolicy.acceptsCompletion(startedAt: session, currentAt: client.connectedAt, connected: client.connected) else { return }
            client.sendViewport(Viewport(width: size.width, height: size.height, scale: textScale,
                                         fps: StreamClient.wantedFPS(remote: client.awayCapsFrameRate)))
        }
    }
}
