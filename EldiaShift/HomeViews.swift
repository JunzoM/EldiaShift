import SwiftUI
import UIKit

// MARK: - サイドバー（iPad）・タブ（iPhone）

enum AppTab: String, Hashable, Identifiable {
    var id: String { rawValue }
    case home, schedule, requests, staff, summary, print, stores, settings
}

extension AppTab {
    /// メニュー（Mac）などから画面を開く。MainTabsView が受け取る
    static let openNotification = Notification.Name("EldiaShift.openTab")
    static func open(_ tab: AppTab) { NotificationCenter.default.post(name: openNotification, object: tab.rawValue) }

    var title: String {
        switch self {
        case .home: "ホーム"
        case .schedule: "シフト表"
        case .requests: "希望休"
        case .staff: "スタッフ"
        case .summary: "集計"
        case .print: "印刷・出力"
        case .stores: "店舗"
        case .settings: "設定"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .schedule: "calendar"
        case .requests: "calendar.badge.minus"
        case .staff: "person.2"
        case .summary: "chart.bar.doc.horizontal"
        case .print: "printer"
        case .stores: "building.2"
        case .settings: "gearshape"
        }
    }
}

/// iPad（横幅が広いとき）は左にサイドバー、iPhone は下にタブ。
/// iPad で上部のタブバーにすると、シフト表の月の移動ボタンがツールバーからあふれて「…」に隠れるため、サイドバーにする
/// iOS 17 でも使える（サイドバーは iOS 16 から、下のタブは iOS 17 では従来の書き方）
struct MainTabsView: View {
    @Binding var anchor: DayKey

    @Environment(\.shiftStore) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("appTab") private var savedTab: AppTab = .home
    @State private var tab: AppTab = .home
    @AppStorage("viewMode") private var mode: GridMode = .month
    /// サイドバーをアイコンだけにする（AppSidebar と同じ設定）。iPad は向きで自動で切り替える
    @AppStorage("sidebarCompact") private var sidebarCompact = false

    var body: some View {
        Group {
            if sizeClass == .regular { split } else { tabs }
        }
        .onAppear {
            if DemoMode.enabled {
                tab = DemoMode.flag("-demoHome") ? .home
                    : DemoMode.flag("-demoTabRequests") ? .requests
                    : DemoMode.flag("-demoTabStaff") ? .staff
                    : DemoMode.flag("-demoTabPrint") ? .print
                    : DemoMode.flag("-demoTabStores") ? .stores
                    : DemoMode.flag("-demoTabBackup") ? .settings : .schedule
            } else {
                tab = savedTab
            }
            fitTabToLayout()
        }
        .onChange(of: tab) { if !DemoMode.enabled { savedTab = tab } }
        .onReceive(NotificationCenter.default.publisher(for: AppTab.openNotification)) { n in
            guard let raw = n.object as? String, let t = AppTab(rawValue: raw) else { return }
            tab = t
            fitTabToLayout()
        }
        // 折りたたみの iPhone（Duo）を閉じた・iPad を分割表示にしたなどで下のタブに変わったとき、
        // タブに無い項目（スタッフ・印刷・店舗）を開いていたら、近い項目へ移す（何も出ない画面にしない）
        .onChange(of: sizeClass) { fitTabToLayout() }
    }

    // MARK: iPad：サイドバー

    /// サイドバーと中身を横に並べるだけにする（NavigationSplitView だと、設定の中を開いたときに
    /// 中身の画面がサイドバーの後ろへ回り込むなど、画面の切り替わりが崩れることがあったため）
    private var split: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                // 幅はサイドバー自身が決める（たたむとアイコンだけの細い帯）
                AppSidebar(tab: $tab)
                content(tab, storeInToolbar: false)
                    .id(tab)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // iPad：縦にしたらサイドバーをたたみ、横にしたら広げる（向きを変えたときだけ。そのあと手で切り替えてもよい）
            .onAppear { fitSidebar(portrait: geo.size.height > geo.size.width, animated: false) }
            .onChange(of: geo.size.height > geo.size.width) { _, portrait in fitSidebar(portrait: portrait, animated: true) }
        }
    }

    /// iPad の向きに合わせてサイドバーをたたむ・広げる（Mac はウインドウの形で変えない）
    private func fitSidebar(portrait: Bool, animated: Bool) {
        #if !targetEnvironment(macCatalyst)
        guard UIDevice.current.userInterfaceIdiom == .pad, sidebarCompact != portrait else { return }
        if animated {
            withAnimation(.snappy(duration: 0.25)) { sidebarCompact = portrait }
        } else {
            sidebarCompact = portrait
        }
        #endif
    }

    // MARK: iPhone：タブ

    /// 下のタブに出す項目（5つまで）
    static let compactTabs: [AppTab] = [.home, .schedule, .requests, .summary, .settings]

    private func fitTabToLayout() {
        guard sizeClass != .regular, !Self.compactTabs.contains(tab) else { return }
        switch tab {
        case .print: tab = .schedule
        default: tab = .settings
        }
    }

    @ViewBuilder
    private var tabs: some View {
        // 5つまで（6つ以上だと「その他」の中に入り、設定の中を開くと画面が崩れるため）。
        // スタッフ・店舗は設定から、印刷はシフト表の上のボタンから開く
        let all = Self.compactTabs
        if #available(iOS 18.0, *) {
            TabView(selection: $tab) {
                ForEach(all) { t in
                    Tab(t.title, systemImage: t.systemImage, value: t) { content(t, storeInToolbar: true) }
                }
            }
        } else {
            TabView(selection: $tab) {
                ForEach(all) { t in
                    content(t, storeInToolbar: true)
                        .tabItem { Label(t.title, systemImage: t.systemImage) }
                        .tag(t)
                }
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
        case .requests:
            NavigationStack {
                OffRequestListView()
                    .toolbar { if storeInToolbar { ToolbarItem(placement: .topBarLeading) { StoreSwitcher() } } }
            }
        case .print:
            PrintSheet(anchor: anchor, inTab: true)
        case .stores:
            NavigationStack { StoreListView() }
        case .settings:
            if DemoMode.flag("-demoTabBackup") {
                NavigationStack { BackupView() }
            } else {
                SettingsView(inTab: true)
            }
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
    /// 中身の幅の上限。Mac はほかの画面と同じく幅いっぱいに使う（HOTEL-SHIFT の Mac 版と同じ）
    #if targetEnvironment(macCatalyst)
    static let contentWidth: CGFloat = .infinity
    #else
    static let contentWidth: CGFloat = 1100
    #endif

    var openDay: (DayKey) -> Void
    var openTab: (AppTab) -> Void
    /// 店舗の切替をツールバーに出す（iPad はサイドバーにあるので出さない）
    var storeInToolbar = true

    @Environment(\.shiftStore) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showPrint = false
    @State private var showStores = false
    @State private var showStaff = false
    @State private var showCompany = false
    @State private var adding: StaffMember?
    @State private var showBackup = false
    @AppStorage("summaryTab") private var summaryTab = 0
    /// 最後にバックアップを作った日時（BackupReminder が書く）
    @AppStorage(BackupReminder.key) private var lastBackup: Double = 0
    /// ホームの数字（シフトの中身か日付が変わったときだけ数え直す）
    @State private var memo = HomeMemo()
    /// 中身の幅（数字のカードを1段に並べるか決める）
    @State private var contentWidth: CGFloat = 0
    @Environment(\.appZoom) private var zoom

    var body: some View {
        let today = store.today
        let info = memo.get(store.book, revision: store.revision, today: today)

        ScrollView {
            VStack(alignment: .leading, spacing: DS.section) {
                // 会社 → その下に店舗 → 選んでいる店舗の今日
                // iPad・Mac は店舗の切り替えを会社の帯に入れて低くする。iPhone は帯の下に店舗の並び
                if sizeClass == .compact {
                    CompanyBanner(company: store.book.company, brandHex: store.book.brandColor,
                                  storeCount: store.book.allStores.count, compact: true) { showCompany = true }
                    StoreStrip(stats: StoreTodayStat.all(store.book, today: today), compact: true) { showStores = true }
                } else {
                    CompanyBanner(company: store.book.company, brandHex: store.book.brandColor,
                                  storeCount: store.book.allStores.count, stats: StoreTodayStat.all(store.book, today: today),
                                  manageStores: { showStores = true }) { showCompany = true }
                }
                header(today)
                // 見本の画面（スクショ）には出さない
                if !DemoMode.enabled, !store.book.isEmpty, BackupReminder.isDue(last: lastBackup, now: Date()) { backupNotice }
                cards(info)
                // 出勤人数のカレンダーは、クイックメニューの下に置く
                if sizeClass == .compact {
                    todayList(info)
                    shortList(info)
                    quickMenu
                    monthCalendar(info, today: today)
                } else {
                    HStack(alignment: .top, spacing: DS.gap) {
                        VStack(spacing: DS.section) {
                            todayList(info)
                            shortList(info)
                        }
                        .frame(maxWidth: .infinity)
                        VStack(spacing: DS.section) {
                            quickMenu
                            monthCalendar(info, today: today)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(DS.page)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
            .frame(maxWidth: Self.contentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("ホーム")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if storeInToolbar { ToolbarItem(placement: .topBarLeading) { StoreSwitcher() } } }
        .shiftSheet(isPresented: $showPrint) { PrintSheet(anchor: today) }
        .shiftSheet(isPresented: $showStores) { NavigationStack { StoreListView(inSheet: true) } }
        .shiftSheet(isPresented: $showCompany) { NavigationStack { CompanyInfoView(inSheet: true) } }
        // iPhone（下のタブにスタッフが無い）では、ホームからスタッフの一覧を開く
        .shiftSheet(isPresented: $showStaff) {
            NavigationStack {
                StaffListView()
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { showStaff = false } } }
            }
        }
        .shiftSheet(item: $adding) { s in StaffEditView(member: s, isNew: true) }
        .shiftSheet(isPresented: $showBackup) {
            NavigationStack {
                BackupView()
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { showBackup = false } } }
            }
        }
    }

    // MARK: バックアップのお知らせ

    private var backupNotice: some View {
        let headline = lastBackup > 0
            ? "最後のバックアップから\(BackupReminder.days(since: lastBackup, now: Date()))日たちました"
            : "まだバックアップを作っていません"
        return Button { showBackup = true } label: {
            HStack(spacing: 12) {
                // 1行の細い帯（見出しの下で場所を取らない）
                Image(systemName: "externaldrive.badge.exclamationmark").appFont(.subheadline).foregroundStyle(.orange)
                Text(headline)
                    .appFont(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                Text("押してバックアップを作ります")
                    .appFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").appFont(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, DS.cardPadding).padding(.vertical, 10)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 今月のカレンダー（毎日の出勤人数）

    private func monthCalendar(_ info: HomeInfo, today: DayKey) -> some View {
        HomeSection(title: "\(today.month)月の出勤人数", trailing: "シフト表", action: { openTab(.schedule) }) {
            HomeMonthCalendar(month: MonthKey(today), today: today, counts: info.dayCounts) { openDay($0) }
                .padding(.vertical, 6)
        }
    }

    // MARK: 見出し

    private func header(_ today: DayKey) -> some View {
        let wd = ["日", "月", "火", "水", "木", "金", "土"][today.weekday]
        let st = store.currentStore
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(PaletteColor.fg(st.colorIndex)).frame(width: 9, height: 9)
            Text("\(st.name)の今日").appFont(.title2.weight(.bold))
            Text(verbatim: "\(today.month)月\(today.day)日（\(wd)）\(JapaneseHolidays.name(today).map { " \($0)" } ?? "")")
                .appFont(.subheadline).foregroundStyle(.secondary)
        }
    }

    // MARK: 数字のカード

    private func cards(_ info: HomeInfo) -> some View {
        LazyVGrid(columns: cardColumns, spacing: DS.gap) {
            HomeCard(title: "今日の出勤", systemImage: "person.2.fill", tint: .accentColor,
                     value: "\(info.working.count)", unit: "/ 在籍\(info.enrolled)人",
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
            HomeCard(title: "承認待ちの申請", systemImage: "tray.and.arrow.down.fill",
                     tint: info.pendingRequests > 0 ? .orange : StaffingStyle.ok,
                     value: "\(info.pendingRequests)", unit: "件",
                     note: info.pendingRequests > 0 ? "希望休の画面で承認・却下します" : "承認待ちはありません") {
                openTab(.requests)
            }
            laborCard(info)
            HomeCard(title: "労務の注意", systemImage: "hand.raised.fill",
                     tint: info.laborIssues > 0 ? .orange : StaffingStyle.ok,
                     value: "\(info.laborIssues)", unit: "件", note: "\(store.today.month)月の連勤・間隔・希望休など") {
                summaryTab = 2
                openTab(.summary)
            }
        }
    }

    /// 数字のカード6枚：広ければ1段（6列）、狭ければ2段（3列）、iPhone は2列。1枚だけ下に残らないようにする
    private var cardColumns: [GridItem] {
        let count: Int
        if sizeClass == .compact {
            count = 2
        } else {
            let oneRow = 6 * 170 * zoom + 5 * DS.gap + 2 * DS.page
            count = contentWidth >= oneRow ? 6 : 3
        }
        return Array(repeating: GridItem(.flexible(), spacing: DS.gap), count: count)
    }

    /// 今月の人件費の見込み（人件費を隠しているときは金額を出さない）
    private func laborCard(_ info: HomeInfo) -> some View {
        let visible = LaborCostLock.shared.canView
        let usage = info.laborBudget.flatMap { LaborBudget.usage(info.laborCost, budget: $0) }
        let tint: Color = !visible ? .secondary : (usage ?? 0) > 100 ? .red : (usage ?? 0) >= 90 ? .orange : .accentColor
        let note: String = !visible ? "隠しています。押して確かめると見られます"
            : usage.map { "予算の\(LaborCostView.percent($0))（\(store.today.month)月の見込み）" }
            ?? "\(store.today.month)月の見込み・予算は未設定"
        return HomeCard(title: "今月の人件費", systemImage: "yensign.circle.fill", tint: tint,
                        value: visible ? LaborCostView.short(info.laborCost) : "••••", unit: visible ? "円" : "", note: note) {
            summaryTab = 3
            openTab(.summary)
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
                    InitialAvatar(name: w.member.name, colorIndex: w.department?.colorIndex ?? 8, size: 32, photo: w.member.photo)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(w.member.name).appFont(.body.weight(.semibold))
                        Text(w.department?.name ?? "").appFont(.caption).foregroundStyle(.secondary)
                    }
                    if w.helper { Text("掛け持ち").appFont(.caption2.weight(.bold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(.tertiarySystemFill), in: Capsule()) }
                    Spacer()
                    if let b = w.block {
                        Text(b.label).appFont(.caption.weight(.bold))
                            .foregroundStyle(PaletteColor.fg(b.colorIndex))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(PaletteColor.bg(b.colorIndex), in: Capsule())
                    }
                    Text("\(w.shift.inTime)〜\(w.shift.outTime)").appFont(.subheadline).monospacedDigit()
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
                Text("適正人員を決めると、足りない日がここに出ます。").appFont(.subheadline).foregroundStyle(.secondary).padding(.vertical, 8)
            } else if info.shortDays.isEmpty {
                Label("すべての日でそろっています", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(StaffingStyle.ok).padding(.vertical, 8)
            }
            ForEach(info.shortDays.prefix(6)) { s in
                Button { openDay(s.day) } label: {
                    HStack {
                        Text(Self.dayLabel(s.day)).appFont(.subheadline.weight(.semibold)).monospacedDigit()
                        Text(s.departments.joined(separator: "・")).appFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Text("−\(s.short)人時").appFont(.subheadline.weight(.heavy)).monospacedDigit().foregroundStyle(StaffingStyle.short)
                        Image(systemName: "chevron.right").appFont(.caption).foregroundStyle(.tertiary)
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
                QuickButton(title: "スタッフ", systemImage: "person.2") {
                    if sizeClass == .regular { openTab(.staff) } else { showStaff = true }
                }
                QuickButton(title: "スタッフを追加", systemImage: "person.badge.plus") {
                    adding = store.newStaff(in: store.book.scopedDepartments.first?.id ?? store.book.departments.first?.id ?? "")
                }
                QuickButton(title: "希望休", systemImage: "calendar.badge.minus") { openTab(.requests) }
                QuickButton(title: "集計", systemImage: "chart.bar.doc.horizontal") { openTab(.summary) }
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

/// HomeInfo を覚えておく入れ物（観察しないので、描く途中で入れ替えてもよい）
final class HomeMemo {
    private var key: (Int, DayKey)?
    private var info: HomeInfo?

    func get(_ book: ShiftBook, revision: Int, today: DayKey) -> HomeInfo {
        if let key, key == (revision, today), let info { return info }
        let i = HomeInfo(book: book, today: today)
        key = (revision, today)
        info = i
        return i
    }
}

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
    /// 在籍の人数（今日の時点で辞めていない人。掛け持ちで来る人を含む）
    var enrolled = 0
    /// 承認待ちの希望休の申請
    var pendingRequests = 0
    /// 今月の人件費の見込み（円）と月予算（未設定は nil）
    var laborCost = 0
    var laborBudget: Int?
    /// 今月の毎日の出勤人数（ほかの店舗での勤務・休みは数えない）
    var dayCounts: [DayKey: Int] = [:]

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
                    let gap = StaffingCheck.gap(book.staffing, department: g.department.id, on: d,
                                                counts: table.counts(g.members, on: d))
                    if gap.short > 0 { total += gap.short; names.append(g.department.name) }
                }
                if total > 0 { shortDays.append(ShortDay(day: d, short: total, departments: names)) }
            }
        }

        unpublished = PublishDiff.changes(book, month: month)?.changes.count
        laborIssues = LaborCheck.issues(book, members: members, days: month.days).count

        enrolled = members.filter { !$0.hasLeft(on: today) }.count
        pendingRequests = members.reduce(0) { n, m in n + m.leaveRequests.filter { $0.status == .pending }.count }
        laborCost = Payroll.total(month: month, in: book)
        laborBudget = LaborBudget.value(store: book.scopeStoreID, month: month, rules: book.pay)
        for d in month.days {
            dayCounts[d] = members.filter { m in
                guard !m.hasLeft(on: d), let r = Schedule.resolve(m, on: d, in: book) else { return false }
                return !r.isOff && !r.elsewhere && ClockTime.parse(r.inTime) != nil
            }.count
        }
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
                    Text(title).appFont(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Spacer()
                    Image(systemName: systemImage)
                        .appFont(.subheadline)
                        .foregroundStyle(tint)
                        .frame(width: 32, height: 32)
                        .background(tint.opacity(0.14), in: Circle())
                }
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).appFont(.number).monospacedDigit()
                    Text(unit).appFont(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text(note).appFont(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.cardPadding)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DS.cardRadius))
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
                Text(title).appFont(.headline)
                Spacer()
                if let trailing, let action {
                    Button(trailing, action: action).appFont(.subheadline)
                }
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, DS.cardPadding).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous))
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
                Image(systemName: systemImage).appFont(.title3).foregroundStyle(Color.accentColor)
                Text(title).appFont(.caption.weight(.semibold)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// ホームの月のカレンダー（日ごとの出勤人数。押すとその日のタイムライン）
struct HomeMonthCalendar: View {
    let month: MonthKey
    let today: DayKey
    let counts: [DayKey: Int]
    var open: (DayKey) -> Void

    var body: some View {
        let days = month.days
        let lead = days[0].weekday
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(["日", "月", "火", "水", "木", "金", "土"], id: \.self) { Text($0).appFont(.caption2).foregroundStyle(.secondary) }
            ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 40) }
            ForEach(days, id: \.self) { d in dayCell(d) }
        }
    }

    private func dayCell(_ d: DayKey) -> some View {
        let n = counts[d] ?? 0
        let isToday = d == today
        let red = d.weekday == 0 || JapaneseHolidays.isHoliday(d)
        let ink: Color = red ? .red : d.weekday == 6 ? .blue : .primary
        return Button { open(d) } label: {
            VStack(spacing: 1) {
                Text("\(d.day)").appFont(.subheadline.weight(isToday ? .bold : .regular)).monospacedDigit().foregroundStyle(ink)
                Text(n > 0 ? "\(n)人" : " ").appFont(.caption2.weight(.semibold)).monospacedDigit().foregroundStyle(Color.accentColor)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(isToday ? Color.accentColor.opacity(0.12) : Color(.tertiarySystemFill).opacity(0.5),
                        in: RoundedRectangle(cornerRadius: DS.chipRadius, style: .continuous))
            .overlay {
                if isToday { RoundedRectangle(cornerRadius: DS.chipRadius, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 1.5) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(d.month)月\(d.day)日、出勤\(n)人\(isToday ? "、今日" : "")")
    }
}

/// バックアップを作った日を覚え、しばらく作っていなければホームで知らせる
enum BackupReminder {
    static let key = "lastBackupAt"
    /// これだけの日数バックアップを作っていなければ知らせる
    static let interval = 30

    /// 作った日時を残す（バックアップのファイルを作ったとき）
    static func record(_ now: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(now.timeIntervalSinceReferenceDate, forKey: key)
    }

    /// last：最後に作った日時（timeIntervalSinceReferenceDate。0 はまだ作っていない）
    static func days(since last: Double, now: Date) -> Int {
        max(0, Int((now.timeIntervalSinceReferenceDate - last) / 86_400))
    }

    static func isDue(last: Double, now: Date) -> Bool {
        last <= 0 || days(since: last, now: now) >= interval
    }
}
