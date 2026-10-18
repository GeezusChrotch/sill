import SwiftUI
import StreamProtocol

/// Native spatial settings presentation, using the same optimistic/acknowledged ledger as iPad.
struct VisionHostSettings: View {
    @ObservedObject var client: StreamClient
    @Binding var textScale: Double?
    @Environment(\.dismiss) private var dismiss
    @AppStorage(StreamClient.gesturesKey) private var gesturesOn = true
    @AppStorage(StreamClient.clipboardKey) private var clipboardOn = false

    var body: some View {
        let clipboardSession = client.connectedAt
        NavigationStack {
            Form {
                if let state = client.settings.host, let shown = client.settings.displayed {
                    Section("Streaming from \(client.macName)") {
                        if let stream = state.stream {
                            Text("\(stream.width) × \(stream.height) · \(stream.fps) fps · \(stream.mbps) Mbps")
                                .font(.caption.monospacedDigit())
                            if stream.onVirtualDisplay { Label("On the virtual display", systemImage: "display") }
                        }
                        if let route = client.remoteRoute { Text("Connected \(route.phrase)") }
                        if let line = AwayCopy.headerLine(state.away) { Text(line.text) }
                        Picker("Quality", selection: value(shown.bitrate) { HostSettingsChange(bitrate: $0) }) {
                            ForEach(QualityPreset.allCases) { Text($0.title).tag($0.rawValue) }
                            if QualityPreset(rawValue: shown.bitrate) == nil {
                                Text(QualityPreset.title(forBitrate: shown.bitrate)).tag(shown.bitrate)
                            }
                        }
                        Picker("Resolution", selection: value(shown.captureScale) { HostSettingsChange(captureScale: $0) }) {
                            Text("Retina").tag(2.0); Text("Standard").tag(1.0)
                        }
                        Picker("Frame rate ceiling", selection: value(shown.maxFPS) { HostSettingsChange(maxFPS: $0) }) {
                            ForEach(SettingsChoices.maxFPS, id: \.self) { Text("\($0) fps").tag($0) }
                            if !SettingsChoices.maxFPS.contains(shown.maxFPS) { Text("\(shown.maxFPS) fps").tag(shown.maxFPS) }
                        }
                        Toggle("Prioritize encoding speed", isOn: value(shown.prioritizeSpeed) { HostSettingsChange(prioritizeSpeed: $0) })
                        Toggle("Virtual display", isOn: value(shown.virtualDisplay) { HostSettingsChange(virtualDisplay: $0) })
                            .disabled(!state.virtualDisplayAvailable && !shown.virtualDisplay)
                        if let note = state.virtualDisplayNote { Text(note).font(.caption) }
                        if let direct = shown.directWireless {
                            Toggle("Direct wireless connection", isOn: value(direct) { HostSettingsChange(directWireless: $0) })
                                .disabled(client.remoteRoute != nil)
                            Text(client.remoteRoute != nil ? "Change this on the Mac or from a nearby device." : client.connectedDirectly && direct ? "Turning this off disconnects this Vision Pro." : "Allows nearby devices to find this Mac without a shared network.")
                                .font(.caption)
                        }
                        Text("Changes apply to devices streaming from this Mac and may briefly restart the stream.")
                            .font(.caption)
                        if !state.persistent { Text("This host keeps settings until it quits.").font(.caption) }
                        if state.softwareEncoder { Label("Software encoding: streams are capped at Standard and 60 fps.", systemImage: "exclamationmark.triangle") }
                        if let recommendation = AwayCopy.callout(link: state.link, away: state.away, mac: client.macName) {
                            Text(recommendation.text)
                            if let action = recommendation.button { Button(action.title) { client.changeSettings(action.change) } }
                        }
                        if !client.settings.pending.isEmpty { ProgressView("Waiting for the Mac to confirm changes…") }
                        if let problem = client.settingsProblem { Text(problem).foregroundStyle(.orange) }
                    }
                } else {
                    Section("Streaming") { Text("Waiting for settings. Older Sill hosts may need an update to offer these controls.") }
                }
                Section("Mac actions") {
                    Toggle("Enable Mac gesture actions", isOn: $gesturesOn)
                    Text("Use the toolbar’s Mac actions for Mission Control, App Exposé, Spaces, Apps and Show Desktop. These switch to Desktop before showing the Mac’s system views.").font(.caption)
                }
                Section("Text size in the streamed window") {
                    Picker("Text size", selection: $textScale) {
                        Text("Preserve Mac size").tag(Optional<Double>.none)
                        ForEach([0.5, 0.75, 1, 1.25, 1.5], id: \.self) { Text($0.formatted(.percent)).tag(Optional($0)) }
                    }
                    Text("A size choice resizes the Mac window to fit this spatial window. Desktop capture keeps its size.").font(.caption)
                }
                Section("Clipboard on this Vision Pro") {
                    Toggle("Share text clipboard", isOn: $clipboardOn)
                        .onChange(of: clipboardOn) { _, _ in client.clipboardSwitchChanged() }
                    Text("Off until you enable it. Mac text is copied locally with a ten minute expiry. This device’s text is sent only when you tap Paste.").font(.caption)
                    if clipboardOn {
                        if ClipboardPolicy.hostTakes(client.hostClipboard) {
                            PasteButton(payloadType: String.self) { strings in DispatchQueue.main.async {
                                guard VisionSessionPolicy.acceptsCompletion(startedAt: clipboardSession, currentAt: client.connectedAt, connected: client.connected) else { return }
                                client.sendClipboard(strings)
                            } }
                                .accessibilityHint("Send text to the Mac clipboard. Use Command V on the Mac to paste it.")
                        } else { Text("Enable clipboard sharing in Sill on the Mac, or update the host.") }
                    }
                    if let note = client.clipboardNote { Text(note.text).foregroundStyle(note.warning ? .orange : .secondary) }
                }
            }
            .navigationTitle("Mac settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .frame(minWidth: 520, idealWidth: 600, minHeight: 500, idealHeight: 700)
    }

    // Actions alone send changes; host updates only refresh the displayed ledger values.
    private func value<V>(_ current: V, change: @escaping (V) -> HostSettingsChange) -> Binding<V> {
        Binding(get: { current }, set: { client.changeSettings(change($0)) })
    }
}
