import SwiftUI

/// A narrow sidebar uses a native popover so all text-size detents stay visible and selectable.
struct VisionTextSizePicker: View {
    @Binding var scale: Double?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Text size").font(.headline)
            Button("Preserve Mac size") { scale = nil; dismiss() }
            ForEach(TextScaleControl.steps, id: \.self) { value in
                Button {
                    scale = value
                    dismiss()
                } label: {
                    HStack {
                        Text(TextScaleControl.label(value) + "×")
                        Spacer()
                        if scale == value { Image(systemName: "checkmark") }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 260)
    }
}
