import SwiftUI

struct FileExtSettingsView: View {
    @Bindable private var manager = VideoExtensionManager.shared
    @State private var newExt: String = ""

    var body: some View {
        Form {
            Section {
                ForEach(manager.entries) { entry in
                    HStack(spacing: 12) {
                        Toggle(isOn: Binding(
                            get: { entry.enabled },
                            set: { manager.setEnabled(entry.ext, $0) }
                        )) {
                            Text(".\(entry.ext)")
                                .font(.system(.body, design: .monospaced))
                        }

                        Spacer(minLength: 8)

                        Button {
                            manager.remove(entry.ext)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Color.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Remove .\(entry.ext)")
                    }
                }
            } header: {
                Text("Extensions")
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
                        description: "Extensions recognized as video files when scanning folders. Turn off an extension above to temporarily exclude it from scans."
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
    }

    private func addNew() {
        let trimmed = newExt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        manager.add(trimmed)
        newExt = ""
    }
}
