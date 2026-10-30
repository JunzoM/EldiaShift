import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - スタッフの一覧（PC版の 設定 → スタッフ）

struct StaffListView: View {
    @Environment(ShiftStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var adding: StaffMember?
    /// 部門で絞る（空はすべて）
    @State private var deptFilter = ""
    @State private var showInactive = false
    @State private var search = ""
    @State private var moveFrom = ""
    @State private var moveTo = ""
    @State private var confirmMove = false
    @State private var error: String?

    var body: some View {
        let book = store.book
        let depts = book.scopedDepartments
        List {
            ForEach(sections(book)) { group in
                Section {
                    ForEach(group.members) { m in
                        NavigationLink {
                            StaffEditView(member: m, isNew: false)
                        } label: {
                            row(m)
                        }
                        .swipeActions(edge: .leading) {
                            Button { run { try store.moveStaff(m, by: -1) } } label: { Label("上へ", systemImage: "arrow.up") }
                                .tint(.blue)
                            Button { run { try store.moveStaff(m, by: 1) } } label: { Label("下へ", systemImage: "arrow.down") }
                                .tint(.indigo)
                        }
                    }
                    .onMove { from, to in
                        guard search.isEmpty, group.department.id != "support" else { return }
                        var list = group.members
                        list.move(fromOffsets: from, toOffset: to)
                        run { try store.reorderStaff(list) }
                    }
                } header: {
                    HStack {
                        Text(group.department.name)
                        Spacer()
                        Text("\(group.members.count)人")
                    }
                }
            }

            Section {
                Toggle("退職者も表示", isOn: $showInactive)
            } footer: {
                Text("並べ替えは右上の「編集」でドラッグ、または行を右にスワイプして↑↓。同じ部署の中で並び、番号は自動で振り直します。")
            }

            if depts.count >= 2 {
                Section {
                    Picker("移動元", selection: $moveFrom) {
                        Text("選ぶ").tag("")
                        ForEach(depts) { d in Text("\(d.name)（\(book.staff.filter { $0.departmentID == d.id }.count)人）").tag(d.id) }
                    }
                    Picker("移動先", selection: $moveTo) {
                        Text("選ぶ").tag("")
                        ForEach(depts) { d in Text(d.name).tag(d.id) }
                    }
                    Button("全員を移動する") { confirmMove = true }
                        .disabled(moveFrom.isEmpty || moveTo.isEmpty || moveFrom == moveTo
                                  || !book.staff.contains { $0.departmentID == moveFrom })
                } header: {
                    Text("部署の一括移動")
                } footer: {
                    Text("移動元の全員を、移動先の末尾に（並び順を保って）移します。1人ずつ変えるときは、各スタッフを開いて「部署」を変えてください。")
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { filterBar(book) }
        .searchable(text: $search, prompt: "名前で検索")
        .navigationTitle("スタッフ")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                EditButton()
                Button {
                    adding = store.newStaff(in: deptFilter.isEmpty ? (depts.first?.id ?? "") : deptFilter)
                } label: { Label("新規登録", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("スタッフを追加")
            }
        }
        .confirmationDialog("一括移動しますか？", isPresented: $confirmMove, titleVisibility: .visible) {
            Button("移動する") { run { try store.moveAllStaff(from: moveFrom, to: moveTo) } }
        } message: {
            let a = depts.first { $0.id == moveFrom }?.name ?? ""
            let b = depts.first { $0.id == moveTo }?.name ?? ""
            Text("\(a)の全員を\(b)へ移します。")
        }
        .shiftSheet(item: $adding) { s in StaffEditView(member: s, isNew: true) }
        .errorAlert($error)
    }

    /// 部門のタブ（すべて・部門ごと、人数つき）
    private func filterBar(_ book: ShiftBook) -> some View {
        let active = book.staff.filter { showInactive || ($0.active && $0.leaveDate.isEmpty) }
        let groups = sections(book, ignoringFilter: true)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                tabButton("すべて", count: groups.reduce(0) { $0 + $1.members.count }, id: "")
                ForEach(groups) { g in
                    tabButton(g.department.name, count: g.members.count, id: g.department.id)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .id(active.count)
    }

    private func tabButton(_ title: String, count: Int, id: String) -> some View {
        let on = deptFilter == id
        return Button { deptFilter = id } label: {
            HStack(spacing: 6) {
                Text(title).font(.subheadline.weight(.semibold))
                Text("\(count)").font(.caption.weight(.bold)).monospacedDigit()
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(on ? Color.white.opacity(0.25) : Color(.tertiarySystemFill), in: Capsule())
            }
            .foregroundStyle(on ? Color.white : Color.primary)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(on ? Color.accentColor : Color(.secondarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func row(_ m: StaffMember) -> some View {
        let book = store.book
        let dept = book.departments.first { $0.id == m.departmentID }
        let p = m.patterns.first { $0.id == m.activePatternID } ?? m.patterns.first
        let wide = sizeClass != .compact
        // 給与は人件費を隠しているときは出さない
        let showPay = LaborCostLock.shared.canView
        let wage = showPay ? m.wage(on: store.today) : nil
        let short = showPay ? MinimumWage.shortfall(of: m, on: store.today, in: book) : nil
        return HStack(spacing: 12) {
            InitialAvatar(name: m.name, colorIndex: dept?.colorIndex ?? 8, size: 36, photo: m.photo)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.name).font(.body.weight(.semibold)).lineLimit(1)
                Text(wide ? "No.\(m.number)" : [dept?.name, p.map { $0.label }].compactMap { $0 }.joined(separator: "・"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            // 名前を縦に折り返さない（ほかの列より先に幅を取る）
            .frame(minWidth: 96, alignment: .leading)
            .layoutPriority(1)
            Spacer(minLength: 8)
            if wide {
                Text(dept?.name ?? "—").font(.subheadline).lineLimit(1).frame(width: 84, alignment: .leading)
                Text(p?.label ?? "—").font(.subheadline).foregroundStyle(.secondary).lineLimit(1).frame(width: 72, alignment: .leading)
                Text(Self.usualHours(m, book: book)).font(.subheadline).monospacedDigit().lineLimit(1)
                    .minimumScaleFactor(0.8).frame(width: 112, alignment: .leading)
                if showPay {
                    Text(wage.map { "\($0.kind == .hourly ? "時給" : "月給") \(LaborCostView.yen($0.amount))" } ?? "—")
                        .font(.subheadline).monospacedDigit().foregroundStyle(short == nil ? Color.secondary : Color.red)
                        .lineLimit(1).minimumScaleFactor(0.7).frame(width: 104, alignment: .trailing)
                }
            }
            if short != nil {
                StatusPill(text: "最低賃金未満", color: .red).fixedSize()
                    .accessibilityLabel("時給が最低賃金より低い")
            }
            status(m).fixedSize()
        }
        .padding(.vertical, 2)
    }

    private func status(_ m: StaffMember) -> some View {
        if let leave = DayKey(m.leaveDate) {
            return leave >= store.today ? StatusPill(text: "退職予定", color: .orange) : StatusPill(text: "退職", color: .gray)
        }
        return m.active ? StatusPill(text: "在籍", color: .green) : StatusPill(text: "退職", color: .gray)
    }

    /// いつもの勤務時間（使用中の週間パターンでいちばん多い勤務）
    static func usualHours(_ m: StaffMember, book: ShiftBook) -> String {
        guard let p = m.patterns.first(where: { $0.id == m.activePatternID }) ?? m.patterns.first else { return "—" }
        let blocks = p.days.compactMap { $0 }.compactMap { book.block($0, for: m) }.filter { !$0.isOff }
        let counts = Dictionary(blocks.map { ($0.id, 1) }, uniquingKeysWith: +)
        guard let top = counts.max(by: { $0.value < $1.value }), let b = blocks.first(where: { $0.id == top.key }) else { return "—" }
        func hm(_ t: String) -> String {
            guard let v = ClockTime.parse(t) else { return t }
            return "\(v / 60):\(String(format: "%02d", v % 60))"
        }
        return "\(hm(b.inTime))〜\(hm(b.outTime))"
    }

    private func sections(_ book: ShiftBook, ignoringFilter: Bool = false) -> [DepartmentGroup] {
        let all = allSections(book)
        guard !ignoringFilter, !deptFilter.isEmpty else { return all }
        return all.filter { $0.department.id == deptFilter }
    }

    private func allSections(_ book: ShiftBook) -> [DepartmentGroup] {
        let q = search.trimmingCharacters(in: .whitespaces)
        let shown = book.staff.filter {
            (showInactive || ($0.active && $0.leaveDate.isEmpty)) && (q.isEmpty || $0.name.contains(q))
        }
        // いま見ている店舗の部門だけ
        var result: [DepartmentGroup] = book.scopedDepartments.compactMap { d -> DepartmentGroup? in
            let m = shown.filter { $0.departmentID == d.id }.sorted(by: StaffMember.order)
            return m.isEmpty ? nil : DepartmentGroup(department: d, members: m)
        }
        let known = Set(book.departments.map(\.id))
        // 掛け持ちでこの店舗にも入る人（並べ替えは自分の店舗で）
        if let scope = book.scopeStoreID {
            let helpers = shown.filter { known.contains($0.departmentID) && book.homeStoreID(of: $0) != scope && $0.extraStoreIDs.contains(scope) }
            if !helpers.isEmpty {
                result.append(DepartmentGroup(department: Department(id: "support", name: "掛け持ち（ほかの店舗から）", colorIndex: 8,
                                                                     sortOrder: .max - 1), members: helpers.sorted(by: StaffMember.order)))
            }
        }
        let others = shown.filter { !known.contains($0.departmentID) }.sorted(by: StaffMember.order)
        if !others.isEmpty, book.scopeStoreID == nil || book.scopeStoreID == book.allStores[0].id {
            result.append(DepartmentGroup(department: Department(id: "", name: "部門なし", colorIndex: 8, sortOrder: .max), members: others))
        }
        return result
    }

    private func run(_ f: () throws -> Void) {
        do { try f() } catch { self.error = error.localizedDescription }
    }
}

// MARK: - スタッフ1人の設定（基本・個人の時間・週間パターン・期間限定パターン）

struct StaffEditView: View {
    @State var member: StaffMember
    let isNew: Bool
    /// シートで開いたとき（表の名前から）。「閉じる」を出す
    var inSheet = false

    @Environment(ShiftStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var confirmDelete = false
    @State private var editingBlock: TimeBlock?
    @State private var editingPattern: WeekPattern?
    @State private var editingPeriod: PeriodPattern?
    /// 開いたときの内容（保存していない変更があるかを見る）
    @State private var initial: StaffMember?
    @State private var askDiscard = false
    @State private var pickedPhoto: PhotosPickerItem?
    /// 似顔絵を作る画面・ファイルから写真を選ぶ画面
    @State private var makingAvatar = false
    @State private var importingPhoto = false
    /// 保存すると表が変わる日（確認してから保存する）
    @State private var pendingPreview: PatternChecks.Preview?

    private var dirty: Bool { initial.map { $0 != member } ?? false }

    var body: some View {
        let book = store.book
        let deptColor = book.departments.first { $0.id == member.departmentID }?.colorIndex ?? 8
        let form = Form {
            Section("基本") {
                HStack(spacing: 16) {
                    InitialAvatar(name: member.name.isEmpty ? "？" : member.name, colorIndex: deptColor, size: 64, photo: member.photo)
                    // PhotosPicker の見出しは別スレッドから呼ばれることがあるので、先に文字を決めておく
                    let pickTitle = member.photo == nil ? "顔写真を選ぶ" : "写真を変える"
                    VStack(alignment: .leading, spacing: 8) {
                        PhotosPicker(selection: $pickedPhoto, matching: .images) {
                            Label(pickTitle, systemImage: "person.crop.circle.badge.plus")
                        }
                        Menu {
                            Button { makingAvatar = true } label: {
                                Label(StaffAvatarDrawing.restored(from: member.photo) == nil ? "似顔絵を作る" : "似顔絵を直す", systemImage: "face.smiling")
                            }
                            Button { pastePhoto() } label: { Label("画像を貼り付け（ミー文字など）", systemImage: "doc.on.clipboard") }
                            Button { importingPhoto = true } label: { Label("ファイルから選ぶ", systemImage: "folder") }
                        } label: {
                            Label("似顔絵・ほかの画像", systemImage: "face.smiling")
                        }
                        .buttonStyle(.borderless)
                        if member.photo != nil {
                            Button("写真を外す", role: .destructive) { member.photo = nil }
                                .buttonStyle(.borderless)
                        }
                    }
                    // 1行に2つのボタンがあるので、行全体ではなくボタンだけが反応するように
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 2)
                TextField("名前", text: $member.name)
                    .textContentType(.name)
                if let other = duplicateName(book) {
                    Text("同じ名前の人がいます（\(other)）。表で見分けやすい名前にすると迷いません。")
                        .font(.footnote).foregroundStyle(.orange)
                }
                Picker("部署", selection: Binding(get: { member.departmentID }, set: { id in
                    member.departmentID = id
                    // 自分の店舗は掛け持ち先に入れない
                    let home = book.storeID(ofDepartment: id)
                    member.extraStoreIDs.removeAll { $0 == home }
                })) {
                    if !book.departments.contains(where: { $0.id == member.departmentID }) {
                        Text("なし").tag(member.departmentID)
                    }
                    let multi = book.allStores.count > 1
                    ForEach(book.allStores) { st in
                        ForEach(book.departments(in: st.id)) { d in
                            Text(multi ? "\(st.name)・\(d.name)" : d.name).tag(d.id)
                        }
                    }
                }
                Picker("在職", selection: $member.active) {
                    Text("在職").tag(true)
                    Text("退職").tag(false)
                }
                .pickerStyle(.segmented)
                Picker("雇用形態", selection: $member.employment) {
                    Text("未設定").tag("")
                    ForEach(StaffMember.employmentChoices, id: \.self) { Text($0).tag($0) }
                    // 取り込んだデータなどで選択肢に無い値も、そのまま残す
                    if !member.employment.isEmpty, !StaffMember.employmentChoices.contains(member.employment) {
                        Text(member.employment).tag(member.employment)
                    }
                }
                OptionalDateRow(title: "入社日", text: $member.joinDate)
                OptionalDateRow(title: "退職日", text: $member.leaveDate)
                if let issue = dateIssue {
                    Text(issue).font(.footnote).foregroundStyle(.red)
                }
            }

            if book.allStores.count > 1 {
                let home = book.storeID(ofDepartment: member.departmentID)
                Section {
                    ForEach(book.allStores.filter { $0.id != home }) { st in
                        Toggle(isOn: Binding(get: { member.extraStoreIDs.contains(st.id) }, set: { on in
                            member.extraStoreIDs.removeAll { $0 == st.id }
                            if on { member.extraStoreIDs.append(st.id) }
                        })) {
                            StoreBadgeLabel(store: st)
                        }
                    }
                } header: {
                    Text("掛け持ち")
                } footer: {
                    Text("オンにした店舗のシフト表にも、この人が出ます。同じ日に2つの店舗へは入れません（1日1か所）。週間パターンは自分の店舗（\(book.store(home)?.name ?? "")）の勤務になります。")
                }
            }

            WageSection(member: $member)

            Section {
                ForEach(member.timeBlocks) { b in
                    Button { editingBlock = b } label: { BlockRow(block: b) }
                }
                Button {
                    editingBlock = TimeBlock(id: UUID().uuidString, label: member.name.isEmpty ? "" : "\(member.name)_",
                                             short: "", inMinutes: 9 * 60, outMinutes: 18 * 60, colorIndex: 0)
                } label: { Label("個人の時間を追加", systemImage: "plus") }
            } header: {
                Text("個人の時間")
            } footer: {
                Text("この人だけが使う時間のひな形です。マスの選択画面では、共通の時間より先に出ます。")
            }

            Section {
                ForEach(member.patterns) { p in
                    Button { editingPattern = p } label: { patternRow(p) }
                }
                Button {
                    editingPattern = WeekPattern(id: UUID().uuidString, label: member.patterns.isEmpty ? "通常" : "",
                                                 colorIndex: 0, days: Array(repeating: nil, count: 7), activeFrom: nil)
                } label: { Label("週間パターンを作成", systemImage: "plus") }
            } header: {
                Text("週間パターン")
            } footer: {
                Text("曜日ごとの勤務を毎週自動で入れます。「適用開始日」を決めると、その日からそのパターンに切り替わります（例：4/16〜は新しいパターン）。複数あるときは「標準」に選んだものを使います。")
            }

            Section {
                ForEach(member.periodPatterns) { p in
                    Button { editingPeriod = p } label: { periodRow(p) }
                }
                Button {
                    let today = DayKey.today
                    editingPeriod = PeriodPattern(id: UUID().uuidString, label: "", colorIndex: 3,
                                                  startDate: today.description, endDate: today.adding(days: 6).description, days: [:])
                } label: { Label("期間限定パターンを作成", systemImage: "plus") }
            } header: {
                Text("期間限定パターン（GW・年末年始など）")
            } footer: {
                Text("期間中はこちらが週間パターンより優先されます。期間内で何も決めていない日は空きになります。")
            }

            if !isNew {
                Section {
                    Button("このスタッフを削除", role: .destructive) { confirmDelete = true }
                } footer: {
                    Text("辞めた人は、削除せずに退職日を入れると、それまでのシフトが残ります（退職月の翌月から表に出なくなります）。")
                }
            }
        }
        let impact = confirmDelete ? StaffDeletionImpact(member: member, book: book, today: store.today) : nil

        let content = form
            .navigationTitle(isNew ? "スタッフを追加" : (member.name.isEmpty ? "スタッフ" : member.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(member.name.trimmingCharacters(in: .whitespaces).isEmpty || dateIssue != nil)
                }
                if isNew || inSheet {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(isNew ? "やめる" : "閉じる") { if dirty { askDiscard = true } else { dismiss() } }
                    }
                } else if dirty {
                    // 一覧から開いたとき：変更があれば「戻る」で確かめる
                    ToolbarItem(placement: .topBarLeading) {
                        Button { askDiscard = true } label: { Label("戻る", systemImage: "chevron.backward") }
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
            .navigationBarBackButtonHidden(dirty && !isNew && !inSheet)
            .discardGuard(dirty: dirty, asking: $askDiscard) { dismiss() }
            .confirmationDialog("表が変わります。保存しますか？",
                                isPresented: Binding(get: { pendingPreview != nil }, set: { if !$0 { pendingPreview = nil } }),
                                titleVisibility: .visible) {
                Button("保存する") { save(confirmed: true) }
                Button("戻って直す", role: .cancel) {}
            } message: {
                Text(pendingPreview?.message ?? "")
            }
            .onAppear { if initial == nil { initial = member } }
            .onChange(of: pickedPhoto) {
                guard let item = pickedPhoto else { return }
                Task { @MainActor in
                    if let data = try? await item.loadTransferable(type: Data.self), let small = StaffPhoto.shrink(data) {
                        member.photo = small
                    } else {
                        error = "写真を読み込めませんでした"
                    }
                    pickedPhoto = nil
                }
            }
            .shiftSheet(isPresented: $makingAvatar) {
                // 似顔絵は選んだ内容を中に残した PNG のまま入れる（あとで直せるように。240px で十数KB）
                StaffAvatarCreator(initial: StaffAvatarConfiguration(), sourcePhoto: member.photo) { _, data in member.photo = data }
            }
            .fileImporter(isPresented: $importingPhoto, allowedContentTypes: [.image]) { result in
                guard case .success(let url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url), let small = StaffPhoto.shrink(data) {
                    member.photo = small
                } else {
                    error = "画像を読み込めませんでした"
                }
            }
            .shiftSheet(item: $editingBlock) { b in TemplateEditView(template: b, personal: $member.timeBlocks) }
            .shiftSheet(item: $editingPattern) { p in
                PatternEditView(pattern: p, member: member, patterns: $member.patterns, activeID: $member.activePatternID)
            }
            .shiftSheet(item: $editingPeriod) { p in
                PeriodPatternEditView(pattern: p, member: member, periods: $member.periodPatterns)
            }
            .confirmationDialog("\(member.name)さんを削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
                if let impact, impact.enteredDays > 0, member.leaveDate.isEmpty {
                    Button("削除せずに今日で退職にする") {
                        member.leaveDate = store.today.description
                        save(confirmed: true)
                    }
                }
                Button("削除する", role: .destructive) {
                    do { try store.deleteStaff(member); dismiss() } catch { self.error = error.localizedDescription }
                }
            } message: {
                Text(impact?.message ?? "元には戻せません。")
            }
            .errorAlert($error)

        if isNew {
            NavigationStack { content }
        } else {
            content
        }
    }

    private func patternRow(_ p: WeekPattern) -> some View {
        let book = store.book
        let isActive = p.id == (member.activePatternID ?? member.patterns.first?.id)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(PaletteColor.fg(p.colorIndex)).frame(width: 10, height: 10)
                Text(p.label.isEmpty ? "パターン" : p.label).foregroundStyle(.primary)
                if let f = p.activeFrom { Text("\(f)〜").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                if isActive { Text("標準").font(.caption.bold()).foregroundStyle(Color.accentColor) }
            }
            WeekStrip(days: p.days) { book.block($0, for: member) }
        }
    }

    private func periodRow(_ p: PeriodPattern) -> some View {
        HStack {
            Circle().fill(PaletteColor.fg(p.colorIndex)).frame(width: 10, height: 10)
            Text(p.label.isEmpty ? "期間限定" : p.label).foregroundStyle(.primary)
            Spacer()
            Text("\(p.startDate ?? "?") 〜 \(p.endDate ?? "?")").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            Text("\(p.days.count)日").font(.caption).foregroundStyle(.secondary)
        }
    }

    /// 入社日・退職日の食い違い
    private var dateIssue: String? {
        guard let join = DayKey(member.joinDate), let leave = DayKey(member.leaveDate), leave < join else { return nil }
        return "退職日が入社日より前になっています。"
    }

    /// 同じ名前のほかの人（部署名。いなければ nil）
    private func duplicateName(_ book: ShiftBook) -> String? {
        let name = member.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty,
              let other = book.staff.first(where: { $0.id != member.id && $0.name.trimmingCharacters(in: .whitespaces) == name })
        else { return nil }
        let dept = book.departments.first { $0.id == other.departmentID }
        let st = dept.flatMap { book.store(book.storeID(ofDepartment: $0.id)) }
        return [book.allStores.count > 1 ? st?.name : nil, dept?.name ?? "部門なし"].compactMap { $0 }.joined(separator: "・")
    }

    /// confirmed：表が変わる日の確認を済ませた（または不要）
    /// コピーした画像（メッセージのミー文字のステッカーなど）を写真にする
    private func pastePhoto() {
        let board = UIPasteboard.general
        let data = board.data(forPasteboardType: UTType.png.identifier) ?? board.image?.pngData()
        if let data, let small = StaffPhoto.shrink(data) {
            member.photo = small
        } else {
            error = "貼り付けられる画像がありません。メッセージなどで画像やミー文字をコピーしてから押してください。"
        }
    }

    private func save(confirmed: Bool = false) {
        member.name = member.name.trimmingCharacters(in: .whitespaces)
        if let leave = DayKey(member.leaveDate), leave < DayKey.today { member.active = false }
        if member.activePatternID == nil || !member.patterns.contains(where: { $0.id == member.activePatternID }) {
            member.activePatternID = member.patterns.first?.id
        }
        if !confirmed, !isNew, let initial {
            let preview = PatternChecks.preview(old: initial, new: member, book: store.book, today: store.today)
            if !preview.isEmpty {
                pendingPreview = preview
                return
            }
        }
        do {
            try store.save(member)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - 週間パターンの編集

struct PatternEditView: View {
    @State var pattern: WeekPattern
    let member: StaffMember
    @Binding var patterns: [WeekPattern]
    @Binding var activeID: String?

    @Environment(ShiftStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var initial: WeekPattern?
    @State private var askDiscard = false

    /// 表の並び（月曜はじまり）。値は days の位置（0＝日曜）
    private let weekOrder = [1, 2, 3, 4, 5, 6, 0]
    private let weekNames = ["日", "月", "火", "水", "木", "金", "土"]
    private var isNew: Bool { !patterns.contains { $0.id == pattern.id } }

    var body: some View {
        let book = store.book
        let blocks = member.timeBlocks + book.templates
        NavigationStack {
            Form {
                Section {
                    TextField("名前（例：通常・夜勤週）", text: $pattern.label)
                    OptionalDateRow(title: "適用開始日", text: Binding(get: { pattern.activeFrom ?? "" },
                                                                 set: { pattern.activeFrom = $0.isEmpty ? nil : $0 }))
                    Toggle("標準にする", isOn: Binding(get: { (activeID ?? patterns.first?.id) == pattern.id || (isNew && patterns.isEmpty) },
                                                   set: { if $0 { activeID = pattern.id } }))
                }
                Section("色") { ColorChoice(index: $pattern.colorIndex) }

                Section {
                    ForEach(weekOrder, id: \.self) { w in
                        Picker(selection: day(w)) {
                            Text("なし").tag(String?.none)
                            ForEach(blocks) { b in
                                Text(b.isOff ? b.label : "\(b.label)（\(b.inTime)〜\(b.outTime)）").tag(String?.some(b.id))
                            }
                        } label: {
                            Text(weekNames[w] + "曜").foregroundStyle(w == 0 ? Color.red : w == 6 ? Color.blue : Color.primary)
                        }
                    }
                } header: {
                    Text("曜日ごとの勤務")
                }

                // ひな形を押して、入れたい曜日を選ぶ（PC版のチップと同じ使い方）
                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                        ForEach(blocks) { b in
                            Menu {
                                ForEach(weekOrder, id: \.self) { w in
                                    Button {
                                        pattern.days[w] = pattern.days[w] == b.id ? nil : b.id
                                    } label: {
                                        if pattern.days[w] == b.id { Label(weekNames[w] + "曜", systemImage: "checkmark") }
                                        else { Text(weekNames[w] + "曜") }
                                    }
                                }
                                Divider()
                                Button("月〜金に入れる") { for w in 1...5 { pattern.days[w] = b.id } }
                                Button("土日に入れる") { pattern.days[6] = b.id; pattern.days[0] = b.id }
                            } label: {
                                BlockChip(block: b, count: pattern.days.filter { $0 == b.id }.count)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("ひな形から曜日を選ぶ")
                }

                if !isNew {
                    Section {
                        Button("このパターンを削除", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "週間パターンを作成" : "週間パターン")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { if initial == nil { initial = pattern } }
            .discardGuard(dirty: initial.map { $0 != pattern } ?? false, asking: $askDiscard) { dismiss() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("やめる") { if initial.map({ $0 != pattern }) ?? false { askDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("決定") {
                        pattern.label = pattern.label.trimmingCharacters(in: .whitespaces)
                        if pattern.label.isEmpty { pattern.label = "パターン\(patterns.count + 1)" }
                        if let i = patterns.firstIndex(where: { $0.id == pattern.id }) { patterns[i] = pattern }
                        else { patterns.append(pattern) }
                        if activeID == nil { activeID = pattern.id }
                        dismiss()
                    }
                }
            }
            .confirmationDialog("「\(pattern.label)」を削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("削除する", role: .destructive) {
                    patterns.removeAll { $0.id == pattern.id }
                    if activeID == pattern.id { activeID = patterns.first?.id }
                    dismiss()
                }
            }
        }
    }

    private func day(_ w: Int) -> Binding<String?> {
        Binding(get: { pattern.days.indices.contains(w) ? pattern.days[w] : nil },
                set: { v in
                    while pattern.days.count < 7 { pattern.days.append(nil) }
                    pattern.days[w] = v
                })
    }
}

// MARK: - 期間限定パターンの編集

struct PeriodPatternEditView: View {
    @State var pattern: PeriodPattern
    let member: StaffMember
    @Binding var periods: [PeriodPattern]

    @Environment(ShiftStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var initial: PeriodPattern?
    @State private var askDiscard = false

    private var isNew: Bool { !periods.contains { $0.id == pattern.id } }

    private var range: [DayKey] {
        guard let a = DayKey(pattern.startDate ?? ""), let b = DayKey(pattern.endDate ?? ""), a <= b else { return [] }
        var out: [DayKey] = []
        var d = a
        while d <= b && out.count < 400 { out.append(d); d = d.adding(days: 1) }
        return out
    }

    var body: some View {
        let book = store.book
        let blocks = member.timeBlocks + book.templates
        let days = range
        NavigationStack {
            Form {
                Section {
                    TextField("名前（例：GW・年末年始）", text: $pattern.label)
                    DatePicker("開始日", selection: date(\.startDate), displayedComponents: .date)
                    DatePicker("終了日", selection: date(\.endDate), displayedComponents: .date)
                    if days.isEmpty {
                        Text("終了日は開始日以降にしてください").font(.footnote).foregroundStyle(.red)
                    }
                    ForEach(PatternChecks.overlapping(pattern, in: periods)) { o in
                        Text("「\(o.label)」（\(o.startDate ?? "")〜\(o.endDate ?? "")）と期間が重なっています。重なった日はどちらか一方しか使われないので、期間をずらしてください。")
                            .font(.footnote).foregroundStyle(.red)
                    }
                }
                Section("色") { ColorChoice(index: $pattern.colorIndex) }

                if !days.isEmpty {
                    Section {
                        Menu {
                            ForEach(blocks) { b in
                                Button(b.isOff ? b.label : "\(b.label)（\(b.inTime)〜\(b.outTime)）") {
                                    for d in days { pattern.days[d.description] = b.id }
                                }
                            }
                            Divider()
                            Button("すべて空きにする", role: .destructive) {
                                for d in days { pattern.days.removeValue(forKey: d.description) }
                            }
                        } label: {
                            Label("一括設定（期間内の全日を同じシフトに）", systemImage: "square.stack.3d.down.right")
                        }
                    }

                    Section {
                        ForEach(days, id: \.self) { d in
                            Picker(selection: Binding(get: { pattern.days[d.description] },
                                                      set: { pattern.days[d.description] = $0 })) {
                                Text("空き").tag(String?.none)
                                ForEach(blocks) { b in
                                    Text(b.isOff ? b.label : "\(b.label)（\(b.inTime)〜\(b.outTime)）").tag(String?.some(b.id))
                                }
                            } label: {
                                let wd = ["日", "月", "火", "水", "木", "金", "土"][d.weekday]
                                Text("\(d.month)/\(d.day)（\(wd)）").monospacedDigit()
                                    .foregroundStyle(d.weekday == 0 || JapaneseHolidays.isHoliday(d) ? Color.red
                                                     : d.weekday == 6 ? Color.blue : Color.primary)
                            }
                        }
                    } header: {
                        Text("日ごとの勤務（\(days.count)日）")
                    }
                }

                if !isNew {
                    Section {
                        Button("この期間限定パターンを削除", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "期間限定パターンを作成" : "期間限定パターン")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { if initial == nil { initial = pattern } }
            .discardGuard(dirty: initial.map { $0 != pattern } ?? false, asking: $askDiscard) { dismiss() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("やめる") { if initial.map({ $0 != pattern }) ?? false { askDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("決定") {
                        // 期間の外になった日の指定は捨てる
                        let keep = Set(days.map(\.description))
                        pattern.days = pattern.days.filter { keep.contains($0.key) }
                        pattern.label = pattern.label.trimmingCharacters(in: .whitespaces)
                        if pattern.label.isEmpty { pattern.label = "期間限定" }
                        if let i = periods.firstIndex(where: { $0.id == pattern.id }) { periods[i] = pattern }
                        else { periods.append(pattern) }
                        dismiss()
                    }
                    .disabled(days.isEmpty || !PatternChecks.overlapping(pattern, in: periods).isEmpty)
                }
            }
            .confirmationDialog("「\(pattern.label)」を削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("削除する", role: .destructive) {
                    periods.removeAll { $0.id == pattern.id }
                    dismiss()
                }
            }
        }
    }

    private func date(_ key: WritableKeyPath<PeriodPattern, String?>) -> Binding<Date> {
        Binding(get: { DayKey(pattern[keyPath: key] ?? "")?.date ?? Date() },
                set: { pattern[keyPath: key] = DayKey($0).description })
    }
}

// MARK: - 部品

/// 日付を入れるかどうか＋日付（"YYYY-MM-DD"、空は未設定）
struct OptionalDateRow: View {
    let title: String
    @Binding var text: String

    var body: some View {
        let has = Binding(get: { DayKey(text) != nil },
                          set: { text = $0 ? DayKey.today.description : "" })
        let date = Binding(get: { DayKey(text)?.date ?? Date() },
                           set: { text = DayKey($0).description })
        VStack(alignment: .leading) {
            Toggle(title, isOn: has)
            if has.wrappedValue {
                DatePicker(title, selection: date, displayedComponents: .date)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "ja_JP"))
            }
        }
    }
}

/// ひな形1つの行
struct BlockRow: View {
    let block: TimeBlock

    var body: some View {
        HStack(spacing: 12) {
            Text(block.short.isEmpty ? "・" : block.short).font(.headline)
                .foregroundStyle(PaletteColor.fg(block.colorIndex))
                .frame(width: 44, height: 32)
                .background(PaletteColor.bg(block.colorIndex), in: RoundedRectangle(cornerRadius: 8))
            Text(block.label).foregroundStyle(.primary)
            Spacer()
            if !block.isOff {
                Text("\(block.inTime)〜\(block.outTime)").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }
}

/// ひな形のチップ（何曜日に入っているか）
struct BlockChip: View {
    let block: TimeBlock
    let count: Int

    var body: some View {
        VStack(spacing: 1) {
            Text(block.label).font(.caption.weight(.bold)).lineLimit(1)
            if !block.isOff {
                Text("\(block.inTime)〜\(block.outTime)").font(.system(size: 10)).monospacedDigit()
            }
            if count > 0 { Text("\(count)日").font(.system(size: 9, weight: .bold)) }
        }
        .foregroundStyle(PaletteColor.fg(block.colorIndex))
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(count > 0 ? PaletteColor.bg(block.colorIndex) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(PaletteColor.fg(block.colorIndex), style: StrokeStyle(lineWidth: 1.5, dash: count > 0 ? [] : [4])))
    }
}

/// 週間パターンを1行で（月〜日）
struct WeekStrip: View {
    let days: [String?]
    let block: (String?) -> TimeBlock?

    var body: some View {
        HStack(spacing: 3) {
            ForEach([1, 2, 3, 4, 5, 6, 0], id: \.self) { w in
                let b = days.indices.contains(w) ? block(days[w]) : nil
                VStack(spacing: 0) {
                    Text(["日", "月", "火", "水", "木", "金", "土"][w]).font(.system(size: 9)).foregroundStyle(.secondary)
                    Text(b?.short ?? "－").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(b.map { PaletteColor.fg($0.colorIndex) } ?? Color(.tertiaryLabel))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                .background(b.map { PaletteColor.bg($0.colorIndex) } ?? Color.clear, in: RoundedRectangle(cornerRadius: 4))
            }
        }
    }
}
