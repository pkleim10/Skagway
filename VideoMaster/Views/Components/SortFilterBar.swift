import SwiftUI

struct SortMenuButton: View {
    let viewModel: LibraryViewModel

    private var currentSort: VideoSort {
        guard let first = viewModel.tableSortOrder.first else { return .dateAdded }
        return VideoSort.from(keyPath: first.keyPath)
    }

    private var isAscending: Bool {
        viewModel.tableSortOrder.first?.order == .forward
    }

    var body: some View {
        Menu {
            ForEach(VideoSort.allCases) { sort in
                Button {
                    if currentSort == sort {
                        viewModel.tableSortOrder = sort.comparators(ascending: !isAscending)
                    } else {
                        viewModel.tableSortOrder = sort.comparators(ascending: true)
                    }
                } label: {
                    HStack {
                        Text(sort.displayName)
                        if currentSort == sort {
                            Image(
                                systemName: isAscending
                                    ? "chevron.up" : "chevron.down"
                            )
                        }
                    }
                }
            }
        } label: {
            // Show the active sort field + direction so it's identifiable in Grid view, where there
            // are no column headers (unlike List view's `Table`).
            Label {
                Text(currentSort.displayName)
            } icon: {
                Image(systemName: isAscending ? "arrow.up" : "arrow.down")
            }
        }
        .help("Sort videos")
    }
}
