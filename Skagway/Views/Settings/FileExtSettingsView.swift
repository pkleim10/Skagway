import SwiftUI

struct FileExtSettingsView: View {
    @Bindable private var manager = VideoExtensionManager.shared
    @State private var newExt: String = ""
    @State private var hoveredExt: String?

    var body: some View {
        Form {
            Section {
                ForEach(manager.entries) { entry in
                    extensionRow(entry)
                }
            } header: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Extensions")
                    Text("Turn the toggle off to temporarily exclude an extension from folder scans. Hover a row and click Remove to delete it from the list.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textCase(nil)
                }
            }

            Section {
                LabeledContent {
                    HStack(spacing: 8) {
                        TextField("e.g. mp4", text: $newExt)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                            .onSubmit { addNew() }
                        Button("Add") { addNew() }
                            .disabled(newExt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } label: {
                    SettingsLabel(
                        "Extension",
                        description: "Add a file extension Skagway should treat as video when scanning folders."
                    )
                }
            } header: {
                Text("Add Extension")
            }

            Section {
                Button("Reset to Defaults") {
                    manager.resetToDefaults()
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func extensionRow(_ entry: VideoExtensionEntry) -> some View {
        let isHovered = hoveredExt == entry.ext
        return HStack(spacing: 12) {
            Text(".\(entry.ext)")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(entry.enabled ? Color.primary : Color.secondary)

            Spacer(minLength: 8)

            // Always in the layout (opacity only) so hover doesn’t change row height / jitter the list.
            Button("Remove") {
                manager.remove(entry.ext)
                if hoveredExt == entry.ext {
                    hoveredExt = nil
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .help("Remove .\(entry.ext)")
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
            .accessibilityHidden(!isHovered)

            Toggle(
                "Enabled",
                isOn: Binding(
                    get: { entry.enabled },
                    set: { manager.setEnabled(entry.ext, $0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredExt = entry.ext
            } else if hoveredExt == entry.ext {
                hoveredExt = nil
            }
        }
    }

    private func addNew() {
        let trimmed = newExt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        manager.add(trimmed)
        newExt = ""
    }
}
