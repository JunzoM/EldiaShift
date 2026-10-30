import SwiftUI

// MARK: - 初めて開いたとき

struct StartView: View {
    @Binding var importing: Bool
    @Environment(ShiftStore.self) private var store
    @State private var error: String?

    var body: some View {
        ContentUnavailableView {
            Label("シフト表をはじめる", systemImage: "calendar.badge.plus")
        } description: {
            Text("新しく作るか、ほかの端末・PC版で作ったバックアップ（.json）を取り込んでください。")
        } actions: {
            VStack(spacing: 12) {
                Button {
                    do { try store.startNew() } catch { self.error = error.localizedDescription }
                } label: {
                    Text("新しく作る").frame(minWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    importing = true
                } label: {
                    Text("バックアップを取り込む").frame(minWidth: 220)
                }
                .buttonStyle(.bordered)
                Text("「新しく作る」は、部門と時間のひな形の例が入った状態で始まります。名前や時間はあとで変えられます。")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .alert("始められませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}

/// スタッフがまだいないときの表の代わり
struct NoStaffView: View {
    @Environment(ShiftStore.self) private var store
    @State private var adding: StaffMember?

    var body: some View {
        ContentUnavailableView {
            Label("スタッフがいません", systemImage: "person.2.badge.plus")
        } description: {
            Text("スタッフを追加すると、ここにシフト表が表示されます。")
        } actions: {
            Button("スタッフを追加") {
                adding = store.newStaff(in: store.book.scopedDepartments.first?.id ?? store.book.departments.first?.id ?? "")
            }
            .buttonStyle(.borderedProminent)
        }
        .shiftSheet(item: $adding) { s in StaffEditView(member: s, isNew: true) }
    }
}

// MARK: - 部門

struct DepartmentListView: View {
    @Environment(ShiftStore.self) private var store
    @State private var editing: Department?
    @State private var error: String?

    var body: some View {
        let book = store.book
        let stores = book.allStores
        List {
            ForEach(stores) { st in
                let depts = book.departments(in: st.id)
                Section {
                    ForEach(depts) { d in
                        Button { editing = d } label: {
                            HStack {
                                Circle().fill(PaletteColor.fg(d.colorIndex)).frame(width: 12, height: 12)
                                Text(d.name).foregroundStyle(.primary)
                                Spacer()
                                Text("\(book.staff.filter { $0.departmentID == d.id }.count)人")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onMove { from, to in
                        var list = depts
                        list.move(fromOffsets: from, toOffset: to)
                        // ほかの店舗の部門はそのままの順で、店舗の並びにつなぐ
                        let all = stores.flatMap { $0.id == st.id ? list : book.departments(in: $0.id) }
                        do { try store.reorderDepartments(all) } catch { self.error = error.localizedDescription }
                    }
                    if depts.isEmpty {
                        Text("部門がありません").foregroundStyle(.secondary)
                    }
                } header: {
                    if stores.count > 1 { StoreBadgeLabel(store: st) }
                } footer: {
                    if st.id == stores.last?.id { Text("表では、この順に上から並びます。") }
                }
            }
        }
        .navigationTitle("部門")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                EditButton()
                Button { editing = store.newDepartment() } label: { Image(systemName: "plus") }
                    .accessibilityLabel("部門を追加")
            }
        }
        .shiftSheet(item: $editing) { d in DepartmentEditView(department: d) }
        .errorAlert($error)
    }
}

struct DepartmentEditView: View {
    @State var department: Department
    @Environment(ShiftStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    private var isNew: Bool { !store.book.departments.contains { $0.id == department.id } }

    var body: some View {
        NavigationStack {
            Form {
                TextField("部門の名前（例：ホール）", text: $department.name)
                if store.book.allStores.count > 1 {
                    Picker("店舗", selection: Binding(get: { store.book.store(department.storeID)?.id ?? store.book.allStores[0].id },
                                                     set: { department.storeID = $0 })) {
                        ForEach(store.book.allStores) { st in Text(st.name).tag(st.id) }
                    }
                }
                Section("色") { ColorChoice(index: $department.colorIndex) }
                if !isNew {
                    Section {
                        Button("この部門を削除", role: .destructive) {
                            do { try store.deleteDepartment(department); dismiss() } catch { self.error = error.localizedDescription }
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "部門を追加" : "部門")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("やめる") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        department.name = department.name.trimmingCharacters(in: .whitespaces)
                        do { try store.save(department); dismiss() } catch { self.error = error.localizedDescription }
                    }
                    .disabled(department.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .errorAlert($error)
        }
        .presentationDetents([.medium])
    }
}

// MARK: - 時間のひな形

struct TemplateListView: View {
    @Environment(ShiftStore.self) private var store
    @State private var editing: TimeBlock?
    @State private var error: String?

    var body: some View {
        let all = store.book.templates
        List {
            section("勤務", all.filter { !$0.isOff }, all: all)
            section("休み", all.filter(\.isOff), all: all)
        }
        .navigationTitle("時間のひな形")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                EditButton()
                Menu {
                    Button("勤務のひな形") { editing = store.newTemplate(off: false) }
                    Button("休みのひな形") { editing = store.newTemplate(off: true) }
                } label: { Image(systemName: "plus") }
                    .accessibilityLabel("ひな形を追加")
            }
        }
        .shiftSheet(item: $editing) { t in TemplateEditView(template: t) }
        .errorAlert($error)
    }

    private func section(_ title: String, _ items: [TimeBlock], all: [TimeBlock]) -> some View {
        Section(title) {
            ForEach(items) { t in
                Button { editing = t } label: {
                    HStack(spacing: 12) {
                        Text(t.short.isEmpty ? "・" : t.short).font(.headline)
                            .foregroundStyle(PaletteColor.fg(t.colorIndex))
                            .frame(width: 44, height: 32)
                            .background(PaletteColor.bg(t.colorIndex), in: RoundedRectangle(cornerRadius: 8))
                        Text(t.label).foregroundStyle(.primary)
                        Spacer()
                        if !t.isOff {
                            Text("\(t.inTime)〜\(t.outTime)").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onMove { from, to in
                // この区分の中で並べ替え、もう一方の区分はそのままの順で後ろにつなぐ
                var list = items
                list.move(fromOffsets: from, toOffset: to)
                let rest = all.filter { t in !items.contains { $0.id == t.id } }
                do { try store.reorderTemplates(list + rest) } catch { self.error = error.localizedDescription }
            }
        }
    }
}

struct TemplateEditView: View {
    @State var template: TimeBlock
    @State private var initialTemplate: TimeBlock?
    @State private var askDiscard = false
    /// スタッフの「個人の時間」を編集するとき（保存はスタッフの設定の「保存」でまとめて行う）
    var personal: Binding<[TimeBlock]>? = nil
    @Environment(ShiftStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var confirmDelete = false

    private var isNew: Bool {
        if let personal { return !personal.wrappedValue.contains { $0.id == template.id } }
        return !store.book.templates.contains { $0.id == template.id }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名前（例：早番）", text: $template.label)
                    TextField("表に出す略称（1〜3文字）", text: Binding(get: { template.short },
                                                                set: { template.short = String($0.prefix(3)) }))
                }
                if !template.isOff {
                    Section("時間") {
                        Picker("出勤", selection: Binding(get: { template.inMinutes ?? 540 }, set: { template.inMinutes = $0 })) {
                            ForEach(Array(stride(from: 0, to: 1440, by: 30)), id: \.self) { Text(ClockTime.format($0)).tag($0) }
                        }
                        Picker("退勤", selection: Binding(get: { template.outMinutes ?? 1080 }, set: { template.outMinutes = $0 })) {
                            ForEach(Array(stride(from: 0, through: 1440, by: 30)), id: \.self) { m in
                                Text(ClockTime.format(m) + (m <= (template.inMinutes ?? 0) ? "（翌日）" : "")).tag(m)
                            }
                        }
                        LabeledContent("拘束時間", value: String(format: "%.1f 時間",
                                                              ClockTime.hours(from: template.inMinutes ?? 0, to: template.outMinutes ?? 0)))
                    }
                }
                if !template.isOff {
                    TemplateBreakSection(block: $template, rules: store.book.breakRules)
                }
                Section("色") { ColorChoice(index: $template.colorIndex) }
                if !isNew {
                    Section {
                        Button("このひな形を削除", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(personal != nil ? (isNew ? "個人の時間を追加" : "個人の時間") : (isNew ? "ひな形を追加" : "ひな形"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { if initialTemplate == nil { initialTemplate = template } }
            .discardGuard(dirty: initialTemplate.map { $0 != template } ?? false, asking: $askDiscard) { dismiss() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("やめる") { if initialTemplate.map({ $0 != template }) ?? false { askDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        template.label = template.label.trimmingCharacters(in: .whitespaces)
                        if template.short.isEmpty { template.short = String(template.label.prefix(1)) }
                        if let personal {
                            if let i = personal.wrappedValue.firstIndex(where: { $0.id == template.id }) {
                                personal.wrappedValue[i] = template
                            } else {
                                personal.wrappedValue.append(template)
                            }
                            dismiss()
                            return
                        }
                        do { try store.save(template); dismiss() } catch { self.error = error.localizedDescription }
                    }
                    .disabled(template.label.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("「\(template.label)」を削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("削除する", role: .destructive) {
                    if let personal {
                        personal.wrappedValue.removeAll { $0.id == template.id }
                        dismiss()
                        return
                    }
                    do { try store.deleteTemplate(template); dismiss() } catch { self.error = error.localizedDescription }
                }
            } message: {
                let n = store.usageCount(of: template.id)
                Text(n == 0 ? "どこにも使われていません。"
                     : "\(n)か所で使われています。削除すると、週のくり返しでこのひな形を選んでいた日は空きになります（手で入れた時刻は残ります）。")
            }
            .errorAlert($error)
        }
    }
}

// MARK: - 部品

/// 10色から選ぶ
struct ColorChoice: View {
    @Binding var index: Int

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
            ForEach(Palette.colors.indices, id: \.self) { i in
                Button { index = i } label: {
                    Circle().fill(PaletteColor.fg(i)).frame(width: 30, height: 30)
                        .overlay(Circle().strokeBorder(Color.primary, lineWidth: index == i ? 3 : 0).padding(-4))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("色\(i + 1)")
                .accessibilityAddTraits(index == i ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

extension View {
    /// 失敗したときのお知らせ
    func errorAlert(_ message: Binding<String?>) -> some View {
        alert("うまくいきませんでした", isPresented: Binding(get: { message.wrappedValue != nil },
                                                    set: { if !$0 { message.wrappedValue = nil } })) {
            Button("OK") { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
