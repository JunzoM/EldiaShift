import SwiftUI

/// シフト表（月・週。左に名前、右に日付）
/// 月は横に動かして見る。週は7日を画面の幅に収め、マスを大きくして勤務時間も出す
struct MonthGridView: View {
    let mode: GridMode
    let days: [DayKey]
    /// 日付を押したとき（その日のタイムラインへ）
    var onOpenDay: (DayKey) -> Void = { _ in }

    @Environment(\.shiftStore) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selected: Selection?

    private struct Selection: Identifiable {
        let member: StaffMember
        let day: DayKey
        var id: String { CellKey(staffID: member.id, day: day).description }
    }

    /// スタッフの設定を開く（名前の下の「＋パターン」など）
    private struct StaffSheet: Identifiable {
        let member: StaffMember
        let isNew: Bool
        var id: String { member.id }
    }

    /// 表の1行（名前の列と表の本体を同じ並び・同じ高さで描くため）
    private enum Row: Identifiable {
        case section(Department, Int)
        case staff(StaffMember)
        case hourToggle(Department, [StaffMember])
        case hour(Department, [StaffMember], Int)

        var id: String {
            switch self {
            case .section(let d, _): "s-\(d.id)"
            case .staff(let m): "m-\(m.id)"
            case .hourToggle(let d, _): "t-\(d.id)"
            case .hour(let d, _, let h): "h-\(d.id)-\(h)"
            }
        }
    }

    @AppStorage("showInactive") private var showInactive = false
    @State private var openHourly: Set<String> = DemoMode.hourly ? ["hall", "kitchen"] : []
    @State private var staffSheet: StaffSheet?
    @State private var saveError: String?
    /// まとめて入れるために選んだマス
    @State private var selecting = false
    @State private var picked: Set<CellKey> = []
    @State private var pickAnchor: CellKey?
    @State private var shortage: ShortageTarget?
    @State private var showRequests = false

    private var compact: Bool { sizeClass == .compact }
    private var nameWidth: CGFloat { compact ? 104 : 156 }
    @State private var availableWidth: CGFloat = 0
    private var isWeek: Bool { mode == .week }
    private var cellWidth: CGFloat {
        guard isWeek else { return compact ? 46 : 54 }
        return max(compact ? 64 : 96, (availableWidth - nameWidth - summaryWidth) / 7)
    }
    private var rowHeight: CGFloat { isWeek ? (compact ? 78 : 70) : 58 }
    private let headerHeight: CGFloat = 46
    private let sectionHeight: CGFloat = 28
    private let toggleHeight: CGFloat = 44
    private let hourHeight: CGFloat = 22
    private let summaryWidth: CGFloat = 70
    /// 時間帯別在籍人数の並び（PC版と同じ：9時〜翌8時）
    private let hours = [9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 0, 1, 2, 3, 4, 5, 6, 7, 8]

    @State private var scroll = ScrollTracker()

    private func rows(_ groups: [DepartmentGroup]) -> [Row] {
        var out: [Row] = []
        for g in groups {
            out.append(.section(g.department, g.members.count))
            out += g.members.map(Row.staff)
            out.append(.hourToggle(g.department, g.members))
            if openHourly.contains(g.department.id) {
                out += hours.map { Row.hour(g.department, g.members, $0) }
            }
        }
        return out
    }

    private func height(_ r: Row) -> CGFloat {
        switch r {
        case .section: sectionHeight
        case .staff: rowHeight
        case .hourToggle: toggleHeight
        case .hour: hourHeight
        }
    }

    /// 重い計算の結果（シフトの中身・表示する日・退職者の表示が変わったときだけ作り直す。
    /// マスを押してシートを開く・まとめて選ぶ、などでは作り直さない）
    @State private var memo = GridMemo()

    var body: some View {
        let book = store.book
        let calc = memo.get(book, revision: store.revision, days: days, showInactive: showInactive)
        let rows = rows(calc.groups)
        let shown = calc.shown
        let table = calc.table
        let today = store.today
        // 連勤・勤務の間隔・週の時間・希望休の注意
        let issues = calc.issues
        // 必要人数に足りない日（日付の上に赤い点）
        let shortDays = calc.shortDays

        // 上：日付の行（縦には動かない。横は下の表と同じだけずらす）
        // 下：縦に動く。左に名前の列、右に横に動く表
        // 画面の幅は外から受け取る（表の中身の幅を測ると、広がった幅をまた使ってしまい、名前の列が画面の外に出る）
        GeometryReader { geo in
        VStack(spacing: 0) {
            toolbarRow(table: table, shown: shown)
            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("No").frame(width: 26)
                    Text("氏名").frame(maxWidth: .infinity, alignment: .leading)
                }
                .appFont(.caption.weight(.bold)).foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .frame(width: nameWidth, height: headerHeight)
                .overlay(alignment: .trailing) { Divider() }
                FollowingHeader(tracker: scroll) {
                    HStack(spacing: 0) {
                        ForEach(days, id: \.self) { d in
                            dayHeader(d, today: today, short: shortDays.contains(d))
                                .contentShape(Rectangle())
                                .onTapGesture { onOpenDay(d) }
                                .accessibilityAddTraits(.isButton)
                                .accessibilityHint("その日のタイムラインを開きます")
                        }
                        summaryHeader
                    }
                }
            }
            .frame(height: headerHeight)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }

            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        ForEach(rows) { r in leftCell(r, book: book).frame(height: height(r)) }
                    }
                    .frame(width: nameWidth)
                    .overlay(alignment: .trailing) { Divider() }

                    ScrollViewReader { proxy in
                        ScrollView(.horizontal) {
                            VStack(spacing: 0) {
                                // スクロール位置を合わせるための目印（日付ごと）
                                HStack(spacing: 0) {
                                    ForEach(days, id: \.self) { d in Color.clear.frame(width: cellWidth, height: 1).id(d) }
                                }
                                ForEach(rows) { r in
                                    rightCells(r, book: book, table: table, today: today, issues: issues, shown: shown, calc: calc).frame(height: height(r))
                                }
                            }
                            .background(GeometryReader { g in
                                // iOS 17 用：表の位置が変わったら日付の行を合わせる（iOS 18 以降は下の onScrollGeometryChange）
                                let x = g.frame(in: .named("gridH")).minX
                                Color.clear
                                    .onAppear { scroll.x = max(0, -x) }
                                    .onChange(of: x) { scroll.x = max(0, -x) }
                            })
                        }
                        .coordinateSpace(name: "gridH")
                        // 横に動く表の幅は「画面の幅 − 名前の列」に固定する（中身の幅に合わせて広がると、名前の列が画面の外に押し出される）
                        .frame(width: max(0, availableWidth - nameWidth))
                        .scrollDisabled(isWeek && cellWidth * 7 + summaryWidth <= availableWidth - nameWidth + 1)
                        .modifier(TrackHorizontalScroll(tracker: scroll))
                        .onAppear { scrollToToday(proxy, days: days, today: today) }
                        .onChange(of: days) { scrollToToday(proxy, days: days, today: today) }
                    }
                }
            }
        }
        .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        .onAppear { availableWidth = geo.size.width }
        .onChange(of: geo.size.width) { availableWidth = geo.size.width }
        }
        .shiftSheet(item: $selected) { s in
            if store.editing {
                CellEditorSheet(member: s.member, day: s.day)
                    .presentationDetents([.medium, .large])
            } else {
                CellDetailSheet(member: s.member, day: s.day)
                    .presentationDetents([.medium])
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selecting { selectionBar(book) }
        }
        .shiftSheet(item: $shortage) { t in CandidatesSheet(target: t).presentationDetents([.medium, .large]) }
        .shiftSheet(isPresented: $showRequests) { OffRequestSheet(month: MonthKey(days[days.count / 2])) }
        .onChange(of: store.editing) { if !store.editing { selecting = false; picked = []; pickAnchor = nil } }
        .errorAlert($saveError)
        .shiftSheet(item: $staffSheet) { s in
            if s.isNew {
                StaffEditView(member: s.member, isNew: true)
            } else {
                NavigationStack { StaffEditView(member: s.member, isNew: false, inSheet: true) }
            }
        }
    }

    // MARK: 表の上の操作

    private func toolbarRow(table: ScheduleTable, shown: [StaffMember]) -> some View {
        // iPhone では入りきらないので、横に動かせるようにする
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                Button {
                    staffSheet = StaffSheet(member: store.newStaff(in: store.book.scopedDepartments.first?.id ?? store.book.departments.first?.id ?? ""), isNew: true)
                } label: {
                    Label("スタッフを追加", systemImage: "person.badge.plus")
                }
                Toggle("退職者も表示", isOn: $showInactive)
                    .toggleStyle(.button)
                Spacer(minLength: 0)
                if !compact {
                    // シフトの種類の凡例
                    HStack(spacing: 6) {
                        ForEach(store.book.templates.prefix(8)) { t in
                            ShiftChip(text: t.label, colorIndex: t.colorIndex, height: 24, fontSize: 12).fixedSize()
                        }
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Color.orange.opacity(0.8)).frame(width: 6, height: 6)
                        Text("自動")
                    }
                    .appFont(.caption).foregroundStyle(.secondary)
                }
                if store.editing {
                    UndoRedoButtons()
                    Toggle(isOn: Binding(get: { selecting }, set: { selecting = $0; if !$0 { picked = []; pickAnchor = nil } })) {
                        Label("まとめて選ぶ", systemImage: "checklist")
                    }
                    .toggleStyle(.button)
                    Menu {
                        Button { showRequests = true } label: { Label("希望休を入れる", systemImage: "calendar.badge.minus") }
                        if isWeek {
                            Button { copyWeek(table: table, shown: shown) } label: {
                                Label("この週を翌週へコピー", systemImage: "doc.on.doc")
                            }
                        }
                    } label: {
                        Label("便利な操作", systemImage: "ellipsis.circle")
                    }
                    EditingChip()
                } else {
                    Text("ロック中（鉛筆で編集）").appFont(.caption).foregroundStyle(.secondary)
                }
            }
            .appFont(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minWidth: availableWidth, alignment: .leading)
        }
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: まとめて入れる

    private func togglePick(_ key: CellKey) {
        if picked.contains(key) { picked.remove(key) } else { picked.insert(key); pickAnchor = key }
    }

    /// 前に選んだマスから key までの四角（人×日）を選ぶ
    private func pickRange(to key: CellKey, shown: [StaffMember]) {
        guard let a = pickAnchor,
              let r1 = shown.firstIndex(where: { $0.id == a.staffID }), let r2 = shown.firstIndex(where: { $0.id == key.staffID }),
              let c1 = days.firstIndex(of: a.day), let c2 = days.firstIndex(of: key.day) else {
            togglePick(key)
            return
        }
        for r in min(r1, r2)...max(r1, r2) {
            for c in min(c1, c2)...max(c1, c2) where !shown[r].hasLeft(on: days[c]) {
                picked.insert(CellKey(staffID: shown[r].id, day: days[c]))
            }
        }
        pickAnchor = key
    }

    private func selectionBar(_ book: ShiftBook) -> some View {
        let common = book.templates.filter { !$0.isOff }
        let off = book.templates.filter(\.isOff)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(picked.count)マスを選択中").appFont(.subheadline.weight(.bold)).monospacedDigit()
                Text("押して選ぶ・長押しで前のマスから四角く選ぶ").appFont(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Menu {
                Section("勤務") {
                    ForEach(common) { b in Button("\(b.label)（\(b.inTime)〜\(b.outTime)）") { applyPicked(b) } }
                }
                Section("休み") {
                    ForEach(off) { b in Button(b.label) { applyPicked(b) } }
                }
                Section {
                    Button("自動（パターン）に戻す", role: .destructive) { applyPicked(nil) }
                }
            } label: {
                Label("入れる", systemImage: "square.and.pencil").appFont(.subheadline.weight(.bold))
            }
            .buttonStyle(.borderedProminent)
            .disabled(picked.isEmpty)
            Button("選び直す") { picked = []; pickAnchor = nil }.disabled(picked.isEmpty)
            Button("終える") { selecting = false; picked = []; pickAnchor = nil }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func applyPicked(_ b: TimeBlock?) {
        let entry: CellEntry? = b.map {
            $0.isOff ? CellEntry(inTime: "", outTime: "", blockID: $0.id, isOff: true)
                     : CellEntry(inTime: $0.inTime, outTime: $0.outTime, blockID: $0.id, isOff: false)
        }
        let n = picked.count
        let keys = picked.sorted { a, b in a.day != b.day ? a.day < b.day : a.staffID < b.staffID }
        do {
            try store.setCells(keys.map { ($0, entry) }, title: "\(n)マスを「\(b?.label ?? "自動")」にしました")
            picked = []
            pickAnchor = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    /// 表示している週を、翌週の同じ曜日へ写す（同じ内容になる日は飛ばす）
    private func copyWeek(table: ScheduleTable, shown: [StaffMember]) {
        let book = store.book
        var items: [(CellKey, CellEntry?)] = []
        for m in shown {
            for d in days {
                let to = d.adding(days: 7)
                guard !m.hasLeft(on: to), let r = table.get(m, d) else { continue }
                let entry = CellEntry(inTime: r.inTime, outTime: r.outTime, blockID: r.blockID, isOff: r.isOff,
                                      storeID: r.isOff ? nil : r.storeID)
                if let now = Schedule.resolve(m, on: to, in: book),
                   now.inTime == entry.inTime, now.outTime == entry.outTime, now.blockID == entry.blockID, now.isOff == entry.isOff,
                   now.isOff || now.storeID == entry.storeID {
                    continue
                }
                items.append((CellKey(staffID: m.id, day: to), entry))
            }
        }
        guard !items.isEmpty else { saveError = "翌週はもう同じ内容です。"; return }
        do { try store.setCells(items, title: "この週を翌週へコピーしました（\(items.count)マス）") }
        catch { saveError = error.localizedDescription }
    }

    // MARK: 行の中身

    @ViewBuilder
    private func leftCell(_ r: Row, book: ShiftBook) -> some View {
        switch r {
        case .section(let d, let n):
            sectionLabel(d, count: n)
        case .staff(let m):
            nameCell(m, book: book)
        case .hourToggle(let d, _):
            Button { toggleHourly(d) } label: {
                HStack(spacing: 6) {
                    Image(systemName: openHourly.contains(d.id) ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                        .appFont(.body)
                    Text("時間帯別在籍人数").appFont(.subheadline.weight(.bold)).lineLimit(1).minimumScaleFactor(0.6)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 8)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .coachTarget("hourly-\(d.id)")
            .overlay(alignment: .bottom) { Divider() }
        case .hour(_, _, let h):
            let night = h <= 8
            HStack(spacing: 0) {
                Text(night ? "明" : "").appFont(.system(size: 9)).foregroundStyle(.secondary).frame(width: 26)
                Text(String(format: "%02d:00", h)).appFont(.system(size: 11, weight: .bold)).monospacedDigit()
                    .foregroundStyle(night ? Color.blue : Color.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(maxHeight: .infinity)
            .background(night ? Color.blue.opacity(0.06) : Color(.secondarySystemBackground).opacity(0.4))
        }
    }

    @ViewBuilder
    private func rightCells(_ r: Row, book: ShiftBook, table: ScheduleTable, today: DayKey,
                            issues: [CellKey: [LaborIssue]], shown: [StaffMember], calc: GridMemo.Result) -> some View {
        switch r {
        case .section:
            Rectangle().fill(Color(.secondarySystemBackground))
                .frame(width: cellWidth * CGFloat(days.count) + summaryWidth)
        case .staff(let m):
            HStack(spacing: 0) {
                ForEach(days, id: \.self) { d in
                    let key = CellKey(staffID: m.id, day: d)
                    ShiftCellView(member: m, day: d, resolved: table.get(m, d),
                                  book: book, isToday: d == today, compact: compact, large: isWeek,
                                  issues: issues[key] ?? [], requested: m.requestsOff(d), picked: picked.contains(key))
                        .frame(width: cellWidth, height: rowHeight)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !m.hasLeft(on: d) else { return }
                            if selecting { togglePick(key) } else { selected = Selection(member: m, day: d) }
                        }
                        .onLongPressGesture(minimumDuration: 0.35) {
                            // 選んでいるとき：前に選んだマスからここまでを四角く選ぶ
                            if selecting { pickRange(to: key, shown: shown) }
                        }
                }
                summaryCell(table.summary(m, days: days))
            }
            .overlay(alignment: .bottom) { Divider() }
        case .hourToggle(let dept, _):
            let plan = book.staffing
            if plan.hasPlan(for: dept.id) {
                // 必要人数を決めている部門は、閉じていても日ごとの不足が見える
                HStack(spacing: 0) {
                    ForEach(days, id: \.self) { d in
                        let g = calc.gaps[dept.id]?[d] ?? StaffingGap()
                        Group {
                            if g.short > 0 {
                                // 押すと、その日に入れられる人を出す
                                Button { shortage = ShortageTarget(department: dept, day: d) } label: {
                                    Text("−\(g.short)").appFont(.system(size: 11, weight: .heavy)).monospacedDigit()
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4).padding(.vertical, 3)
                                        .background(StaffingStyle.short, in: RoundedRectangle(cornerRadius: 4))
                                        .frame(width: cellWidth, height: toggleHeight)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(d.day)日 \(dept.name) 不足 \(g.short)人時。入れられる人を見る")
                            } else {
                                Image(systemName: "checkmark").appFont(.system(size: 9, weight: .bold)).foregroundStyle(StaffingStyle.ok.opacity(0.7))
                            }
                        }
                        .frame(width: cellWidth, height: toggleHeight)
                    }
                    Text("不足").appFont(.system(size: 9)).foregroundStyle(.secondary).frame(width: summaryWidth)
                }
                .background(Color(.systemBackground))
                .overlay(alignment: .bottom) { Divider() }
                .contentShape(Rectangle())
                .onTapGesture { toggleHourly(dept) }
            } else {
                Color(.systemBackground)
                    .frame(width: cellWidth * CGFloat(days.count) + summaryWidth)
                    .overlay(alignment: .bottom) { Divider() }
                    .contentShape(Rectangle())
                    .onTapGesture { toggleHourly(dept) }
            }
        case .hour(let dept, _, let h):
            let night = h <= 8
            HStack(spacing: 0) {
                ForEach(days, id: \.self) { d in
                    let n = calc.hourly.count(dept.id, on: d, hour: h)
                    let need = calc.needs[dept.id]?[d]?[h] ?? nil
                    if let need, let c = StaffingStyle.color(n, need: need) {
                        // 必要人数がある時間：実際/必要 を色で（足りない＝赤、多い＝オレンジ）
                        HStack(spacing: 0) {
                            Text("\(n)").appFont(.system(size: 12, weight: .heavy))
                            Text("/\(need)").appFont(.system(size: 8)).foregroundStyle(.secondary)
                        }
                        .monospacedDigit()
                        .foregroundStyle(n < need ? Color.white : c)
                        .frame(width: cellWidth, height: hourHeight)
                        .background(n < need ? c.opacity(0.85) : c.opacity(0.15))
                        .overlay(alignment: .trailing) { Rectangle().fill(Color(.separator)).frame(width: 0.5) }
                        .contentShape(Rectangle())
                        .onTapGesture { if n < need { shortage = ShortageTarget(department: dept, day: d) } }
                        .accessibilityLabel("\(h)時 \(n)人（必要\(need)人）")
                        .accessibilityAddTraits(n < need ? .isButton : [])
                    } else {
                    Text(n == 0 ? "0" : "\(n)")
                        .appFont(.system(size: n > 2 ? 13 : 11, weight: n > 2 ? .heavy : n > 0 ? .bold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(n == 0 ? Color(.tertiaryLabel) : night ? Color.blue : Color.green)
                        .frame(width: cellWidth, height: hourHeight)
                        .background(n > 0 ? (night ? Color.blue.opacity(0.15) : Color.green.opacity(0.15)) : Color.clear)
                        .overlay(alignment: .trailing) { Rectangle().fill(Color(.separator)).frame(width: 0.5) }
                    }
                }
                Color.clear.frame(width: summaryWidth, height: hourHeight)
            }
            .background(night ? Color.blue.opacity(0.04) : Color(.secondarySystemBackground).opacity(0.3))
        }
    }

    private func scrollToToday(_ proxy: ScrollViewProxy, days: [DayKey], today: DayKey) {
        // 左には名前の列が重なるので、今日の数日前を左端に合わせる
        // 週は月曜から見せる（動かさない）。月は今日の数日前を左端に
        guard !isWeek else { return }
        let target = days.contains(today) ? today.adding(days: -(compact ? 2 : 3)) : nil
        if let target, days.contains(target) { proxy.scrollTo(target, anchor: .leading) }
        else if let first = days.first { proxy.scrollTo(first, anchor: .leading) }
    }

    // MARK: 部品

    private func sectionLabel(_ d: Department, count: Int) -> some View {
        HStack(spacing: 6) {
            Circle().fill(PaletteColor.fg(d.colorIndex)).frame(width: 8, height: 8)
            Text(d.name).appFont(.caption.bold()).foregroundStyle(PaletteColor.fg(d.colorIndex))
            Text("\(count)人").appFont(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        .background(Color(.secondarySystemBackground))
    }

    /// 番号・名前・使う週間パターン（切り替え）・個人の時間
    private func nameCell(_ m: StaffMember, book: ShiftBook) -> some View {
        let active = m.patterns.first { $0.id == m.activePatternID }
        return HStack(alignment: .center, spacing: 0) {
            Text("\(m.number)").appFont(.caption2).foregroundStyle(.secondary).monospacedDigit().frame(width: 22)
            if !compact {
                InitialAvatar(name: m.name, colorIndex: book.departments.first { $0.id == m.departmentID }?.colorIndex ?? 8, size: 28, photo: m.photo)
                    .padding(.trailing, 6)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(m.name)
                    .appFont(compact ? .footnote.weight(.bold) : .subheadline.weight(.bold))
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .foregroundStyle(m.active && m.leaveDate.isEmpty ? Color.primary : Color.secondary)
                if m.active {
                    if m.patterns.isEmpty {
                        Button("＋パターン") { staffSheet = StaffSheet(member: m, isNew: false) }
                            .appFont(.caption2).foregroundStyle(.secondary)
                    } else {
                        Menu {
                            ForEach(m.patterns) { p in
                                Button {
                                    var x = m
                                    x.activePatternID = p.id
                                    do { try store.save(x) } catch { saveError = error.localizedDescription }
                                    CoachCenter.shared.show(.pattern("pattern-\(m.id)"), after: 0.5)
                                } label: {
                                    if p.id == m.activePatternID { Label(patternTitle(p), systemImage: "checkmark") }
                                    else { Text(patternTitle(p)) }
                                }
                            }
                        } label: {
                            Text(active?.label ?? "パターン").appFont(.caption2.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .foregroundStyle(PaletteColor.fg(active?.colorIndex ?? 8))
                                .background(PaletteColor.bg(active?.colorIndex ?? 8), in: RoundedRectangle(cornerRadius: 4))
                        }
                        .coachTarget("pattern-\(m.id)")
                    }
                }
                if !m.timeBlocks.isEmpty && !compact {
                    Button("個人の時間 \(m.timeBlocks.count)件") { staffSheet = StaffSheet(member: m, isNew: false) }
                        .appFont(.system(size: 10)).foregroundStyle(Color.accentColor)
                }
            }
            Spacer(minLength: 0)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 4)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .contextMenu {
            Button("スタッフの設定を開く") { staffSheet = StaffSheet(member: m, isNew: false) }
        }
        .overlay(alignment: .bottom) { Divider() }
    }

    private func patternTitle(_ p: WeekPattern) -> String {
        (p.label.isEmpty ? "パターン" : p.label) + (p.activeFrom.map { "（\($0)〜）" } ?? "（標準）")
    }

    /// 時間帯別在籍人数を開く・閉じる（左の見出しでも、右の行のどこを押しても）
    private func toggleHourly(_ d: Department) {
        if openHourly.contains(d.id) { openHourly.remove(d.id) } else {
            openHourly.insert(d.id)
            CoachCenter.shared.show(.hourly("hourly-\(d.id)"), after: 0.3)
        }
    }

    private func dayHeader(_ d: DayKey, today: DayKey, short: Bool) -> some View {
        let holiday = JapaneseHolidays.name(d)
        let color: Color = (d.weekday == 0 || holiday != nil) ? .red : d.weekday == 6 ? .blue : .primary
        let wd = ["日", "月", "火", "水", "木", "金", "土"][d.weekday]
        return VStack(spacing: 1) {
            if isWeek {
                Text("\(d.month)/\(d.day)（\(wd)）").appFont(.subheadline.weight(.bold)).monospacedDigit()
                if let holiday { Text(holiday).appFont(.caption2).lineLimit(1) }
            } else {
                Text("\(d.day)").appFont(.subheadline.weight(.bold)).monospacedDigit()
                Text(wd).appFont(.caption2)
            }
        }
        .foregroundStyle(color)
        .frame(width: cellWidth, height: headerHeight)
        .background(d == today ? Color.accentColor.opacity(0.15) : .clear)
        .overlay(alignment: .topTrailing) {
            if short { Circle().fill(StaffingStyle.short).frame(width: 6, height: 6).padding(3) }
        }
        .overlay(alignment: .topLeading) {
            let t = store.book.staffing.type(of: d)
            if !store.book.staffing.isEmpty, t == .busy || t == .quiet {
                Text(t.short).appFont(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 2)
                    .background(t == .busy ? Color.red : Color.brown, in: RoundedRectangle(cornerRadius: 2))
                    .padding(2)
            }
        }
        .contextMenu {
            if !store.book.staffing.isEmpty {
                let cur = store.book.staffing.type(of: d)
                Section("この日の型（適正人員）") {
                    ForEach(DayType.allCases) { x in
                        Button {
                            var p = store.book.staffing
                            p.setType(x, for: d)
                            do { try store.setStaffing(p) } catch { saveError = error.localizedDescription }
                        } label: {
                            if x == cur { Label(x.title, systemImage: "checkmark") } else { Text(x.title) }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(d.month)月\(d.day)日\(holiday.map { "、\($0)" } ?? "")\(short ? "、人が足りない時間あり" : "")")
    }

    private var summaryHeader: some View {
        Text("合計").appFont(.caption.weight(.bold)).foregroundStyle(.secondary)
            .frame(width: summaryWidth, height: headerHeight)
    }

    private func summaryCell(_ s: MonthSummary) -> some View {
        VStack(spacing: 1) {
            Text("\(s.workDays)日").appFont(.caption.weight(.semibold))
            Text(String(format: "%.1fh", s.hours)).appFont(.caption2).foregroundStyle(.secondary)
        }
        .monospacedDigit()
        .frame(width: summaryWidth, height: rowHeight)
        .background(Color(.secondarySystemBackground).opacity(0.5))
        .accessibilityElement(children: .combine)
    }
}

/// 月の表の重い計算（勤務・注意・時間帯別の人数・不足）を覚えておく入れ物。
/// 観察しない（@Observable にしない）ので、画面を描く途中で中身を入れ替えても描き直しは起きない
final class GridMemo {
    struct Key: Equatable {
        var revision: Int
        var days: [DayKey]
        var showInactive: Bool
    }

    struct Result {
        var groups: [DepartmentGroup]
        var shown: [StaffMember]
        var table: ScheduleTable
        var issues: [CellKey: [LaborIssue]]
        var hourly: HourlyCounts
        /// 部門 → 日 → 0〜23時台の必要人数
        var needs: [String: [DayKey: [Int?]]]
        var gaps: [String: [DayKey: StaffingGap]]
        var shortDays: Set<DayKey>
    }

    private var key: Key?
    private var result: Result?

    func get(_ book: ShiftBook, revision: Int, days: [DayKey], showInactive: Bool) -> Result {
        let k = Key(revision: revision, days: days, showInactive: showInactive)
        if k == key, let result { return result }
        let r = Self.make(book, days: days, showInactive: showInactive)
        key = k
        result = r
        return r
    }

    static func make(_ book: ShiftBook, days: [DayKey], showInactive: Bool) -> Result {
        let groups = book.staffByDepartment(visibleIn: MonthKey(days[0]), includeInactive: showInactive)
        let shown = groups.flatMap(\.members)
        let table = ScheduleTable(book: book, members: shown, days: days)
        let hourly = HourlyCounts(groups: groups, days: days, table: table)
        var needs: [String: [DayKey: [Int?]]] = [:]
        var gaps: [String: [DayKey: StaffingGap]] = [:]
        var short = Set<DayKey>()
        for g in groups where book.staffing.hasPlan(for: g.department.id) {
            var n: [DayKey: [Int?]] = [:], gp: [DayKey: StaffingGap] = [:]
            for d in days {
                let c = (0..<24).map { hourly.count(g.department.id, on: d, hour: $0) }
                n[d] = book.staffing.needs(g.department.id, on: d)
                let gap = StaffingCheck.gap(book.staffing, department: g.department.id, on: d, counts: c)
                gp[d] = gap
                if gap.short > 0 { short.insert(d) }
            }
            needs[g.department.id] = n
            gaps[g.department.id] = gp
        }
        return Result(groups: groups, shown: shown, table: table,
                      issues: LaborCheck.issues(book, members: shown, days: days),
                      hourly: hourly, needs: needs, gaps: gaps, shortDays: short)
    }
}

/// 表を横に動かした量（日付の行だけがこれを見る。表の本体は動かすたびに作り直さない）
@MainActor
@Observable
final class ScrollTracker {
    var x: CGFloat = 0
}

/// iOS 18 以降は、スクロールの位置をそのまま受け取る（確実で軽い）
private struct TrackHorizontalScroll: ViewModifier {
    let tracker: ScrollTracker

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.x + geo.contentInsets.leading
            } action: { _, x in
                tracker.x = max(0, x)
            }
        } else {
            content
        }
    }
}

/// 下の表を横に動かした分だけ、日付の行をずらす
private struct FollowingHeader<Content: View>: View {
    let tracker: ScrollTracker
    @ViewBuilder let content: Content

    var body: some View {
        // 重ねて置くだけにして、日付の行の幅が画面の幅に影響しないようにする
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .leading) {
                content.fixedSize().offset(x: -tracker.x)
            }
            .clipped()
    }
}

/// 1人×1日のマス
struct ShiftCellView: View {
    let member: StaffMember
    let day: DayKey
    let resolved: ResolvedShift?
    let book: ShiftBook
    let isToday: Bool
    let compact: Bool
    /// 週表示（マスが大きい）：時刻を大きく、勤務時間とひな形の名前も出す
    var large = false
    /// 連勤などの注意
    var issues: [LaborIssue] = []
    /// 希望休の日
    var requested = false
    /// まとめて入れるために選んでいる
    var picked = false

    var body: some View {
        let block = book.block(resolved?.blockID, for: member)
        ZStack {
            background(block)
            content(block)
        }
        .overlay(alignment: large ? .bottomTrailing : .topTrailing) {
            // 自動（くり返し・期間の予定）で決まったマスの印。時刻に重ならないよう隅に小さく
            if resolved?.isAuto == true {
                Circle().fill(Color.orange.opacity(0.8)).frame(width: 5, height: 5).padding(large ? 5 : 2)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: large ? .topTrailing : .bottomTrailing) {
            // メモがある日の印（自動で決まったマスの印と重ならない隅に）
            if let n = resolved?.note, !n.isEmpty {
                Image(systemName: "note.text").appFont(.system(size: large ? 10 : 7, weight: .bold))
                    .foregroundStyle(Color.secondary).padding(large ? 4 : 1.5)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .topLeading) {
            if !issues.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .appFont(.system(size: large ? 11 : 9))
                    .foregroundStyle(issues.contains(.requestedOff) ? Color.purple : Color.orange)
                    .padding(2)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if requested {
                Text("希").appFont(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 2)
                    .background(Color.purple, in: RoundedRectangle(cornerRadius: 2))
                    .padding(2)
            }
        }
        .overlay {
            if picked {
                Rectangle().fill(Color.accentColor.opacity(0.18))
                    .overlay(Rectangle().strokeBorder(Color.accentColor, lineWidth: 2.5))
            }
        }
        .overlay(alignment: .trailing) { Rectangle().fill(Color(.separator)).frame(width: 0.5) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(block))
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    @ViewBuilder
    private func background(_ block: TimeBlock?) -> some View {
        if member.hasLeft(on: day) {
            Color(.secondarySystemBackground)
        } else if resolved?.elsewhere == true {
            // ほかの店舗で勤務する日：斜線で薄く
            Color(.secondarySystemBackground)
                .overlay(ElsewhereHatch().opacity(0.5))
        } else if resolved?.isOff == true && large {
            PaletteColor.bg(block?.colorIndex ?? 8)
        } else if isToday {
            Color.accentColor.opacity(0.10)
        } else if day.weekday == 0 || JapaneseHolidays.isHoliday(day) {
            Color.red.opacity(0.04)
        } else if day.weekday == 6 {
            Color.blue.opacity(0.04)
        } else {
            Color(.systemBackground)
        }
    }

    @ViewBuilder
    private func content(_ block: TimeBlock?) -> some View {
        if member.hasLeft(on: day) {
            Text("－").appFont(.caption2).foregroundStyle(.tertiary)
        } else if let r = resolved, r.elsewhere {
            VStack(spacing: 2) {
                if let st = book.store(r.storeID) { StoreTag(store: st, label: book.shortName(of: st), size: large ? 11 : 9) }
                Text(r.inTime.isEmpty ? "—" : r.inTime).appFont(.system(size: large ? 12 : 10)).foregroundStyle(.secondary)
                if large { Text(r.outTime).appFont(.system(size: 11)).foregroundStyle(.tertiary) }
            }
            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        } else if let r = resolved {
            if r.isOff {
                if large {
                    Text(block?.label ?? "休み")
                        .appFont(.headline)
                        .foregroundStyle(PaletteColor.fg(block?.colorIndex ?? 8))
                } else {
                    ShiftChip(text: block.map(ShiftChip.label) ?? "休み", colorIndex: block?.colorIndex ?? 8)
                        .padding(.horizontal, 4)
                }
            } else {
                if large {
                    VStack(spacing: 2) {
                        if compact {
                            // iPhone は幅が狭いので、出勤・退勤を2行に
                            Text(r.inTime.isEmpty ? "—" : r.inTime).appFont(.system(size: 13, weight: .bold))
                            Text(r.outTime.isEmpty ? "—" : r.outTime).appFont(.system(size: 13)).foregroundStyle(.secondary)
                        } else {
                            Text("\(r.inTime.isEmpty ? "—" : r.inTime)〜\(r.outTime.isEmpty ? "—" : r.outTime)")
                                .appFont(.system(size: 14, weight: .bold))
                        }
                        HStack(spacing: 4) {
                            if let block {
                                Text(block.label).foregroundStyle(PaletteColor.fg(block.colorIndex)).fontWeight(.bold)
                            }
                            if let h = r.netHours(book.breakRules) { Text(String(format: "%.1fh", h)).foregroundStyle(.secondary) }
                        }
                        .appFont(.caption2)
                    }
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 2)
                } else {
                // 月：シフトの種類のチップと、その下に短い時刻（ひな形のままでない日は時刻をチップに）
                VStack(spacing: 2) {
                    if let block, block.inTime == r.inTime, block.outTime == r.outTime {
                        ShiftChip(text: ShiftChip.label(block), colorIndex: block.colorIndex)
                        Text("\(ShortTime.compact(r.inTime))-\(ShortTime.compact(r.outTime))")
                            .appFont(.system(size: 9)).foregroundStyle(.secondary)
                    } else {
                        ShiftChip(text: r.inTime.isEmpty ? "—" : r.inTime, colorIndex: block?.colorIndex ?? 8)
                        Text("〜\(r.outTime)").appFont(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 4)
                }
            }
        }
    }

    private func accessibilityText(_ block: TimeBlock?) -> String {
        let extra = (requested ? "、希望休" : "") + (issues.isEmpty ? "" : "、注意：" + issues.map(\.text).joined(separator: "、"))
            + (resolved?.note.map { "、メモ：\($0)" } ?? "")
        return base(block) + extra
    }

    private func base(_ block: TimeBlock?) -> String {
        let date = "\(day.month)月\(day.day)日 \(member.name)"
        if member.hasLeft(on: day) { return "\(date)、退職後" }
        guard let r = resolved else { return "\(date)、未定" }
        if r.isOff { return "\(date)、\(block?.label ?? "休み")" }
        if r.elsewhere { return "\(date)、\(book.store(r.storeID)?.name ?? "ほかの店舗")で\(r.inTime)から\(r.outTime)" }
        return "\(date)、\(r.inTime)から\(r.outTime)\(r.isAuto ? "、自動" : "")"
    }
}

/// ほかの店舗で勤務する日の斜線
struct ElsewhereHatch: View {
    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                p.move(to: CGPoint(x: x, y: size.height))
                p.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 7
            }
            ctx.stroke(p, with: .color(Color(.separator)), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

enum PaletteColor {
    static func fg(_ i: Int) -> Color { Color(hex: Palette.colors[Palette.index(i)].fg) }
    static func bg(_ i: Int) -> Color { Color(hex: Palette.colors[Palette.index(i)].bg) }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
