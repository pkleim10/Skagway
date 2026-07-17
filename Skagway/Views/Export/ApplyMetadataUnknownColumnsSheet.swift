import SwiftUI

/// Pre-import prompt: choose which unknown file columns to add as custom metadata fields.
struct ApplyMetadataUnknownColumnsSheet: View {
    @Bindable var viewModel: LibraryViewModel
    let prompt: LibraryViewModel.MetadataApplyUnknownColumnsPrompt

    @State private var selectedKeys: Set<String>
    @State private var typesByKey: [String: CustomMetadataValueType]

    @Environment(\.dismiss) private var dismiss

    init(viewModel: LibraryViewModel, prompt: LibraryViewModel.MetadataApplyUnknownColumnsPrompt) {
        self.viewModel = viewModel
        self.prompt = prompt
        _selectedKeys = State(initialValue: Set(prompt.columns.map(\.key)))
        _typesByKey = State(initialValue: Dictionary(
            uniqueKeysWithValues: prompt.columns.map { ($0.key, $0.suggestedType) }
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Unknown columns")
                .font(.title2.weight(.semibold))

            Text(prompt.sourceURL.lastPathComponent)
                .foregroundStyle(Color.appTextSecondary)

            Text("These columns are not built-in fields or existing custom metadata. Select which to add as custom fields and import.")
                .font(.callout)
                .foregroundStyle(Color.appTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            List {
                ForEach(prompt.columns) { column in
                    HStack(alignment: .center, spacing: 12) {
                        Toggle(isOn: bindingSelected(column.key)) {
                            EmptyView()
                        }
                        .toggleStyle(.checkbox)
                        .labelsHidden()

                        VStack(alignment: .leading, spacing: 2) {
                            Text(column.key)
                                .font(.body.weight(.medium))
                            if !column.samplePreview.isEmpty {
                                Text(column.samplePreview)
                                    .font(.caption)
                                    .foregroundStyle(Color.appTextTertiary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Picker("Type", selection: bindingType(column.key)) {
                            ForEach(CustomMetadataValueType.allCases) { t in
                                Text(t.displayName).tag(t)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                        .disabled(!selectedKeys.contains(column.key))
                    }
                    .padding(.vertical, 2)
                }
            }
            .frame(minHeight: 180, maxHeight: 320)

            HStack {
                Button("Cancel") {
                    viewModel.cancelImportUnknownColumns()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Skip all") {
                    viewModel.skipImportUnknownColumns()
                    dismiss()
                }

                Button("Import selected") {
                    let selections = prompt.columns.compactMap { col -> (key: String, valueType: CustomMetadataValueType)? in
                        guard selectedKeys.contains(col.key) else { return nil }
                        let type = typesByKey[col.key] ?? col.suggestedType
                        return (col.key, type)
                    }
                    viewModel.confirmImportUnknownColumns(selections)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedKeys.isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 360)
    }

    private func bindingSelected(_ key: String) -> Binding<Bool> {
        Binding(
            get: { selectedKeys.contains(key) },
            set: { on in
                if on { selectedKeys.insert(key) } else { selectedKeys.remove(key) }
            }
        )
    }

    private func bindingType(_ key: String) -> Binding<CustomMetadataValueType> {
        Binding(
            get: { typesByKey[key] ?? .string },
            set: { typesByKey[key] = $0 }
        )
    }
}
