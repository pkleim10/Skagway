import SwiftUI

/// Shown when setup is done but no library is open (Ask-each-launch, Close Library,
/// Remember-mode volume offline, or open failure). All create/open/recent actions live in File.
struct LandingView: View {
    var body: some View {
        VStack(spacing: AppSpacing.xxxl) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)

            VStack(spacing: AppSpacing.sm) {
                Text("Skagway")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(Color.appTextPrimary)

                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(Color.appTextSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)

                Text("Use File → Open Library…, New Library…, or Open Recent.")
                    .font(.body)
                    .foregroundStyle(Color.appTextTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .padding(.top, AppSpacing.sm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }

    private var subtitle: String {
        if DatabaseExportImport.promptsForLibraryEachLaunch {
            return "Open a library to continue — its location is not remembered on this Mac"
        }
        if DatabaseExportImport.storesLocationAsBookmarkOnly {
            return "Home library isn’t available — the volume may be offline"
        }
        return "No library is open"
    }
}
