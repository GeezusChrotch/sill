import SwiftUI

struct VisionAppLauncher: View {
    @ObservedObject var client: StreamClient
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Open apps") {
                    ForEach(openApps, id: \.self) { bundle in
                        let windows = client.orderedWindows.filter { $0.bundleID == bundle }
                        if let first = windows.first, matches(first.appName) {
                            Button {
                                let current = windows.firstIndex { client.active == .window($0.id) }
                                let next = current.map { windows[($0 + 1) % windows.count] } ?? first
                                client.select(.window(next.id)); dismiss()
                            } label: { Label(first.appName + (windows.count > 1 ? " (\(windows.count) windows)" : ""), systemImage: "macwindow.on.rectangle") }
                        }
                    }
                }
                Section("All apps on your Mac") {
                    ForEach(client.apps.filter { matches($0.name) }) { app in
                        Button { client.launch(bundleID: app.bundleID); dismiss() } label: {
                            HStack {
                                if let icon = client.icons[app.bundleID] { Image(uiImage: icon).resizable().scaledToFit().frame(width: 32, height: 32) }
                                Text(app.name)
                            }
                        }
                    }
                    if client.apps.isEmpty { Text("Waiting for the Mac’s app catalog…").foregroundStyle(.secondary) }
                }
            }
            .searchable(text: $search, prompt: "Find a Mac app")
            .navigationTitle("Apps on \(client.macName)")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .frame(minWidth: 460, idealWidth: 560, minHeight: 450, idealHeight: 650)
    }
    private var openApps: [String] { var seen = Set<String>(); return client.orderedWindows.compactMap { seen.insert($0.bundleID).inserted ? $0.bundleID : nil } }
    private func matches(_ title: String) -> Bool { search.isEmpty || title.localizedCaseInsensitiveContains(search) }
}
