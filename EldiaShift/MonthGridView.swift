import SwiftUI

/// シフト表（月・週。左に名前、右に日付）
/// 月は横に動かして見る。週は7日を画面の幅に収め、マスを大きくして勤務時間も出す
struct MonthGridView: View {
    let mode: GridMode
    let days: [DayKey]
    /// 選んでいる日（Duo の見開き：右のページに出している日。日付に枠を付け、表をその日まで動かす）
    var selectedDay: DayKey? = nil
    /// 印を付ける人（Duo の見開き：閉じた画面で見ていた人）
    var highlightStaffID: String? = nil
    /// マスを押したとき（シートを開くのとは別に知らせる。Duo の見開きで右のページをその日にする）
    var onPickCell: (StaffMember, DayKey) -> Void = { _, _ in }
    /// 日付を押したとき（その日のタイムラインへ）
    var onOpenDay: (DayKey) -> Void = { _ in }

    @Environment(\.shiftStore) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// 文字の倍率（Mac の 表示 → 拡大・縮小）
    @Environment(\.appZoom) private var baseZoom
    /// iPhone・iPad の「文字の大きさ」
    @Environment(\.dynamicTypeSize) private var typeSize
    /// 表の倍率。文字だけ大きくするとマスからはみ出して切れるので、マスの幅・高さにも同じ倍率をかける。
    /// iPhone・iPad は「文字の大きさ」から決める（Mac は Dynamic Type が効かないので Mac の倍率だけ）
    private var zoom: CGFloat {
        #if targetEnvironment(macCatalyst)
        baseZoom
        #else
        baseZoom * AppFont.typeScale(typeSize)
        #endif
    }
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
    private var nameWidth: CGFloat { (compact ? 104 : 156) * zoom }
    @State private var availableWidth: CGFloat = 0
    /// 表（縦横に動く部分）の見えている大きさ
    @State private var viewport: CGSize = .zero
    private var isWeek: Bool { mode == .week }
    /// 週の表が画面の幅に収まる（横には動かさない）
    private var fitsWidth: Bool { isWeek && cellWidth * 7 + summaryWidth <= availableWidth - nameWidth + 1 }
    private var cellWidth: CGFloat {
        guard isWeek else { return (compact ? 46 : 54) * zoom }
        return max((compact ? 64 : 96) * zoom, (availableWidth - nameWidth - summaryWidth) / 7)
    }
    private var rowHeight: CGFloat { (isWeek ? (compact ? 78 : 70) : 58) * zoom }
    private var headerHeight: CGFloat { 46 * zoom }
    private var sectionHeight: CGFloat { 28 * zoom }
    private var toggleHeight: CGFloat { 44 * zoom }
    private var hourHeight: CGFloat { 22 * zoom }
    private var summaryWidth: CGFloat { 70 * zoom }
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
                    Text("No").frame(width: 26 * zoom)
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

            gridBody(rows: rows, book: book, table: table, today: today, issues: issues, shown: shown, calc: calc)
        }
        .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        .onAppear { availableWidth = geo.size.width }
        .onChange(of: geo.size.width) { availableWidth = geo.size.width }
        }
        // 表の中の文字（.appFont）にも同じ倍率を渡す。倍率が 1 でないとき .appFont は決まった大きさになるので、
        // 「文字の大きさ」と二重に大きくならない。下のシートには渡さない（シートはふつうの Dynamic Type のまま）
        .environment(\.appZoom, zoom)
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

    // MARK: 表の本体

    /// 表の本体。iOS 18 以降は、縦横に動く1つの表に「名前＋マス」の行を見えている分だけ作る（軽く、名前と行が必ずそろう）。
    /// iOS 17 はこの作りだと行を何度も作り直して月の切り替えが十数秒かかるので、前の作り（名前の列と横に動く表を並べる）にする
    @ViewBuilder
    private func gridBody(rows: [Row], book: ShiftBook, table: ScheduleTable, today: DayKey,
                          issues: [CellKey: [LaborIssue]], shown: [StaffMember], calc: GridMemo.Result) -> some View {
        if #available(iOS 18.0, *) {
            lazyTable(rows: rows, book: book, table: table, today: today, issues: issues, shown: shown, calc: calc)
        } else {
            classicTable(rows: rows, book: book, table: table, today: today, issues: issues, shown: shown, calc: calc)
        }
    }

    private func lazyTable(rows: [Row], book: ShiftBook, table: ScheduleTable, today: DayKey,
                           issues: [CellKey: [LaborIssue]], shown: [StaffMember], calc: GridMemo.Result) -> some View {
        // 縦横に動く1つの表。1行の中に「名前＋その人のマス」を入れるので、名前と行は必ずそろう。
        // 行は画面に見えている分だけ作る（人数・時間帯の行が多くても、全部のマスを一度に持たない）。
        // 名前の列は、横に動かしても左に貼り付く（PinnedColumn）
        ScrollViewReader { proxy in
            ScrollView(fitsWidth ? .vertical : [.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // スクロール位置を合わせるための目印（日付ごと）。マスより名前の列の幅だけ左に置くので、
                    // 目印を左端に合わせると、その日が名前の列のすぐ右に来る
                    HStack(spacing: 0) {
                        ForEach(days, id: \.self) { d in Color.clear.frame(width: cellWidth, height: 1).id(d) }
                    }
                    ForEach(rows) { r in
                        HStack(spacing: 0) {
                            PinnedColumn(tracker: scroll) {
                                leftCell(r, book: book)
                                    .frame(width: nameWidth, height: height(r))
                                    // 下を通るマスが透けないように
                                    .background(Color(.systemBackground))
                                    // 名前の列の右の線（Divider は置き場所によって向きが変わるので、幅を決めた線にする）
                                    .overlay(alignment: .trailing) { Rectangle().fill(Color(.separator)).frame(width: 0.5) }
                            }
                            .zIndex(1)
                            rightCells(r, book: book, table: table, today: today, issues: issues, shown: shown, calc: calc)
                                .frame(height: height(r))
                        }
                        .id(r.id)
                    }
                }
                // 中身が画面より小さいときも左上に寄せる（縦横に動く表は、そのままだと真ん中に置かれる）。
                // defaultScrollAnchor を使うと、中身が変わるたびに見えていない行まで測り直して月の切り替えが重くなるので、
                // 中身を見えている大きさ以上にして左上に置く
                .frame(minWidth: viewport.width, minHeight: viewport.height, alignment: .topLeading)
                .background(GeometryReader { g in
                    // iOS 17 用：表の位置が変わったら日付の行・名前の列を合わせる（iOS 18 以降は下の onScrollGeometryChange）
                    let x = g.frame(in: .named("gridH")).minX
                    Color.clear
                        .onAppear { scroll.x = max(0, -x) }
                        .onChange(of: x) { scroll.x = max(0, -x) }
                })
            }
            // 表の見えている大きさ（中身をこれより小さくしないために使う）
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { viewport = g.size }
                    .onChange(of: g.size) { viewport = g.size }
            })
            .coordinateSpace(name: "gridH")
            .modifier(TrackHorizontalScroll(tracker: scroll))
            .onAppear {
                scrollToToday(proxy, days: days, today: today)
                // 画面確認用：いちばん下・いちばん右まで動かした状態（名前と行がそろっているかを見る）
                if DemoMode.flag("-demoScrollEnd"), let last = rows.last?.id {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 800_000_000)
                        proxy.scrollTo(last, anchor: .bottomTrailing)
                    }
                }
            }
            .onChange(of: days) { scrollToToday(proxy, days: days, today: today) }
            // 週の表が画面に収まって横に動かなくなったら、名前の列・日付の行の位置も戻す
            .onChange(of: fitsWidth) { if fitsWidth { scroll.x = 0 } }
        }
    }

    /// iOS 17 用：左に名前の列、右に横に動く表を並べ、全体を縦に動かす（行はすべて作る。左右の行の高さは同じなのでそろう）
    private func classicTable(rows: [Row], book: ShiftBook, table: ScheduleTable, today: DayKey,
                              issues: [CellKey: [LaborIssue]], shown: [StaffMember], calc: GridMemo.Result) -> some View {
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    // 右の表の上にある目印の行（高さ1）と同じだけ空けて、左右の行をそろえる
                    Color.clear.frame(height: 1)
                    ForEach(rows) { r in leftCell(r, book: book).frame(height: height(r)) }
                }
                .frame(width: nameWidth)
                .overlay(alignment: .trailing) { Rectangle().fill(Color(.separator)).frame(width: 0.5) }

                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        VStack(spacing: 0) {
                            // スクロール位置を合わせるための目印（日付ごと）
                            HStack(spacing: 0) {
                                ForEach(days, id: \.self) { d in Color.clear.frame(width: cellWidth, height: 1).id(d) }
                            }
                            ForEach(rows) { r in
                                rightCells(r, book: book, table: table, today: today, issues: issues, shown: shown, calc: calc)
                                    .frame(height: height(r))
                            }
                        }
                        .background(GeometryReader { g in
                            // 表の位置が変わったら日付の行を合わせる
                            let x = g.frame(in: .named("gridH")).minX
                            Color.clear
                                .onAppear { scroll.x = max(0, -x) }
                                .onChange(of: x) { scroll.x = max(0, -x) }
                        })
                    }
                    .coordinateSpace(name: "gridH")
                    // 横に動く表の幅は「画面の幅 − 名前の列」に固定する（中身の幅に合わせて広がると、名前の列が画面の外に押し出される）
                    .frame(width: max(0, availableWidth - nameWidth))
                    .scrollDisabled(fitsWidth)
                    .onAppear { scrollToToday(proxy, days: days, today: today) }
                    .onChange(of: days) { scrollToToday(proxy, days: days, today: today) }
                }
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

    /// 行の中の横の位置 → 何日目か（合計の列や外は nil）
    private func day(atX x: CGFloat) -> DayKey? {
        guard x >= 0, cellWidth > 0 else { return nil }
        let i = Int(x / cellWidth)
        return days.indices.contains(i) ? days[i] : nil
    }

    /// マスを押したとき：まとめて選んでいれば選ぶ・外す、ふだんはそのマスを開く
    private func tapCell(_ m: StaffMember, _ d: DayKey) {
        guard !m.hasLeft(on: d) else { return }
        if selecting {
            togglePick(CellKey(staffID: m.id, day: d))
        } else {
            selected = Selection(member: m, day: d)
            DuoFocus.shared.look(staffID: m.id, day: d)
            onPickCell(m, d)
        }
    }

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
                .background(m.id == highlightStaffID ? Color.accentColor.opacity(0.14) : .clear)
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
            .overlay(alignment: .bottom) { RowLine() }
        case .hour(_, _, let h):
            let night = h <= 8
            HStack(spacing: 0) {
                Text(night ? "明" : "").appFont(.system(size: 9)).foregroundStyle(.secondary).frame(width: 26 * zoom)
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
            // 1行を1枚の絵として描く（部品を何千個も並べない。古い iPad でも月・週の切り替えを速くするため）
            HStack(spacing: 0) {
                MonthRowCanvas(name: m.name, cells: days.map { d in
                    let key = CellKey(staffID: m.id, day: d)
                    let r = table.get(m, d)
                    let away = r?.elsewhere == true ? book.store(r?.storeID) : nil
                    return MonthRowCanvas.Cell(day: d, left: m.hasLeft(on: d), resolved: r,
                                               block: book.block(r?.blockID, for: m),
                                               awayStore: away, awayLabel: away.map { book.shortName(of: $0) } ?? "",
                                               isToday: d == today, issues: issues[key] ?? [],
                                               requested: m.requestsOff(d), picked: picked.contains(key),
                                               hours: isWeek ? r?.netHours(book.breakRules) : nil)
                }, cellWidth: cellWidth, rowHeight: rowHeight, large: isWeek, compact: compact,
                   onActivate: { d in tapCell(m, d) })
                .overlay {
                    // まとめて選んでいるとき：押す・長押し（四角く選ぶ）を、押した位置で受ける
                    if selecting {
                        RowTouchCatcher(onTap: { x in if let d = day(atX: x) { tapCell(m, d) } },
                                        onLongPress: { x in
                                            if let d = day(atX: x) { pickRange(to: CellKey(staffID: m.id, day: d), shown: shown) }
                                        })
                    }
                }
                summaryCell(table.summary(m, days: days))
            }
            .overlay(alignment: .bottom) { RowLine() }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { v in
                if let d = day(atX: v.location.x) { tapCell(m, d) }
            }, including: selecting ? .subviews : .all)
        case .hourToggle(let dept, _):
            let plan = book.staffing
            if plan.hasPlan(for: dept.id) {
                // 必要人数を決めている部門は、閉じていても日ごとの不足が見える
                HStack(spacing: 0) {
                    // 日ごとの不足の札を1枚の絵として描く（押す操作は行に1つ。下の onTap）
                    ShortRowCanvas(departmentName: dept.name,
                                   cells: days.map { d in ShortRowCanvas.Cell(day: d, short: calc.gaps[dept.id]?[d]?.short ?? 0) },
                                   cellWidth: cellWidth, rowHeight: toggleHeight,
                                   onShort: { d in shortage = ShortageTarget(department: dept, day: d) })
                    Text("不足").appFont(.system(size: 9)).foregroundStyle(.secondary).frame(width: summaryWidth)
                }
                .background(Color(.systemBackground))
                .overlay(alignment: .bottom) { RowLine() }
                .contentShape(Rectangle())
                // 足りない日を押したら入れられる人を、それ以外は時間帯別を開く・閉じる
                .gesture(SpatialTapGesture().onEnded { v in
                    if let d = day(atX: v.location.x), (calc.gaps[dept.id]?[d]?.short ?? 0) > 0 {
                        shortage = ShortageTarget(department: dept, day: d)
                    } else {
                        toggleHourly(dept)
                    }
                })
            } else {
                Color(.systemBackground)
                    .frame(width: cellWidth * CGFloat(days.count) + summaryWidth)
                    .overlay(alignment: .bottom) { RowLine() }
                    .contentShape(Rectangle())
                    .onTapGesture { toggleHourly(dept) }
            }
        case .hour(let dept, _, let h):
            let night = h <= 8
            HStack(spacing: 0) {
                // 時間帯別の1行を1枚の絵として描く（開くと 24 時間 × 日数 × 部門のマスになるため）
                HourRowCanvas(hour: h, cells: days.map { d in
                    HourRowCanvas.Cell(day: d, count: calc.hourly.count(dept.id, on: d, hour: h),
                                       need: calc.needs[dept.id]?[d]?[h] ?? nil)
                }, cellWidth: cellWidth, rowHeight: hourHeight,
                   onShort: { d in shortage = ShortageTarget(department: dept, day: d) })
                Color.clear.frame(width: summaryWidth, height: hourHeight)
            }
            .background(night ? Color.blue.opacity(0.04) : Color(.secondarySystemBackground).opacity(0.3))
            // 足りない時間を押したら、その日に入れられる人を出す（押す操作は行に1つ）
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { v in
                guard let d = day(atX: v.location.x), let need = calc.needs[dept.id]?[d]?[h] ?? nil,
                      calc.hourly.count(dept.id, on: d, hour: h) < need else { return }
                shortage = ShortageTarget(department: dept, day: d)
            })
        }
    }

    private func scrollToToday(_ proxy: ScrollViewProxy, days: [DayKey], today: DayKey) {
        // 左には名前の列が重なるので、今日の数日前を左端に合わせる
        // 週は月曜から見せる（動かさない）。月は今日の数日前を左端に
        guard !isWeek else { return }
        // 選んでいる日があれば（Duo の見開き）その日を、なければ今日を見せる
        let focus = selectedDay.flatMap { days.contains($0) ? $0 : nil } ?? today
        let target = days.contains(focus) ? focus.adding(days: -(compact ? 2 : 3)) : nil
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
            Text("\(m.number)").appFont(.caption2).foregroundStyle(.secondary).monospacedDigit().frame(width: 22 * zoom)
            if !compact {
                InitialAvatar(name: m.name, colorIndex: book.departments.first { $0.id == m.departmentID }?.colorIndex ?? 8, size: 28 * zoom, photo: m.photo)
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
        .overlay(alignment: .bottom) { RowLine() }
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
        .overlay {
            if d == selectedDay {
                RoundedRectangle(cornerRadius: DS.chipRadius).strokeBorder(Color.accentColor, lineWidth: 2).padding(2)
            }
        }
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



/// 行の下の線。行は横並び（名前＋マス）の中にあるので、Divider だと縦の線になってしまう。高さを決めた横の線にする
private struct RowLine: View {
    var body: some View {
        Rectangle().fill(Color(.separator)).frame(height: 0.5).accessibilityHidden(true)
    }
}

/// 名前の列：表を横に動かした分だけ戻して、いつも左端に置く（この部品だけが横の位置を見るので、行の中身は作り直さない）
private struct PinnedColumn<Content: View>: View {
    let tracker: ScrollTracker
    @ViewBuilder let content: Content

    var body: some View {
        content.offset(x: tracker.x)
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
