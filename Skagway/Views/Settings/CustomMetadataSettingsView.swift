import SwiftUI

/// Defines custom metadata **fields** (name + type). Per-video values are edited in the Inspector
/// (`CuratedWallInspector`), which reads these definitions to render the right control per field.
struct CustomMetadataSettingsView: View {
    @Bindable var viewModel: LibraryViewModel
    @State private var hoveredFieldId: UUID?
    @State private var showingAddField = false
    @State private var draftName = ""
    @State private var draftType: CustomMetadataValueType = .string

    var body: some View {
        Form {
            Section {
                if viewModel.customMetadataFieldDefinitions.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "square.grid.3x3.square.badge.ellipsis")
                            .font(.title2)
                            .foregroundStyle(Color.secondary)
                        Text("No custom fields")
                            .foregroundStyle(Color.secondary)
                        Text("Add a field to use in the Inspector")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else {
                    ForEach(viewModel.customMetadataFieldDefinitions) { field in
                        fieldRow(field)
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fields")
                    Text("Define fields for custom metadata. Edit per-video values in the Inspector. Change a field’s type with the menu; hover a row and click Remove to delete it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textCase(nil)
                }
            }

            Section {
                LabeledContent {
                    Button("Add Field…") {
                        draftName = ""
                        draftType = .string
                        showingAddField = true
                    }
                } label: {
                    SettingsLabel(
                        "New field",
                        description: "Choose a name and type in the dialog. The field appears in the list above and in the Inspector."
                    )
                }
            } header: {
                Text("Manage")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .sheet(isPresented: $showingAddField) {
            addFieldSheet
        }
    }

    private var addFieldSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Custom Field")
                .font(.title2.weight(.semibold))

            Form {
                TextField("Name", text: $draftName)
                Picker("Type", selection: $draftType) {
                    ForEach(CustomMetadataValueType.allCases) { t in
                        Text(t.displayName).tag(t)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 360)

            HStack {
                Spacer()
                Button("Cancel") {
                    showingAddField = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Add") {
                    commitAddField()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func commitAddField() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = viewModel.addCustomMetadataField(name: trimmed, valueType: draftType)
        showingAddField = false
    }

    private func fieldRow(_ field: CustomMetadataFieldDefinition) -> some View {
        let isHovered = hoveredFieldId == field.id
        return HStack(spacing: 12) {
            Text(field.name)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Always in the layout (opacity only) so hover doesn’t change row height.
            Button("Remove") {
                viewModel.removeCustomMetadataFields(ids: [field.id])
                if hoveredFieldId == field.id {
                    hoveredFieldId = nil
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .help("Remove \(field.name)")
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
            .accessibilityHidden(!isHovered)

            Picker(
                "Type",
                selection: Binding(
                    get: { field.valueType },
                    set: { viewModel.updateCustomMetadataFieldType(id: field.id, valueType: $0) }
                )
            ) {
                ForEach(CustomMetadataValueType.allCases) { t in
                    Text(t.displayName).tag(t)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredFieldId = field.id
            } else if hoveredFieldId == field.id {
                hoveredFieldId = nil
            }
        }
    }
}
