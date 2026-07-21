import AppKit
import SwiftUI

/// System Settings–style integer field: value + up/down chevrons inside one rounded bezel,
/// with an optional unit label outside (e.g. Font size … `pt`).
struct SettingsIntegerStepper: View {
    @Binding var value: Int
    var range: ClosedRange<Int>
    var unit: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                TextField("", value: $value, format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain)
                    .frame(width: 36)
                    .onChange(of: value) { _, newVal in
                        if newVal < range.lowerBound { value = range.lowerBound }
                        if newVal > range.upperBound { value = range.upperBound }
                    }

                VStack(spacing: 0) {
                    Button {
                        if value < range.upperBound { value += 1 }
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 7, weight: .bold))
                            .frame(width: 14, height: 9)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(value >= range.upperBound)

                    Button {
                        if value > range.lowerBound { value -= 1 }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                            .frame(width: 14, height: 9)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(value <= range.lowerBound)
                }
                .foregroundStyle(Color.secondary)
            }
            .padding(.leading, 6)
            .padding(.trailing, 4)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
            )

            if let unit {
                Text(unit)
                    .foregroundStyle(Color.secondary)
            }
        }
        .fixedSize()
    }
}
