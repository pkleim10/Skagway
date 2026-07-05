import SwiftUI

/// The "Re-encode Queue" manager, opened from the header status pill.
/// Lists every ConversionJob and offers per-status actions: abort, move to top,
/// delete backup, restore from backup, retry, dismiss.
struct ConversionQueueView: View {
    @Bindable var vm: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    private var hasAnyBackup: Bool {
        vm.conversionJobs.contains { $0.isCompleted && $0.backupPath != nil }
    }

    /// Completed jobs whose backup is already gone — nothing left to manage, just clutter.
    private var hasClearableJobs: Bool {
        vm.conversionJobs.contains { $0.isCompleted && $0.backupPath == nil }
    }

    private var firstQueuedId: UUID? {
        vm.conversionJobs.first { $0.status == .queued }?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().overlay(Color.appDivider)

            if vm.conversionJobs.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: AppSpacing.xs) {
                        ForEach(vm.conversionJobs) { job in
                            row(job)
                            Divider().overlay(Color.appDivider.opacity(0.5))
                        }
                    }
                    .padding(AppSpacing.md)
                }
            }
        }
        .frame(width: 520, height: 420)
        .background(Color.appSurface.opacity(0.98))
    }

    private var header: some View {
        HStack(spacing: AppSpacing.md) {
            Text("Re-encode Queue")
                .font(.headline)
                .foregroundStyle(Color.appTextPrimary)
            Spacer()
            if hasClearableJobs {
                Button("Clear") { vm.clearConvertedJobsWithDeletedBackup() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appTextSecondary)
            }
            if hasAnyBackup {
                Button("Delete All Backups") { vm.deleteAllConversionBackups() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appTextSecondary)
            }
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Color.appAccent)
                .controlSize(.small)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.sm) {
            Spacer()
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 28))
                .foregroundStyle(Color.appTextTertiary)
            Text("No re-encode jobs")
                .font(.callout)
                .foregroundStyle(Color.appTextSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ job: ConversionJob) -> some View {
        HStack(spacing: AppSpacing.md) {
            statusIcon(job)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(job.sourceFileName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.appTextPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                detail(job)
            }

            Spacer(minLength: AppSpacing.sm)

            actions(job)
        }
        .padding(.vertical, AppSpacing.xs)
    }

    @ViewBuilder
    private func statusIcon(_ job: ConversionJob) -> some View {
        switch job.status {
        case .queued:
            Image(systemName: "clock").foregroundStyle(Color.appTextTertiary)
        case .converting:
            ProgressView().controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func detail(_ job: ConversionJob) -> some View {
        switch job.status {
        case .queued:
            Text("Queued")
                .font(.system(size: 10))
                .foregroundStyle(Color.appTextTertiary)
        case .converting(let pct):
            HStack(spacing: AppSpacing.sm) {
                ProgressView(value: Double(pct), total: 100)
                    .progressViewStyle(.linear)
                    .tint(Color.appAccent)
                    .frame(width: 120)
                Text("\(pct)%")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(Color.appTextSecondary)
            }
        case .completed:
            Text(job.backupPath != nil ? "Converted · backup kept" : "Converted · backup deleted")
                .font(.system(size: 10))
                .foregroundStyle(Color.appTextTertiary)
        case .failed(let reason):
            Text(reason)
                .font(.system(size: 10))
                .foregroundStyle(.orange)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func actions(_ job: ConversionJob) -> some View {
        switch job.status {
        case .queued:
            if job.id != firstQueuedId {
                pillButton("Move to Top", systemImage: "arrow.up.to.line") {
                    vm.moveConversionToTop(job.id)
                }
            }
            pillButton("Abort", role: .destructive) { vm.abortConversion(job.id) }
        case .converting:
            pillButton("Abort", role: .destructive) { vm.abortConversion(job.id) }
        case .completed:
            if job.backupPath != nil {
                pillButton("Restore") { Task { await vm.restoreConversionBackup(job.id) } }
                pillButton("Delete Backup", role: .destructive) { vm.deleteConversionBackup(job.id) }
            } else {
                pillButton("Dismiss") { vm.dismissConversion(job.id) }
            }
        case .failed:
            pillButton("Retry") { vm.retryConversion(job.id) }
            pillButton("Dismiss") { vm.dismissConversion(job.id) }
        }
    }

    private func pillButton(
        _ title: String,
        systemImage: String? = nil,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            HStack(spacing: 3) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(role == .destructive ? Color.red : Color.appTextSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }
}
