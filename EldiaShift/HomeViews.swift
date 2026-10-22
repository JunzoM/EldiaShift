import SwiftUI

// MARK: - サイドバー（iPad）・タブ（iPhone）

enum AppTab: String, Hashable, Identifiable {
    var id: String { rawValue }
    case home, schedule, staff, summary, settings
}

extension AppTab {
    var title: String {
        switch self {
        case .home: "ホーム"
        case .schedule: "シフト表"
        case .staff: "スタッフ"
        case .summary: "集計"
        case .settings: "設定"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .schedule: "calendar"
        case .staff: "person.2"
        case .summary: "chart.bar.doc.horizontal"
        case .settings: "gearshape"
        }
    }
}

/// iPad（横幅が広いとき）は左にサイドバー、iPhone は下にタブ。
/// iPad で上部のタブバーにすると、シフト表の月の移動ボタンがツールバーからあふれて「…」に隠れるため、サイドバーにする
@available(iOS 18.0, *)
struct MainTabsView: View {
    @Binding var anchor: DayKey

    @Environment(ShiftStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("appTab") private var savedTab: AppTab = .home
    @State private var tab: AppTab = .home
    @AppStorage("viewMode") private var mode: GridMode = .month
    /// iPad を縦にしてもサイドバー（ホームなどの切替）を隠さない
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        Group {
            if sizeClass == .regular { split } else { tabs }
        }
        .onAppear {
            if DemoMode.enabled {
                tab = DemoMode.flag("-demoHome") ? .home : .schedule
            } else {
                tab = savedTab
            }
        }
        .onChange(of: tab) { if !DemoMode.enabled { savedTab = tab } }
    }

    // MARK: iPad：サイドバー

    private var split: some View {
        NavigationSplitView(columnVisibility: $columns) {
            List(selection: Binding<AppTab?>(get: { tab }, set: { if let t = $0 { tab = t } })) {
                Section {
                    StoreSwitcher()
                }
                Section {
                    ForEach([AppTab.home, .schedule, .staff, .summary]) { t in
                        Label(t.title, systemImage: t.systemImage).tag(t)
                    }
                }
                Section {
                    Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage).tag(AppTab.settings)
                }
            }
            .navigationTitle("シフト表")
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
        } detail: {
            content(tab, storeInToolbar: false)
                .id(tab)
        }
        // 縦向きでもサイドバーを重ねずに横に並べる（隠れるとホームへ戻れない）
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: iPhone：タブ

    private var tabs: some View {
        TabView(selection: $tab) {
            ForEach([AppTab.home, .schedule, .staff, .summary, .settings]) { t in
                Tab(t.title, systemImage: t.systemImage, value: t) { content(t, storeInToolbar: true) }
            }
        }
    }

    @ViewBuilder
    private func content(_ t: AppTab, storeInToolbar: Bool) -> some View {
        switch t {
        case .home:
            NavigationStack {
                HomeView(openDay: openDay, openTab: { tab = $0 }, storeInToolbar: storeInToolbar)
            }
        case .schedule:
            ShiftBoardView(anchor: $anchor, inTabs: true, storeInToolbar: storeInToolbar)
        case .staff:
            NavigationStack {
                StaffListView()
                    .toolbar { if storeInToolbar { ToolbarItem(placement: .topBarLeading) { StoreSwitcher() } } }
            }
        case .summary:
            NavigationStack {
                SummaryView(month: MonthKey(anchor))
                    .toolbar { if storeInToolbar { ToolbarItem(placement: .topBarLeading) { StoreSwitcher() } } }
            }
        case .settings:
            SettingsView(inTab: true)
        }
    }

    /// ホームから：その日のタイムラインを開く
    private func openDay(_ d: DayKey) {
        anchor = d
        mode = .day
        tab = .schedule
    }
}

// MARK: - ホーム

struct HomeView: View {
    var openDay: (DayKey) -> Void
    var openTab: (AppTab) -> Void
    /// 店舗の切替をツールバーに出す（iPad はサイドバーにあるので出さない）
    var storeInToolbar = true

    @Environment(ShiftStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showPrint = false
    @State private var showStores = false
    @State private var adding: StaffMember?
    @AppStorage("summaryTab") private var summaryTab = 0

    var body: some View {
        let today = store.today
        let info = HomeInfo(book: store.book, today: today)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(today)
                cards(info)
                if sizeClass == .compact {
                    todayList(info)
                    shortList(info)
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        todayList(info).frame(maxWidth: .infinity)
                        VStack(spacing: 16) {
                            shortList(info)
                            quickMenu
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                if sizeClass == .compact { quickMenu }
            }
            .padding(16)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("ホーム")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if storeInToolbar { ToolbarItem(placement: .topBarLeading) { StoreSwitcher() } } }
        .sheet(isPresented: $showPrint) { PrintSheet(anchor: today) }
        .sheet(isPresented: $showStores) { NavigationStack { StoreListView(inSheet: true) } }
        .sheet(item: $adding) { s in StaffEditView(member: s, isNew: true) }
    }

    // MARK: 見出し

    private func header(_ today: DayKey) -> some View {
        let wd = ["日", "月", "火", "水", "木", "金", "土"][today.weekday]
        return VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "\(today.year)年\(today.month)月\(today.day)日（\(wd)）\(JapaneseHolidays.name(today).map { " \($0)" } ?? "")")
                .font(.subheadline).foregroundStyle(.secondary)
            Text(store.currentStore.name).font(.title.weight(.bold))
        }
    }

    // MARK: 数字のカード

    private func cards(_ info: HomeInfo) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: sizeClass == .compact ? 150 : 200), spacing: 12)], spacing: 12) {
            HomeCard(title: "今日の出勤", systemImage: "person.2.fill", tint: .accentColor,
                     value: "\(info.working.count)", unit: "人",
                     note: info.helpers > 0 ? "うち掛け持ち \(info.helpers)人・休み \(info.off)人" : "休み \(info.off)人") {
                openDay(store.today)
            }
            if store.book.staffing.isEmpty {
                HomeCard(title: "人手不足の日", systemImage: "exclamationmark.triangle", tint: .secondary,
                         value: "—", unit: "", note: "適正人員が未設定です") {
                    summaryTab = 1
                    openTab(.summary)
                }
            } else {
                HomeCard(title: "人手不足の日", systemImage: "exclamationmark.triangle.fill",
                         tint: info.shortDays.isEmpty ? StaffingStyle.ok : StaffingStyle.short,
                         value: "\(info.shortDays.count)", unit: "日",
                         note: info.shortDays.first.map { "次は \($0.day.month)/\($0.day.day)・2週間以内" } ?? "2週間以内はそろっています") {
                    if let d = info.shortDays.first?.day { openDay(d) } else { openTab(.schedule) }
                }
            }
            HomeCard(title: "未公開の変更", systemImage: "paperplane.fill",
                     tint: (info.unpublished ?? 1) > 0 ? .orange : StaffingStyle.ok,
                     value: info.unpublished.map { "\($0)" } ?? "—", unit: info.unpublished == nil ? "" : "件",
                     note: info.unpublished == nil ? "\(store.today.month)月分はまだ公開していません" : "\(store.today.month)月分・前回の公開から") {
                showPrint = true
            }
            HomeCard(title: "労務の注意", systemImage: "hand.raised.fill",
                     tint: info.laborIssues > 0 ? .orange : StaffingStyle.ok,
                     value: "\(info.laborIssues)", unit: "件", note: "\(store.today.month)月の連勤・間隔・希望休など") {
                summaryTab = 2
                openTab(.summary)
            }
        }
    }

    // MARK: 今日の出勤

    private func todayList(_ info: HomeInfo) -> some View {
        HomeSection(title: "今日の出勤", trailing: "タイムライン") {
            openDay(store.today)
        } content: {
            if info.working.isEmpty {
                Text("今日の出勤はありません").foregroundStyle(.secondary).padding(.vertical, 8)
            }
            ForEach(info.working) { w in
                HStack(spacing: 10) {
                    Circle().fill(PaletteColor.fg(w.department?.colorIndex ?? 8)).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(w.member.name).font(.body.weight(.semibold))
                        Text(w.department?.name ?? "").font(.caption).foregroundStyle(.secondary)
                    }
                    if w.helper { Text("掛け持ち").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(.tertiarySystemFill), in: Capsule()) }
                    Spacer()
                    if let b = w.block {
                        Text(b.label).font(.caption.weight(.bold))
                            .foregroundStyle(PaletteColor.fg(b.colorIndex))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(PaletteColor.bg(b.colorIndex), in: Capsule())
                    }
                    Text("\(w.shift.inTime)〜\(w.shift.outTime)").font(.subheadline).monospacedDigit()
                }
                .padding(.vertical, 6)
                if w.id != info.working.last?.id { Divider() }
            }
        }
    }

    // MARK: 人手が足りない日

    private func shortList(_ info: HomeInfo) -> some View {
        HomeSection(title: "人手が足りない日（2週間）", trailing: nil, action: nil) {
            if store.book.staffing.isEmpty {
                Text("適正人員を決めると、足りない日がここに出ます。").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 8)
            } else if info.shortDays.isEmpty {
                Label("すべての日でそろっています", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(StaffingStyle.ok).padding(.vertical, 8)
            }
            ForEach(info.shortDays.prefix(6)) { s in
                Button { openDay(s.day) } label: {
                    HStack {
                        Text(Self.dayLabel(s.day)).font(.subheadline.weight(.semibold)).monospacedDigit()
                        Text(s.departments.joined(separator: "・")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Text("−\(s.short)人時").font(.subheadline.weight(.heavy)).monospacedDigit().foregroundStyle(StaffingStyle.short)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if s.id != info.shortDays.prefix(6).last?.id { Divider() }
            }
        }
    }

    // MARK: クイックメニュー

    private var quickMenu: some View {
        HomeSection(title: "クイックメニュー", trailing: nil, action: nil) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                QuickButton(title: "シフト表", systemImage: "calendar") { openTab(.schedule) }
                QuickButton(title: "印刷・共有", systemImage: "printer") { showPrint = true }
                QuickButton(title: "スタッフを追加", systemImage: "person.badge.plus") {
                    adding = store.newStaff(in: store.book.scopedDepartments.first?.id ?? store.book.departments.first?.id ?? "")
                }
                QuickButton(title: "店舗", systemImage: "building.2") { showStores = true }
            }
            .padding(.vertical, 4)
        }
    }

    static func dayLabel(_ d: DayKey) -> String {
        "\(d.month)/\(d.day)（\(["日", "月", "火", "水", "木", "金", "土"][d.weekday])）"
    }
}

// MARK: - ホームに出す数字（画面と切り離して計算する）

struct HomeInfo {
    struct Working: Identifiable {
        var member: StaffMember
        var department: Department?
        var shift: ResolvedShift
        var block: TimeBlock?
        /// 掛け持ちでほかの店舗から来ている
        var helper: Bool
        var id: String { member.id }
    }

    struct ShortDay: Identifiable {
        var day: DayKey
        /// 足りない人×時間（部門の合計）
        var short: Int
        var departments: [String]
        var id: DayKey { day }
    }

    var working: [Working] = []
    var helpers = 0
    var off = 0
    var shortDays: [ShortDay] = []
    /// 前回の公開からの変更（まだ公開していなければ nil）
    var unpublished: Int?
    var laborIssues = 0

    init(book: ShiftBook, today: DayKey) {
        let month = MonthKey(today)
        let groups = book.staffByDepartment(visibleIn: month)
        let members = groups.flatMap(\.members)
        let deptOf = Dictionary(book.departments.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let scope = book.scopeStoreID

        // 今日の出勤（出勤の早い順）
        for m in members where !m.hasLeft(on: today) {
            guard let r = Schedule.resolve(m, on: today, in: book) else { continue }
            if r.isOff { off += 1; continue }
            guard !r.elsewhere, ClockTime.parse(r.inTime) != nil else { continue }
            let helper = scope != nil && book.homeStoreID(of: m) != scope
            if helper { helpers += 1 }
            working.append(Working(member: m, department: deptOf[m.departmentID], shift: r,
                                   block: book.block(r.blockID, for: m), helper: helper))
        }
        working.sort { (ClockTime.parse($0.shift.inTime) ?? 0, $0.member.name) < (ClockTime.parse($1.shift.inTime) ?? 0, $1.member.name) }

        // 2週間以内の人手不足
        if !book.staffing.isEmpty {
            let days = (0..<14).map { today.adding(days: $0) }
            let table = ScheduleTable(book: book, members: members, days: days)
            for d in days {
                var total = 0
                var names: [String] = []
                for g in groups where book.staffing.hasPlan(for: g.department.id) {
                    let gap = StaffingCheck.gap(book.staffing, department: g.department.id, members: g.members, on: d) {
                        table.working($0, on: $1, hour: $2)
                    }
                    if gap.short > 0 { total += gap.short; names.append(g.department.name) }
                }
                if total > 0 { shortDays.append(ShortDay(day: d, short: total, departments: names)) }
            }
        }

        unpublished = PublishDiff.changes(book, month: month)?.changes.count
        laborIssues = LaborCheck.issues(book, members: members, days: month.days).count
    }
}

// MARK: - 部品

/// 数字のカード（中身なのでガラスは使わず、角丸の面で見せる）
struct HomeCard: View {
    let title: String
    let systemImage: String
    let tint: Color
    let value: String
    let unit: String
    let note: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Spacer()
                    Image(systemName: systemImage)
                        .font(.subheadline)
                        .foregroundStyle(tint)
                        .frame(width: 32, height: 32)
                        .background(tint.opacity(0.14), in: Circle())
                }
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(.system(size: 32, weight: .bold, design: .rounded)).monospacedDigit()
                    Text(unit).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)\(unit)。\(note)")
    }
}

struct HomeSection<Content: View>: View {
    let title: String
    let trailing: String?
    let action: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if let trailing, let action {
                    Button(trailing, action: action).font(.subheadline)
                }
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, 14).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

struct QuickButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage).font(.title3).foregroundStyle(Color.accentColor)
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
