import SwiftUI

/// Playground window for experimenting with custom chrome (independent of Settings).
struct FunComponentView: View {
    /// Window fill (hidden once sidebar + content cover the window).
    var backgroundColor: Color = Color(red: 135 / 255, green: 206 / 255, blue: 235 / 255) // sky blue

    /// Sidebar fill — Settings-sidebar width, full height including title-bar safe area.
    var sidebarColor: Color = Color(red: 22 / 255, green: 24 / 255, blue: 26 / 255)
    private let sidebarWidth: CGFloat = 200

    /// Content pane fill — everything not occupied by the sidebar.
    var contentColor: Color = Color(red: 36 / 255, green: 40 / 255, blue: 42 / 255)

    /// Inset between content edges and the yellow cards / title.
    private let contentPadding: CGFloat = 22
    /// Header strip above the first card (layout height below the safe area).
    private let titleBandHeight: CGFloat = 56
    /// Empty placeholder cards — roughly two Settings-style rows.
    private let emptyCardHeight: CGFloat = 96
    private let cardCornerRadius: CGFloat = 10
    private let emptyCardCount = 2

    /// Card fill inside the content pane.
    var cardColor: Color = Color(red: 43 / 255, green: 47 / 255, blue: 48 / 255)

    @State private var excludeCorrupt = false
    @State private var confirmDeletions = true
    @State private var selectedCategory: SettingsCategory? = .library
    @State private var searchText = ""

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var searchResults: [SettingsSearchItem] {
        SettingsSearchCatalog.matches(for: searchText)
    }

    private var contentTitle: String {
        selectedCategory?.title ?? "Library"
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: sidebarWidth)
                .frame(maxHeight: .infinity)
                .background(sidebarColor.ignoresSafeArea(edges: .top))

            contentPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Background only under the title bar; title/cards stay clear of traffic lights.
                .background(contentColor.ignoresSafeArea(edges: .top))
        }
        .frame(minWidth: 720, minHeight: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundColor.ignoresSafeArea())
    }

    // MARK: - Sidebar (mirrors Settings chrome; does not modify Settings)

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Search — same structure/spacing as Settings (sits under traffic-light safe area).
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 12)

            List(selection: $selectedCategory) {
                if isSearching {
                    ForEach(searchResults) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .foregroundStyle(Color.primary)
                                .multilineTextAlignment(.leading)
                            Text(item.category.title)
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .tag(item.category)
                        .onTapGesture {
                            selectedCategory = item.category
                            searchText = ""
                        }
                    }
                } else {
                    ForEach(SettingsCategory.allCases) { category in
                        Label(category.title, systemImage: category.systemImage)
                            .tag(category)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .overlay {
                if isSearching && searchResults.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
    }

    // MARK: - Content

    private var contentPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Center title in the *visible* content band (window top → first card).
            GeometryReader { geo in
                let safeTop = geo.safeAreaInsets.top
                let visualBandHeight = safeTop + titleBandHeight
                Text(contentTitle)
                    .font(.title2.weight(.semibold))
                    .padding(.horizontal, contentPadding)
                    .frame(width: geo.size.width, height: visualBandHeight, alignment: .leading)
                    .offset(y: -safeTop)
            }
            .frame(height: titleBandHeight)

            ScrollView {
                VStack(spacing: 16) {
                    sampleSettingsCard

                    ForEach(0..<emptyCardCount, id: \.self) { _ in
                        emptyCard
                    }
                }
                .padding(.horizontal, contentPadding)
                .padding(.bottom, contentPadding)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    /// First card with two sample settings rows separated like Settings Form sections.
    private var sampleSettingsCard: some View {
        VStack(spacing: 0) {
            settingsRow(
                title: "Exclude corrupt files from filters",
                description: "Corrupt files (missing duration and resolution) will be hidden from Library, Collections, Rating, and Tag filters. They remain visible in the Corrupt filter and name search.",
                isOn: $excludeCorrupt
            )

            Rectangle()
                .fill(Color(red: 53 / 255, green: 56 / 255, blue: 58 / 255))
                .frame(height: 1)
                .padding(.horizontal, 14)

            settingsRow(
                title: "Confirm deletions",
                description: "When enabled, a confirmation dialog will appear before moving files to Trash.",
                isOn: $confirmDeletions
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardColor, in: RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
    }

    private func settingsRow(title: String, description: String, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("", isOn: isOn)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 52)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyCard: some View {
        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
            .fill(cardColor)
            .frame(maxWidth: .infinity)
            .frame(height: emptyCardHeight)
    }
}
