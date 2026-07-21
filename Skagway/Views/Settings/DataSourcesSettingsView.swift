import AppKit
import GRDB
import SwiftUI

struct DataSourcesSettingsView: View {
    let dbPool: DatabasePool

    @State private var dataSources: [DataSource] = []
    @State private var hoveredId: Int64?
    @State private var isLoading = false

    private var repository: DataSourceRepository {
        DataSourceRepository(dbPool: dbPool)
    }

    var body: some View {
        Form {
            Section {
                if dataSources.isEmpty && !isLoading {
                    VStack(spacing: 6) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.title2)
                            .foregroundStyle(Color.secondary)
                        Text("No data sources")
                            .foregroundStyle(Color.secondary)
                        Text("Add folders to watch for video files")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else {
                    ForEach(dataSources) { source in
                        dataSourceRow(source)
                    }
                }
            } header: {
                Text("Folders")
            }

            Section {
                LabeledContent {
                    Button("Add Folder…", action: addFolder)
                } label: {
                    SettingsLabel(
                        "Folders",
                        description: "Folders that Skagway will scan when you import. Hover a folder and click Remove to drop it from the list (files on disk are not deleted)."
                    )
                }
            } header: {
                Text("Manage")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .task {
            await loadDataSources()
        }
    }

    private func dataSourceRow(_ source: DataSource) -> some View {
        let isHovered = hoveredId == source.id
        return HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .foregroundStyle(Color.secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .fontWeight(.medium)
                Text(source.folderPath)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)

            if isHovered {
                Button("Show in Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: source.folderPath)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                Button("Remove") {
                    remove(source)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Text(source.dateAdded, style: .date)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredId = source.id
            } else if hoveredId == source.id {
                hoveredId = nil
            }
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Select folders to watch for video files"
        panel.prompt = "Add"

        if panel.runModal() == .OK {
            Task {
                for url in panel.urls {
                    let path = url.path
                    let exists = (try? await repository.exists(folderPath: path)) ?? false
                    if !exists {
                        let source = DataSource(
                            folderPath: path,
                            name: url.lastPathComponent,
                            dateAdded: Date()
                        )
                        try? await repository.insert(source)
                    }
                }
                await loadDataSources()
            }
        }
    }

    private func remove(_ source: DataSource) {
        Task {
            try? await repository.delete(source)
            if hoveredId == source.id {
                hoveredId = nil
            }
            await loadDataSources()
        }
    }

    private func loadDataSources() async {
        isLoading = true
        dataSources = (try? await repository.fetchAll()) ?? []
        isLoading = false
    }
}
