import SwiftUI

// MARK: - 希望休を休ませたらどうなるか（案1：希望休の承認の見開き）

/// 承認待ちの申請を承認して、その日を休みにしたときの影響
struct LeaveImpact: Equatable {
    /// その日の今の予定（勤務・休み・空き。nil は空き）
    var current: ResolvedShift?
    /// その人の部門で、承認すると増える「足りない人×時間」（0 なら人数は変わらない）
    var addedShort: Int
    /// 承認したあと足りない時間帯（その人の部門）。足りなければ "13〜22時" のように
    var shortAfter: String?
    /// 承認する前から足りない時間帯（その人の部門）
    var shortBefore: String?
    /// 同じ日に休みを申請している・承認されているほかの人（名前と状態）
    var sameDay: [(name: String, status: LeaveRequest.Status)]
    /// 代わりに入れられる人（注意が出ない順・最大3人）
    var alternatives: [String]

    static func == (a: LeaveImpact, b: LeaveImpact) -> Bool {
        a.addedShort == b.addedShort && a.shortAfter == b.shortAfter && a.shortBefore == b.shortBefore
            && a.sameDay.map(\.name) == b.sameDay.map(\.name) && a.alternatives == b.alternatives
    }

    /// その人がその日に休んだことにして、部門の人数を比べる
    static func of(_ member: StaffMember, on day: DayKey, in book: ShiftBook, offBlockID: String? = nil) -> LeaveImpact {
        let current = Schedule.resolve(member, on: day, in: book)
        var trial = book
        if current.map({ !$0.isOff }) ?? false {
            trial.cells[CellKey(staffID: member.id, day: day)] = CellEntry(inTime: "", outTime: "", blockID: offBlockID ?? "off1",
                                                                          isOff: true, storeID: book.scopeStoreID)
        }
        if let i = trial.staff.firstIndex(where: { $0.id == member.id }), !trial.staff[i].offRequests.contains(day.description) {
            trial.staff[i].offRequests.append(day.description)
        }
        let before = ShortageFinder.items(book, days: [day]).first { $0.department.id == member.departmentID }
        let after = ShortageFinder.items(trial, days: [day]).first { $0.department.id == member.departmentID }
        let others = book.staff.filter { $0.id != member.id && !$0.hasLeft(on: day) }.compactMap { m -> (String, LeaveRequest.Status)? in
            if let r = m.leaveRequests.first(where: { $0.day == day.description && $0.status != .rejected }) { return (m.name, r.status) }
            if m.offRequests.contains(day.description) { return (m.name, .approved) }
            return nil
        }
        let alternatives = (after == nil ? [] : ShortageFinder.candidates(trial, department: member.departmentID, on: day, includeOthers: false))
            .filter { $0.member.id != member.id && $0.issues.isEmpty }
            .prefix(3).map(\.member.name)
        return LeaveImpact(current: current, addedShort: (after?.short ?? 0) - (before?.short ?? 0),
                           shortAfter: after?.hoursLabel, shortBefore: before?.hoursLabel,
                           sameDay: others.map { (name: $0.0, status: $0.1) }, alternatives: Array(alternatives))
    }
}

// MARK: - 希望休の承認の見開き

/// 開いた Duo の希望休：左のページに承認待ちの申請、右のページにその日に休ませたらどうなるか。見てから1回で決める
struct LeaveSpread: View {
    @Environment(\.duo) private var duo
    @Environment(\.shiftStore) private var store
    @AppStorage("requestAlsoOff") private var alsoOff = true
    @State private var selected: String?
    @State private var reply: LeaveReply?
    @State private var error: String?

    var body: some View {
        let rows = Self.pending(in: store.book)
        let row = rows.first { $0.id == selected }
        GeometryReader { geo in
            let rightWidth = duo.rightPageWidth(in: geo.frame(in: .global))
            HStack(spacing: 0) {
                requestList(rows)
                    .frame(width: max(0, geo.size.width - rightWidth))
                Group {
                    if let row { impactPage(row) } else {
                        ContentUnavailableView(rows.isEmpty ? "承認待ちの申請はありません" : "左で申請を選んでください",
                                               systemImage: rows.isEmpty ? "checkmark.circle" : "hand.point.left")
                    }
                }
                .frame(width: rightWidth)
                .overlay(alignment: .leading) { Rectangle().fill(Color(.separator)).frame(width: 0.5) }
            }
        }
        .navigationTitle("希望休の承認")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { pick(rows) }
        .onChange(of: rows.map(\.id)) { pick(rows) }
        .shiftSheet(item: $reply) { LeaveReplySheet(reply: $0) }
        .errorAlert($error)
    }

    /// 承認待ち（日付の早い順）
    static func pending(in book: ShiftBook) -> [LeaveRequestRow] {
        let members = book.staffByDepartment(visibleIn: MonthKey.current).flatMap(\.members)
        var seen = Set<String>()
        return members.filter { seen.insert($0.id).inserted }
            .flatMap { m in m.leaveRequests.filter { $0.status == .pending }.map { LeaveRequestRow(member: m, request: $0) } }
            .sorted { ($0.request.day, $0.member.name) < ($1.request.day, $1.member.name) }
    }

    /// 選んでいる申請が無くなったら、閉じた画面で見ていた申請 → いちばん上 の順に選ぶ
    private func pick(_ rows: [LeaveRequestRow]) {
        guard !rows.contains(where: { $0.id == selected }) else { return }
        let focused = DuoFocus.shared.requestID
        selected = (rows.first { $0.id == focused } ?? rows.first)?.id
    }

    private func requestList(_ rows: [LeaveRequestRow]) -> some View {
        List {
            Section {
                ForEach(rows) { r in
                    Button { selected = r.id } label: { requestRow(r) }
                        .buttonStyle(.plain)
                        .listRowBackground(r.id == selected ? Color.accentColor.opacity(0.14) : Color(.systemBackground))
                }
            } header: {
                Text("承認待ちの申請（\(rows.count)件）")
            }
        }
        .listStyle(.plain)
        .overlay { if rows.isEmpty { ContentUnavailableView("承認待ちの申請はありません", systemImage: "checkmark.circle") } }
    }

    private func requestRow(_ r: LeaveRequestRow) -> some View {
        let color = store.book.departments.first { $0.id == r.member.departmentID }?.colorIndex ?? 8
        return HStack(spacing: 10) {
            InitialAvatar(name: r.member.name, colorIndex: color, size: 32, photo: r.member.photo)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(r.member.name).appFont(.body.weight(.semibold)).lineLimit(1)
                    Text(r.day.map { HomeView.dayLabel($0) } ?? r.request.day).appFont(.subheadline).monospacedDigit()
                }
                if !r.request.note.isEmpty {
                    Text(r.request.note).appFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Text(r.request.receivedAt, style: .relative).appFont(.caption2).foregroundStyle(.secondary)
                .padding(.trailing, 8)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func impactPage(_ r: LeaveRequestRow) -> some View {
        if let day = r.day {
            let impact = LeaveImpact.of(r.member, on: day, in: store.book, offBlockID: offBlockID())
            VStack(spacing: 0) {
                HStack {
                    Text("\(HomeView.dayLabel(day))に\(r.member.name)さんが休むと")
                        .appFont(.headline).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.bar)
                .overlay(alignment: .bottom) { Divider() }
                List {
                    Section("その日の予定") {
                        Label(currentText(impact.current, member: r.member), systemImage: "calendar")
                    }
                    Section("人数") {
                        if impact.addedShort > 0 {
                            Label("\(impact.shortAfter ?? "") が \(impact.addedShort)人時間 足りなくなります",
                                  systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(StaffingStyle.short)
                        } else if let before = impact.shortBefore {
                            Label("人数は変わりません（もとから \(before) が足りません）", systemImage: "minus.circle")
                        } else if store.book.staffing.isEmpty {
                            Label("必要な人数が決まっていないので、足りるかは分かりません", systemImage: "questionmark.circle")
                                .foregroundStyle(.secondary)
                        } else {
                            Label("休んでも必要な人数はそろいます", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(StaffingStyle.ok)
                        }
                    }
                    if !impact.sameDay.isEmpty {
                        Section("同じ日に休む人") {
                            ForEach(impact.sameDay, id: \.name) { p in
                                HStack {
                                    Text(p.name)
                                    Spacer()
                                    Text(p.status == .approved ? "希望休" : "承認待ち").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if impact.addedShort > 0 {
                        Section("代わりに入れられる人") {
                            Text(impact.alternatives.isEmpty ? "注意（連勤・間隔など）が出ずに入れられる人はいません"
                                                             : impact.alternatives.joined(separator: "・"))
                                .foregroundStyle(impact.alternatives.isEmpty ? .secondary : .primary)
                        }
                    }
                    if !r.request.note.isEmpty {
                        Section("届いた文章") { Text(r.request.note).appFont(.subheadline) }
                    }
                }
                buttons(r, day: day, short: impact.addedShort > 0)
            }
        }
    }

    private func buttons(_ r: LeaveRequestRow, day: DayKey, short: Bool) -> some View {
        HStack(spacing: 8) {
            Button(role: .destructive) { decide(r, .rejected) } label: { Text("却下") }
                .buttonStyle(.bordered).tint(.red)
            Spacer(minLength: 0)
            if short {
                Button { decide(r, .approved, findCover: day) } label: { Text("承認して代わりを探す") }
                    .buttonStyle(.bordered)
            }
            Button { decide(r, .approved) } label: { Text("承認") }
                .buttonStyle(.borderedProminent).tint(.green)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func currentText(_ r: ResolvedShift?, member: StaffMember) -> String {
        guard let r else { return "勤務は入っていません" }
        if r.isOff { return "もう休みになっています（\(store.book.block(r.blockID, for: member)?.label ?? "休み")）" }
        let label = store.book.block(r.blockID, for: member)?.label
        return "\(label.map { $0 + " " } ?? "")\(r.inTime)〜\(r.outTime) の勤務 → 承認すると休みになります"
    }

    /// 承認・却下（一覧の画面と同じ決め方）。代わりを探すときは、シフト表の見開きの「人が足りない」でその日を開く
    private func decide(_ r: LeaveRequestRow, _ status: LeaveRequest.Status, findCover: DayKey? = nil) {
        do {
            try store.decideLeaveRequests([r.id], as: status, for: r.member.id, offBlockID: offBlockID())
            if let findCover {
                SpreadBoard.openFill(on: findCover)
                return
            }
            let groups = LeaveRequestInbox.replyGroups([r.id], staff: store.book.staff)
            if !groups.isEmpty {
                reply = LeaveReply(recipients: groups.map { LeaveReply.Recipient(member: $0.member, decided: $0.decided) })
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// 「シフトも休みにする」なら、休みの種類（一覧の画面と同じ選び方）
    private func offBlockID() -> String? {
        guard alsoOff else { return nil }
        let offs = store.book.templates.filter(\.isOff)
        return offs.first { $0.id == "off1" }?.id ?? offs.first?.id
    }
}

// MARK: - 読むだけの小さな表（案2：前回の公開と比べる・案4：2つを左右に並べる）

/// 名前 × 日付の読むだけの表。マスの文字は公開の記録と同じ書き方（「早番 9:00〜18:00」「公休」）を短くして出す
struct MiniGrid: View {
    let members: [StaffMember]
    let days: [DayKey]
    /// "スタッフID|yyyy-MM-dd" → 表示
    let labels: [String: String]
    /// 枠を付けるマス（変わったところ）
    var changed: Set<String> = []
    /// 名前に印を付ける人（掛け持ちで両方に出てくる人など）
    var marked: Set<String> = []
    /// 最初に見せる日
    var focusDay: DayKey?

    private let nameWidth: CGFloat = 64
    private let cellWidth: CGFloat = 44
    private let rowHeight: CGFloat = 36
    private let headerHeight: CGFloat = 32

    var body: some View {
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    Color.clear.frame(width: nameWidth, height: headerHeight)
                    ForEach(members) { m in
                        HStack(spacing: 2) {
                            Text(m.name).appFont(.caption.weight(.bold)).lineLimit(1).minimumScaleFactor(0.6)
                            if marked.contains(m.id) {
                                Image(systemName: "arrow.left.arrow.right").appFont(.caption2).foregroundStyle(Color.accentColor)
                                    .accessibilityLabel("掛け持ち")
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, 8)
                        .frame(width: nameWidth, height: rowHeight)
                        .overlay(alignment: .bottom) { Divider() }
                    }
                }
                .overlay(alignment: .trailing) { Rectangle().fill(Color(.separator)).frame(width: 0.5) }
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 0) {
                                ForEach(days, id: \.self) { d in dayHeader(d).id(d) }
                            }
                            ForEach(members) { m in
                                HStack(spacing: 0) {
                                    ForEach(days, id: \.self) { d in cell(m, d) }
                                }
                            }
                        }
                    }
                    .onAppear { if let focusDay { proxy.scrollTo(focusDay, anchor: .leading) } }
                    .onChange(of: focusDay) { if let focusDay { proxy.scrollTo(focusDay, anchor: .leading) } }
                }
            }
        }
    }

    private func dayHeader(_ d: DayKey) -> some View {
        let color: Color = (d.weekday == 0 || JapaneseHolidays.name(d) != nil) ? .red : d.weekday == 6 ? .blue : .primary
        return VStack(spacing: 0) {
            Text("\(d.day)").appFont(.caption.weight(.bold)).monospacedDigit()
            Text(["日", "月", "火", "水", "木", "金", "土"][d.weekday]).appFont(.caption2)
        }
        .foregroundStyle(color)
        .frame(width: cellWidth, height: headerHeight)
        .background(.bar)
    }

    private func cell(_ m: StaffMember, _ d: DayKey) -> some View {
        let key = CellKey(staffID: m.id, day: d).description
        let text = Self.short(labels[key] ?? "")
        let isChanged = changed.contains(key)
        return Text(text)
            .appFont(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6)
            .foregroundStyle(text.contains("休") ? Color.red : Color.primary)
            .frame(width: cellWidth - 4, height: rowHeight - 8)
            .background(isChanged ? Color.accentColor.opacity(0.14) : Color.clear,
                        in: RoundedRectangle(cornerRadius: DS.chipRadius))
            .overlay {
                if isChanged { RoundedRectangle(cornerRadius: DS.chipRadius).strokeBorder(Color.accentColor, lineWidth: 1.5) }
            }
            .frame(width: cellWidth, height: rowHeight)
            .overlay(alignment: .bottom) { Divider() }
            .accessibilityLabel("\(m.name) \(d.month)/\(d.day) \(labels[key] ?? "なし")\(isChanged ? "（変更）" : "")")
    }

    /// 「早番 9:00〜18:00」→「早番」、「9:00〜18:00」→「9:00〜」、「公休」→「公休」
    static func short(_ label: String) -> String {
        if let sp = label.firstIndex(of: " ") { return String(label[..<sp]) }
        if let tilde = label.firstIndex(of: "〜") { return String(label[..<tilde]) + "〜" }
        return label
    }

    /// その表に出す人（同じ人は1回だけ）
    static func members(_ book: ShiftBook, month: MonthKey) -> [StaffMember] {
        var seen = Set<String>()
        return book.staffByDepartment(visibleIn: month).flatMap(\.members).filter { seen.insert($0.id).inserted }
    }
}

// MARK: - 前回の公開と比べる（案2）

/// 見開きの左右：前回公開した表と、今の表。変わったマスに枠
struct CompareSpread: View {
    let month: MonthKey
    let rightWidth: CGFloat
    let totalWidth: CGFloat

    @Environment(\.shiftStore) private var store

    var body: some View {
        let book = store.book
        let old = book.published.first { $0.month == PublishedMonth.key(month, in: book) }
        let now = PublishedMonth.snapshot(of: book, month: month)
        let diff = PublishDiff.changes(book, month: month)?.changes ?? []
        let changed = Set(diff.map { CellKey(staffID: $0.staffID, day: $0.day).description })
        let members = MiniGrid.members(book, month: month)
        let first = diff.first?.day
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                pageHeader(old.map { "前回の公開（\($0.date.formatted(.dateTime.month().day()))）" } ?? "前回の公開", trailing: nil)
                if let old {
                    MiniGrid(members: members, days: month.days, labels: old.entries, changed: changed, focusDay: first)
                } else {
                    ContentUnavailableView("\(month.month)月はまだ公開していません", systemImage: "paperplane",
                                           description: Text("印刷・出力から公開すると、そのときの表と今の表を見比べられます。"))
                }
            }
            .frame(width: max(0, totalWidth - rightWidth))
            VStack(spacing: 0) {
                pageHeader("今の表", trailing: old == nil ? nil : (diff.isEmpty ? "変更なし" : "変更 \(diff.count)か所"))
                MiniGrid(members: members, days: month.days, labels: now.entries, changed: changed, focusDay: first)
                    .frame(maxHeight: .infinity)
                if !diff.isEmpty {
                    changeList(diff)
                }
            }
            .frame(width: rightWidth)
            .overlay(alignment: .leading) { Rectangle().fill(Color(.separator)).frame(width: 0.5) }
        }
    }

    private func pageHeader(_ title: String, trailing: String?) -> some View {
        HStack {
            Text(title).appFont(.subheadline.weight(.bold)).lineLimit(1)
            Spacer(minLength: 0)
            if let trailing { Text(trailing).appFont(.subheadline.weight(.bold)).foregroundStyle(Color.accentColor) }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    /// 変わったところを文章で（公開のときに送る文章と同じ書き方）
    private func changeList(_ diff: [PublishChange]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(diff.prefix(30).enumerated()), id: \.offset) { _, c in
                    Text("\(c.staffName) \(c.day.month)/\(c.day.day)：\(c.before.isEmpty ? "なし" : c.before) → \(c.after.isEmpty ? "なし" : c.after)")
                        .appFont(.caption).monospacedDigit()
                }
                if diff.count > 30 { Text("ほか\(diff.count - 30)か所").appFont(.caption).foregroundStyle(.secondary) }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 84)
        .background(Color(.secondarySystemBackground))
    }
}

// MARK: - 人件費を見ながら組む（案3）

/// 見開きの右のページ：今月の人件費と予算。勤務を変えるたびに、増えた・減った金額を出す
struct CostPanel: View {
    let month: MonthKey

    @Environment(\.shiftStore) private var store
    @State private var lastTotal: Int?
    @State private var delta: Int?
    @State private var deltaTitle: String?

    var body: some View {
        let lock = LaborCostLock.shared
        if !lock.canView {
            LaborCostLockedView()
        } else {
            let book = store.book
            let total = Payroll.total(month: month, in: book)
            let previous = Payroll.total(month: month.adding(months: -1), in: book)
            let budget = LaborBudget.value(store: book.scopeStoreID, month: month, rules: book.pay)
            let usage = budget.flatMap { LaborBudget.usage(total, budget: $0) }
            List {
                Section("\(month.month)月の人件費（見込み）") {
                    Text("\(total.formatted())円").appFont(.number).monospacedDigit()
                    if let budget, let usage {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: min(usage, 100), total: 100)
                                .tint(usage > 100 ? .red : usage > 90 ? .orange : .green)
                            Text("予算 \(budget.formatted())円の \(Int(usage.rounded()))%"
                                 + (total > budget ? "（\((total - budget).formatted())円 超え）" : "（残り \((budget - total).formatted())円）"))
                                .appFont(.caption).foregroundStyle(usage > 100 ? .red : .secondary).monospacedDigit()
                        }
                    } else {
                        Text("予算は決まっていません（集計 → 人件費 で決められます）").appFont(.caption).foregroundStyle(.secondary)
                    }
                    Text("先月 \(previous.formatted())円").appFont(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                if let delta, delta != 0 {
                    Section("いま変えたこと") {
                        HStack {
                            Text(deltaTitle ?? "変更").appFont(.subheadline).lineLimit(2)
                            Spacer(minLength: 8)
                            Text("\(delta > 0 ? "+" : "−")\(abs(delta).formatted())円")
                                .appFont(.headline).monospacedDigit()
                                .foregroundStyle(delta > 0 ? Color.orange : Color.green)
                        }
                    }
                }
            }
            .onAppear { lastTotal = total }
            // 勤務を変えるたびに、増えた・減った金額を出す
            .onChange(of: total) { old, new in
                delta = new - old
                deltaTitle = store.lastChange?.title
                lastTotal = new
            }
        }
    }
}

// MARK: - 2つを左右に並べる（案4）

/// 見開きの右のページ：来月、またはほかの店舗の同じ月を、読むだけの表で並べる。両方に出てくる人（掛け持ち）に印
struct PairPage: View {
    let month: MonthKey
    /// "next"（来月）または店舗の ID
    @AppStorage("duoPairTarget") private var target = "next"
    @Environment(\.shiftStore) private var store

    var body: some View {
        let book = store.book
        let others = book.allStores.filter { $0.id != store.currentStoreID }
        let isNext = target == "next" || !others.contains { $0.id == target }
        let shown: ShiftBook = {
            guard !isNext else { return book }
            var b = book
            b.scopeStoreID = target
            return b
        }()
        let shownMonth = isNext ? month.adding(months: 1) : month
        let members = MiniGrid.members(shown, month: shownMonth)
        let here = Set(MiniGrid.members(book, month: month).map(\.id))
        let marked = isNext ? [] : Set(members.map(\.id)).intersection(here)
        VStack(spacing: 0) {
            HStack {
                Menu {
                    Button { target = "next" } label: { Label("来月（\(month.adding(months: 1).month)月）", systemImage: isNext ? "checkmark" : "") }
                    ForEach(others) { st in
                        Button { target = st.id } label: { Label("\(st.name)の\(month.month)月", systemImage: target == st.id ? "checkmark" : "") }
                    }
                } label: {
                    Label(isNext ? "来月（\(shownMonth.month)月）" : "\(book.store(target)?.name ?? "")の\(month.month)月",
                          systemImage: "chevron.down")
                        .appFont(.subheadline.weight(.bold))
                }
                Spacer(minLength: 0)
                Text("読むだけ").appFont(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
            MiniGrid(members: members, days: shownMonth.days,
                     labels: PublishedMonth.snapshot(of: shown, month: shownMonth).entries,
                     marked: marked, focusDay: isNext ? nil : store.today)
            if !marked.isEmpty {
                Label("両方の店舗に入る人（掛け持ち）に印を付けています", systemImage: "arrow.left.arrow.right")
                    .appFont(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
            }
        }
    }
}
