import SwiftUI

/// Shared content for Library settings and the list-view “Columns…” sheet.
struct ListColumnsSettingsContent: View {
    @Bindable var viewModel: LibraryViewModel

    /// Multiline “text” custom fields are omitted from list columns (use string or other types).
    private var listableCustomDefinitions: [CustomMetadataFieldDefinition] {
        viewModel.customMetadataFieldDefinitions
            .filter { $0.valueType != .text }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Group {
            HStack(alignment: .firstTextBaseline) {
                SettingsLabel(
                    "Name",
                    description: "Always visible. Choose which metadata columns appear in list view. Up to 16 custom columns can be shown at once (alphabetically). Reorder and resize visible columns from the table header."
                )
                Spacer(minLength: 8)
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.secondary)
                    .help("Always visible")
            }

            Toggle("Duration", isOn: bindingStandard("duration"))
            Toggle("Resolution", isOn: bindingStandard("resolution"))
            Toggle("File size", isOn: bindingStandard("size"))
            Toggle("Rating", isOn: bindingStandard("rating"))
            Toggle("Date added", isOn: bindingStandard("dateAdded"))
            Toggle("Plays", isOn: bindingStandard("playCount"))
            Toggle("Created", isOn: bindingStandard("created"))
            Toggle("Last played", isOn: bindingStandard("lastPlayed"))

            if listableCustomDefinitions.isEmpty {
                Text("No listable custom metadata fields (multiline “Text” fields are excluded). Add fields in Custom Metadata settings.")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .padding(.top, 4)
            } else {
                ForEach(listableCustomDefinitions) { field in
                    Toggle(field.name, isOn: bindingCustom(field.id))
                }
            }
        }
    }

    private func bindingStandard(_ id: String) -> Binding<Bool> {
        Binding(
            get: { viewModel.isStandardListColumnVisible(id) },
            set: { viewModel.setStandardListColumnVisible(id, visible: $0) }
        )
    }

    private func bindingCustom(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { viewModel.isCustomListFieldVisible(id) },
            set: { viewModel.setCustomListFieldVisible(fieldId: id, visible: $0) }
        )
    }
}
