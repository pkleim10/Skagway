import SwiftUI

/// The "Move Queue" manager, opened from the header status pill. Lists every cross-volume
/// `MoveJob` and offers per-status actions: abort, move to top, retry, dismiss.
/// Same-volume moves (atomic rename) never appear here — see `LibraryViewModel.moveVideos`.
struct MoveQueueView: View {
    @Bindable var vm: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    private var firstQueuedId: UUID? {
        vm.moveJobs.first { $0.status == .queued }?.id
    }

    private var hasCompleted: Bool {
        vm.moveJobs.contains { $0.isCompleted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().overlay(Color.appDivider)

            if vm.moveJobs.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: AppSpacing.xs) {
                        ForEach(vm.moveJobs) { job in
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
            Text("Move Queue")
                .font(.headline)
                .foregroundStyle(Color.appTextPrimary)
            Spacer()
            if hasCompleted {
                Button("Clear") { vm.clearCompletedMoves() }
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
            Image(systemName: "arrow.right.doc.on.clipboard")
                .font(.system(size: 28))
                .foregroundStyle(Color.appTextTertiary)
            Text("No moves in progress")
                .font(.callout)
                .foregroundStyle(Color.appTextSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ job: MoveJob) -> some View {
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
    private func statusIcon(_ job: MoveJob) -> some View {
        switch job.status {
        case .queued:
            Image(systemName: "clock").foregroundStyle(Color.appTextTertiary)
        case .moving:
            ProgressView().controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func detail(_ job: MoveJob) -> some View {
        switch job.status {
        case .queued:
            Text("Queued")
                .font(.system(size: 10))
                .foregroundStyle(Color.appTextTertiary)
        case .moving(let fraction):
            HStack(spacing: AppSpacing.sm) {
                ProgressView(value: fraction, total: 1)
                    .progressViewStyle(.linear)
                    .tint(Color.appAccent)
                    .frame(width: 120)
                Text("\(Int(fraction * 100))%")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(Color.appTextSecondary)
            }
        case .completed:
            Text("Moved")
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
    private func actions(_ job: MoveJob) -> some View {
        switch job.status {
        case .queued:
            if job.id != firstQueuedId {
                pillButton("Move to Top", systemImage: "arrow.up.to.line") {
                    vm.moveJobToTop(job.id)
                }
            }
            pillButton("Abort", role: .destructive) { vm.abortMove(job.id) }
        case .moving:
            pillButton("Abort", role: .destructive) { vm.abortMove(job.id) }
        case .completed:
            pillButton("Dismiss") { vm.dismissMove(job.id) }
        case .failed:
            pillButton("Retry") { vm.retryMove(job.id) }
            pillButton("Dismiss") { vm.dismissMove(job.id) }
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
