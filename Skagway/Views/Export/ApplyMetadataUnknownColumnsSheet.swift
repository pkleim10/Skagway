import SwiftUI

/// Pre-import prompt: choose which unknown file columns to add as custom metadata fields.
struct ApplyMetadataUnknownColumnsSheet: View {
    @Bindable var viewModel: LibraryViewModel
    let prompt: LibraryViewModel.MetadataApplyUnknownColumnsPrompt

    @State private var selectedKeys: Set<String>
    @State private var typesByKey: [String: CustomMetadataValueType]

    @Environment(\.dismiss) private var dismiss

    private let rowDark = Color.appBackground
    private let rowLight = Color.appSurface
    private let headerBg = Color.appSurface.opacity(0.95)

    init(viewModel: LibraryViewModel, prompt: LibraryViewModel.MetadataApplyUnknownColumnsPrompt) {
        self.viewModel = viewModel
        self.prompt = prompt
        _selectedKeys = State(initialValue: Set(prompt.columns.map(\.key)))
        _typesByKey = State(initialValue: Dictionary(
            uniqueKeysWithValues: prompt.columns.map { ($0.key, $0.suggestedType) }
        ))
    }

    private var allSelected: Bool {
        !prompt.columns.isEmpty && selectedKeys.count == prompt.columns.count
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

            VStack(spacing: 0) {
                tableHeader
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(prompt.columns.enumerated()), id: \.element.id) { index, column in
                            tableRow(column: column, index: index)
                        }
                    }
                }
                .frame(minHeight: 180, maxHeight: 320)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.appDivider.opacity(0.5), lineWidth: 1)
            )

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
        .frame(minWidth: 640, minHeight: 400)
    }

    private var tableHeader: some View {
        HStack(spacing: 0) {
            Toggle(isOn: Binding(
                get: { allSelected },
                set: { on in
                    if on {
                        selectedKeys = Set(prompt.columns.map(\.key))
                    } else {
                        selectedKeys = []
                    }
                }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .help(allSelected ? "Deselect all" : "Select all")
            .frame(width: 36, alignment: .center)

            headerLabel("Column", alignment: .leading)
                .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)

            headerLabel("Sample", alignment: .leading)
                .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)

            headerLabel("Type", alignment: .leading)
                .frame(width: 140, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(headerBg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.appDivider.opacity(0.45))
                .frame(height: 1)
        }
    }

    private func tableRow(column: UnknownImportColumn, index: Int) -> some View {
        let isOn = selectedKeys.contains(column.key)
        return HStack(spacing: 0) {
            Toggle(isOn: bindingSelected(column.key)) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .frame(width: 36, alignment: .center)

            Text(column.key)
                .font(.body.weight(.medium))
                .lineLimit(1)
                .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)

            Text(column.samplePreview.isEmpty ? "—" : column.samplePreview)
                .font(.caption)
                .foregroundStyle(Color.appTextTertiary)
                .lineLimit(1)
                .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)

            Picker("Type", selection: bindingType(column.key)) {
                ForEach(CustomMetadataValueType.allCases) { t in
                    Text(t.displayName).tag(t)
                }
            }
            .labelsHidden()
            .frame(width: 140, alignment: .leading)
            .disabled(!isOn)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(index.isMultiple(of: 2) ? rowDark : rowLight)
    }

    private func headerLabel(_ title: String, alignment: Alignment) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.appTextSecondary)
            .frame(maxWidth: .infinity, alignment: alignment)
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
