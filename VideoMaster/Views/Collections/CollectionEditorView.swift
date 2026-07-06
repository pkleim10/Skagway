import GRDB
import SwiftUI

struct CollectionEditorView: View {
    let dbPool: DatabasePool
    let collection: VideoCollection?
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var outerMatchMode: MatchMode = .all
    @State private var groups: [EditableGroup] = [EditableGroup()]

    struct EditableRule: Identifiable {
        let id = UUID()
        var attribute: RuleAttribute = .name
        var comparison: RuleComparison = .equals
        var value: String = ""
    }

    struct EditableGroup: Identifiable {
        let id = UUID()
        var matchMode: MatchMode = .all
        var rules: [EditableRule] = [EditableRule()]
    }

    private var repository: CollectionRepository {
        CollectionRepository(dbPool: dbPool)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !groups.isEmpty
            && groups.allSatisfy { group in
                !group.rules.isEmpty
                    && group.rules.allSatisfy { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            groupsArea
            Divider()
            footer
        }
        .frame(width: 660, height: 500)
        .onAppear { loadExisting() }
    }

    private var header: some View {
        HStack {
            Text("Collection Name:")
                .fontWeight(.medium)
            TextField("e.g. Large Files", text: $name)
                .textFieldStyle(.roundedBorder)
        }
        .padding()
    }

    private var groupsArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("Match")
                    .font(.callout)
                    .foregroundStyle(Color.appTextSecondary)

                modeToggle($outerMatchMode)

                Text("of the following groups:")
                    .font(.callout)
                    .foregroundStyle(Color.appTextSecondary)
            }

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { groupIndex, _ in
                        groupCard(groupIndex: groupIndex)
                    }

                    Button(action: addGroup) {
                        Label("Add Group", systemImage: "plus.circle.fill")
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.appAccent)
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: .infinity)
        }
        .padding()
    }

    private func groupCard(groupIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("Match videos where")
                    .font(.callout)
                    .foregroundStyle(Color.appTextSecondary)

                modeToggle($groups[groupIndex].matchMode)

                Text("of the following are true:")
                    .font(.callout)
                    .foregroundStyle(Color.appTextSecondary)

                Spacer()

                Button(action: { removeGroup(at: groupIndex) }) {
                    Image(systemName: "trash")
                        .foregroundStyle(Color.appTextSecondary)
                }
                .buttonStyle(.borderless)
                .disabled(groups.count <= 1)
                .help("Remove group")
            }

            VStack(spacing: 6) {
                ForEach(Array(groups[groupIndex].rules.enumerated()), id: \.element.id) { ruleIndex, _ in
                    ruleRow(groupIndex: groupIndex, ruleIndex: ruleIndex)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.appSurface.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.appDivider, lineWidth: 1)
        )
    }

    private func modeToggle(_ mode: Binding<MatchMode>) -> some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.15)) { mode.wrappedValue = mode.wrappedValue == .all ? .any : .all } }) {
            Text(mode.wrappedValue == .all ? "ALL" : "ANY")
                .font(.callout)
                .fontWeight(.bold)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(mode.wrappedValue == .all ? Color.appAccent : Color.orange)
                )
                .foregroundColor(.white)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func ruleRow(groupIndex: Int, ruleIndex: Int) -> some View {
        HStack(spacing: 8) {
            Picker("Attribute", selection: $groups[groupIndex].rules[ruleIndex].attribute) {
                ForEach(RuleAttribute.allCases) { attr in
                    Text(attr.label).tag(attr)
                }
            }
            .labelsHidden()
            .frame(width: 130)
            .onChange(of: groups[groupIndex].rules[ruleIndex].attribute) { _, newAttr in
                let supported = newAttr.supportedComparisons
                if !supported.contains(groups[groupIndex].rules[ruleIndex].comparison) {
                    groups[groupIndex].rules[ruleIndex].comparison = supported.first ?? .equals
                }
            }

            Picker("Comparison", selection: $groups[groupIndex].rules[ruleIndex].comparison) {
                ForEach(groups[groupIndex].rules[ruleIndex].attribute.supportedComparisons) { comp in
                    Text(comp.label).tag(comp)
                }
            }
            .labelsHidden()
            .frame(width: 150)

            TextField(
                groups[groupIndex].rules[ruleIndex].attribute.valuePlaceholder,
                text: $groups[groupIndex].rules[ruleIndex].value
            )
            .textFieldStyle(.roundedBorder)

            Button(action: { addRule(toGroup: groupIndex) }) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.green)
            }
            .buttonStyle(.borderless)

            Button(action: { removeRule(at: ruleIndex, inGroup: groupIndex) }) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .disabled(groups[groupIndex].rules.count <= 1)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(collection == nil ? "Create" : "Save") { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
        }
        .padding()
    }

    // MARK: - Actions

    private func addRule(toGroup groupIndex: Int) {
        groups[groupIndex].rules.append(EditableRule())
    }

    private func removeRule(at ruleIndex: Int, inGroup groupIndex: Int) {
        guard groups[groupIndex].rules.count > 1 else { return }
        groups[groupIndex].rules.remove(at: ruleIndex)
    }

    private func addGroup() {
        groups.append(EditableGroup())
    }

    private func removeGroup(at index: Int) {
        guard groups.count > 1 else { return }
        groups.remove(at: index)
    }

    private func loadExisting() {
        guard let existing = collection else {
            groups = [EditableGroup()]
            return
        }
        name = existing.name
        outerMatchMode = existing.matchMode
        Task {
            guard let id = existing.id else { return }
            let dbGroups = (try? await repository.fetchRuleGroups(for: id)) ?? []
            let dbRules = (try? await repository.fetchRules(for: id)) ?? []
            if dbGroups.isEmpty {
                groups = [EditableGroup()]
            } else {
                let rulesByGroup = Dictionary(grouping: dbRules, by: \.groupId)
                groups = dbGroups.sorted { $0.orderIndex < $1.orderIndex }.map { g in
                    let groupRules = (rulesByGroup[g.id ?? -1] ?? []).map { r in
                        EditableRule(attribute: r.attribute, comparison: r.comparison, value: r.value)
                    }
                    return EditableGroup(matchMode: g.matchMode, rules: groupRules.isEmpty ? [EditableRule()] : groupRules)
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        Task {
            let groupInputs: [(mode: MatchMode, rules: [CollectionRule])] = groups.map { g in
                (
                    mode: g.matchMode,
                    rules: g.rules.map { r in
                        CollectionRule(
                            collectionId: 0,
                            groupId: 0,
                            attribute: r.attribute,
                            comparison: r.comparison,
                            value: r.value.trimmingCharacters(in: .whitespaces)
                        )
                    }
                )
            }
            if var existing = collection {
                existing.name = trimmedName
                existing.matchMode = outerMatchMode
                try? await repository.update(existing)
                if let id = existing.id {
                    try? await repository.replaceRuleGroups(for: id, with: groupInputs)
                }
            } else {
                let newCollection = VideoCollection(name: trimmedName, dateCreated: Date(), matchMode: outerMatchMode)
                let saved = try? await repository.insert(newCollection)
                if let id = saved?.id {
                    try? await repository.replaceRuleGroups(for: id, with: groupInputs)
                }
            }
            onSave()
            dismiss()
        }
    }
}
