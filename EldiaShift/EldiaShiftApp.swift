import SwiftUI
import UIKit
import Combine

@main
struct EldiaShiftApp: App {
    /// iCloud 共有の招待（リンク）を受け取るため
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var db: ShiftDatabase
    @State private var store: ShiftStore

    init() {
        HandFont.register()
        // 画面確認用（CI のスクリーンショット）は、保存しないデータベースに見本を入れて表示する
        let d = ShiftDatabase(inMemory: DemoMode.enabled)
        let s = ShiftStore(db: d)
        if DemoMode.enabled {
            try? s.replaceAll(with: DemoMode.book())
            let args = ProcessInfo.processInfo.arguments
            let m: GridMode = args.contains("-demoWeek") ? .week : args.contains("-demoDay") ? .day : .month
            UserDefaults.standard.set(m.rawValue, forKey: "viewMode")
            s.editing = args.contains("-demoEdit")
        }
        ShiftStore.current = s
        // 画面の題名（真ん中・18pt 太字）。Mac は 表示 → 拡大・縮小 の倍率もかける（MacZoom）
        MacZoom.applyTitle(1)
        _db = State(initialValue: d)
        _store = State(initialValue: s)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.shiftDatabase, db)
                .environment(\.shiftStore, store)
                .modifier(BrandTint(hex: store.book.brandColor))
                .modifier(MacZoom())
        }
        #if targetEnvironment(macCatalyst)
        .defaultSize(width: 1280, height: 820)
        .commands { MacCommands() }
        #endif
    }
}

#if targetEnvironment(macCatalyst)
/// Mac のメニュー（表示 → 各画面・拡大縮小・フルスクリーン、⌘P で印刷・出力、⌘, で設定）
struct MacCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("設定…") { AppTab.open(.settings) }.keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(replacing: .printItem) {
            Button("印刷・出力…") { AppTab.open(.print) }.keyboardShortcut("p", modifiers: .command)
        }
        // Mac の「表示」メニューに入れる（同じ名前のメニューを2つにしない。「フルスクリーンにする ⌃⌘F」も同じメニューに出る）
        CommandGroup(after: .toolbar) {
            Button("ホーム") { AppTab.open(.home) }.keyboardShortcut("1", modifiers: .command)
            Button("シフト表") { AppTab.open(.schedule) }.keyboardShortcut("2", modifiers: .command)
            Button("希望休") { AppTab.open(.requests) }.keyboardShortcut("3", modifiers: .command)
            Button("スタッフ") { AppTab.open(.staff) }.keyboardShortcut("4", modifiers: .command)
            Button("集計") { AppTab.open(.summary) }.keyboardShortcut("5", modifiers: .command)
            Button("店舗") { AppTab.open(.stores) }.keyboardShortcut("6", modifiers: .command)
            Divider()
            Button("拡大") { zoom = min(zoom + 1, MacZoom.steps.count - 1) }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(zoom >= MacZoom.steps.count - 1)
            Button("縮小") { zoom = max(zoom - 1, 0) }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(zoom <= 0)
            Button("標準の大きさ") { zoom = MacZoom.standard }
                .keyboardShortcut("0", modifiers: .command)
        }
    }

    @AppStorage(MacZoom.key) private var zoom = MacZoom.standard
}
#endif

/// Mac の文字の大きさ（表示 → 拡大・縮小）。Mac は iPad の画面を縮めて出すので、標準でも iPad より一回り大きくする。
/// Mac は iPhone・iPad の「文字の大きさ」の設定（Dynamic Type）を受け付けないので、アプリで決めている文字（.appFont）を倍率で大きくする
struct MacZoom: ViewModifier {
    static let key = "macZoom"
    static let steps: [CGFloat] = [0.85, 1.0, 1.15, 1.3, 1.45, 1.6, 1.8]
    static let standard = 2

    @AppStorage(key) private var zoom = standard

    /// 画面の上の真ん中に出す題名：18pt 太字（どの画面も同じ）
    static func applyTitle(_ scale: CGFloat) {
        UINavigationBar.appearance().titleTextAttributes = [.font: UIFont.systemFont(ofSize: 18 * scale, weight: .bold)]
    }

    #if targetEnvironment(macCatalyst)
    /// 切り替え（セグメント）と画面の題名の文字。これから作る部品に効く
    private static func applyAppearance(_ scale: CGFloat) {
        let segment = UIFont.systemFont(ofSize: 13 * scale)
        let segmentOn = UIFont.systemFont(ofSize: 13 * scale, weight: .semibold)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: segment], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: segmentOn], for: .selected)
        applyTitle(scale)
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: UIFont.systemFont(ofSize: 34 * scale, weight: .bold)]
    }
    #endif

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        let scale = Self.steps[min(max(zoom, 0), Self.steps.count - 1)]
        let _ = Self.applyAppearance(scale)
        // 大きさを決めていない文字（一覧の行・ボタンなど）も、本文の大きさに合わせる
        content
            .environment(\.appZoom, scale)
            .font(.system(size: AppFont.size(of: .body) * scale))
            // 切り替え（セグメント）・画面の題名は UIKit が描くので、大きさを変えたら作り直す
            .id(zoom)
        #else
        content
        #endif
    }
}

// MARK: - 拡大・縮小できる文字
// .font(.caption) の代わりに .appFont(.caption) と書く。倍率（appZoom）が 1 のときは、ふつうの .font と同じ。
// 倍率は Mac だけで変わる。印刷・画像の書き出しは倍率をかけない（そこでは .font のまま）

struct AppFont {
    enum Base {
        case style(Font.TextStyle)
        case size(CGFloat)
    }

    var base: Base
    var weight: Font.Weight?
    var design: Font.Design?

    static var largeTitle: AppFont { AppFont(base: .style(.largeTitle)) }
    static var title: AppFont { AppFont(base: .style(.title)) }
    static var title2: AppFont { AppFont(base: .style(.title2)) }
    static var title3: AppFont { AppFont(base: .style(.title3)) }
    static var headline: AppFont { AppFont(base: .style(.headline)) }
    static var body: AppFont { AppFont(base: .style(.body)) }
    static var callout: AppFont { AppFont(base: .style(.callout)) }
    static var subheadline: AppFont { AppFont(base: .style(.subheadline)) }
    static var footnote: AppFont { AppFont(base: .style(.footnote)) }
    static var caption: AppFont { AppFont(base: .style(.caption)) }
    static var caption2: AppFont { AppFont(base: .style(.caption2)) }

    static func system(size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> AppFont {
        AppFont(base: .size(size), weight: weight, design: design)
    }

    /// 大きな数字（ホームのカード・人件費の合計など）。数字はどの画面でもこの字体にそろえる
    static var number: AppFont { .system(size: 32, weight: .bold, design: .rounded) }

    func weight(_ weight: Font.Weight) -> AppFont {
        var f = self
        f.weight = weight
        return f
    }

    func bold() -> AppFont { weight(.bold) }

    /// iPhone・iPad の標準（文字の大きさ「標準」）のときの大きさ
    static func size(of style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
    }

    func font(zoom: CGFloat) -> Font {
        switch base {
        case .style(let style):
            if zoom == 1 { return .system(style, design: design, weight: weight) }
            return .system(size: Self.size(of: style) * zoom, weight: weight ?? (style == .headline ? .semibold : nil), design: design)
        case .size(let size):
            return .system(size: size * zoom, weight: weight, design: design)
        }
    }
}

extension AppFont {
    /// iPhone・iPad の「文字の大きさ」（Dynamic Type）を倍率にする。本文の大きさ ÷ 標準（17pt）。
    /// 表のようにマスの大きさが決まっている画面で、文字とマスを同じだけ大きくするために使う。
    /// 大きすぎると表に収まらないので max で止める
    static func typeScale(_ size: DynamicTypeSize, max: CGFloat = 1.6) -> CGFloat {
        let body: CGFloat = switch size {
        case .xSmall: 14
        case .small: 15
        case .medium: 16
        case .large: 17
        case .xLarge: 19
        case .xxLarge: 21
        case .xxxLarge: 23
        case .accessibility1: 28
        case .accessibility2: 33
        case .accessibility3: 40
        case .accessibility4: 47
        case .accessibility5: 53
        @unknown default: 17
        }
        return min(body / 17, max)
    }
}

private struct AppZoomKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    /// 文字の倍率（Mac の 表示 → 拡大・縮小）
    var appZoom: CGFloat {
        get { self[AppZoomKey.self] }
        set { self[AppZoomKey.self] = newValue }
    }
}

private struct AppFontModifier: ViewModifier {
    let font: AppFont
    @Environment(\.appZoom) private var zoom

    func body(content: Content) -> some View {
        content.font(font.font(zoom: zoom))
    }
}

extension View {
    func appFont(_ font: AppFont) -> some View {
        modifier(AppFontModifier(font: font))
    }
}

/// いちばん外側。サイドバー（iPad）・タブ（iPhone）。iOS 17 の iPad でも出す
struct RootView: View {
    @Environment(\.shiftDatabase) private var db
    @Environment(\.shiftStore) private var store
    @Environment(\.scenePhase) private var scenePhase

    @State private var anchor = DayKey.today
    /// 申請フォームの取り込み用リンクから開いたとき
    @State private var incomingRequest: LeaveRequestLink?

    /// 見本の画面確認・はじめて開いたとき・読み込めないときは、今までどおりシフト表の画面だけ
    private var boardOnly: Bool {
        DemoMode.staffing || DemoMode.printPage
            || ["-demoLabor", "-demoCandidates", "-demoRequests", "-demoPersonal"].contains(where: DemoMode.flag)
            || db.loadError != nil || store.lastError != nil || store.book.isEmpty
    }

    var body: some View {
        Group {
            if boardOnly {
                ShiftBoardView(anchor: $anchor)
            } else {
                MainTabsView(anchor: $anchor)
            }
        }
        .onChange(of: db.changeToken) { store.refreshIfNeeded() }
        .onOpenURL { url in
            if let link = LeaveRequestLink.decode(url) { incomingRequest = link }
        }
        .shiftSheet(item: $incomingRequest) { link in
            LeaveRequestImportSheet(month: link.month, initialText: link.formText)
        }
        // iCloud 共有の招待を受け取った結果
        .alert("シフト表の共有", isPresented: Binding(get: { ShareInbox.shared.message != nil },
                                                set: { if !$0 { ShareInbox.shared.message = nil } })) {
            Button("OK") { ShareInbox.shared.message = nil }
        } message: {
            Text(ShareInbox.shared.message ?? "")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.refreshIfNeeded()
                store.refreshToday()
            }
            // アプリを離れたら、人件費はまた隠す
            if phase == .background { LaborCostLock.shared.lock() }
        }
        // 開いたまま日付が変わったとき
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            store.refreshToday()
        }
    }
}

/// シフト表の画面（月・週・日）。見本の表示や、はじめて開いたときの画面もここで出す
struct ShiftBoardView: View {
    @Environment(\.shiftDatabase) private var db
    @Environment(\.shiftStore) private var store
    /// 表示している日（ホームから「その日を開く」ときに外から変える）
    @Binding var anchor: DayKey
    /// サイドバー・タブの中で使うとき（設定は別のタブにあるので、歯車を出さない）
    var inTabs = false
    /// 店舗の切替をツールバーに出す（iPad のサイドバーにあるときは出さない）
    var storeInToolbar = true

    @AppStorage("viewMode") private var mode: GridMode = .month
    @State private var showSettings = false
    @State private var importing = false
    @State private var showPrint = ProcessInfo.processInfo.arguments.contains("-demoPrint")

    var body: some View {
        NavigationStack {
            Group {
                if DemoMode.staffing {
                    StaffingAnalysisView(month: MonthKey(anchor))
                } else if DemoMode.flag("-demoLabor") {
                    LaborIssuesView(month: MonthKey(anchor))
                } else if DemoMode.flag("-demoCandidates"), let hall = store.book.departments.first {
                    CandidatesSheet(target: ShortageTarget(department: hall, day: .today))
                } else if DemoMode.flag("-demoRequests") {
                    OffRequestSheet(month: MonthKey(anchor))
                } else if DemoMode.flag("-demoPersonal"), let m = store.book.staff.first {
                    ScrollView { PersonalScheduleImage(member: m, month: MonthKey(anchor), book: store.book, title: "見本ホテル") }
                } else if DemoMode.printPage, let spec = PrintPlanner.pages(format: DemoMode.printLandscape ? .monthLandscape : .monthCombined,
                                                                    half: .first, departments: store.book.departments,
                                                                    anchor: .today).first {
                    // 画面確認用：印刷する1枚をそのまま表示
                    GeometryReader { g in
                        let v = PrintPageView(spec: spec, book: store.book, title: "見本ホテル")
                        let k = min(g.size.width / v.size.width, g.size.height / v.size.height)
                        v.scaleEffect(k, anchor: .topLeading).frame(width: v.size.width * k, height: v.size.height * k, alignment: .topLeading)
                    }
                } else if let error = db.loadError ?? store.lastError {
                    ContentUnavailableView("読み込めませんでした", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if store.book.isEmpty {
                    StartView(importing: $importing)
                } else if store.book.staff.isEmpty {
                    NoStaffView()
                } else {
                    if mode == .day {
                        DayTimelineView(day: anchor)
                    } else {
                        MonthGridView(mode: mode, days: mode.days(around: anchor)) { d in
                            anchor = d
                            mode = .day
                        }
                    }
                }
            }
            // 年月・前後・月週日は、上のバーではなく表のすぐ上の帯に出す
            // （上のバーに入れると、iPhone の縦では「…」にしまわれて何も見えず、iPad では年月が隠れていた）
            .safeAreaInset(edge: .top, spacing: 0) {
                if !store.book.staff.isEmpty && !store.book.isEmpty { periodBar }
            }
            .navigationTitle("シフト表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    if !store.book.isEmpty && storeInToolbar { StoreSwitcher() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !store.book.staff.isEmpty && !inTabs {
                        NavigationLink {
                            SummaryView(month: MonthKey(anchor))
                        } label: {
                            Label("集計", systemImage: "chart.bar.doc.horizontal")
                        }
                    }
                    if !store.book.staff.isEmpty {
                        Button { showPrint = true } label: { Label("印刷・PDF", systemImage: "printer") }
                    }
                    if !store.book.isEmpty { EditToggle() }
                    if !inTabs {
                        Button { showSettings = true } label: { Image(systemName: "gearshape") }
                            .accessibilityLabel("設定")
                    }
                }
            }
            .shiftSheet(isPresented: $showSettings) { SettingsView() }
            .shiftSheet(isPresented: $showPrint) { PrintSheet(anchor: anchor) }
            .backupImporter(isPresented: $importing)
        }
        .overlay(alignment: .bottom) { UndoBar() }
        .coachOverlay(.main)
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-demoCoachEdit") { CoachCenter.shared.show(.edit(), after: 1.5) }
        }
    }
}

extension ShiftBoardView {
    /// 表のすぐ上の帯：‹ 2026年10月 ›・今月・月／週／日（狭いときは2段）
    var periodBar: some View {
        let nav = HStack(spacing: 6) {
            Button { anchor = mode.step(anchor, by: -1) } label: { Image(systemName: "chevron.left").frame(width: 32, height: 32) }
                .accessibilityLabel(mode.previousLabel)
            // 週・日にも年を付ける（月は「2026年10月」のまま）
            Text(mode == .month ? mode.title(around: anchor) : "\(String(anchor.year))年 \(mode.title(around: anchor))")
                .appFont(.title3.weight(.bold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
            Button { anchor = mode.step(anchor, by: 1) } label: { Image(systemName: "chevron.right").frame(width: 32, height: 32) }
                .accessibilityLabel(mode.nextLabel)
            Button(mode.todayLabel) { anchor = .today }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(mode.days(around: anchor).contains(.today))
        }
        let picker = Picker("表示", selection: $mode) {
            Text("月").tag(GridMode.month)
            Text("週").tag(GridMode.week)
            Text("日").tag(GridMode.day)
        }
        .segmented(3)
        .labelsHidden()
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.gap) {
                nav
                Spacer(minLength: DS.gap)
                picker.fixedSize()
            }
            VStack(spacing: 8) {
                nav.frame(maxWidth: .infinity)
                picker
            }
        }
        .padding(.horizontal, DS.page).padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// 表の見せ方（月・週）
enum GridMode: String {
    case month, week, day

    var todayLabel: String { self == .month ? "今月" : self == .week ? "今週" : "今日" }
    var previousLabel: String { self == .month ? "前の月" : self == .week ? "前の週" : "前の日" }
    var nextLabel: String { self == .month ? "次の月" : self == .week ? "次の週" : "次の日" }

    /// その日を含む月、またはその日を含む週（月曜はじまり）の日付
    func days(around d: DayKey) -> [DayKey] {
        switch self {
        case .month: return MonthKey(d).days
        case .week:
            let monday = d.adding(days: -((d.weekday + 6) % 7))
            return (0..<7).map { monday.adding(days: $0) }
        case .day: return [d]
        }
    }

    func step(_ d: DayKey, by n: Int) -> DayKey {
        switch self {
        case .month: return DayKey(MonthKey(d).adding(months: n).year, MonthKey(d).adding(months: n).month, 1)
        case .week: return d.adding(days: 7 * n)
        case .day: return d.adding(days: n)
        }
    }

    func title(around d: DayKey) -> String {
        switch self {
        case .month: return MonthKey(d).description
        case .week:
            let w = days(around: d)
            let a = w.first!, b = w.last!
            return "\(a.month)/\(a.day) 〜 \(b.month)/\(b.day)"
        case .day:
            return "\(d.month)月\(d.day)日（\(["日", "月", "火", "水", "木", "金", "土"][d.weekday])）"
        }
    }
}

/// 変えた直後に下に出る「元に戻す」（数秒で消える）
struct UndoBar: View {
    @Environment(\.shiftStore) private var store
    @State private var error: String?

    var body: some View {
        Group {
            if let c = store.lastChange {
                HStack(spacing: 12) {
                    Text(c.title)
                        .appFont(.subheadline).lineLimit(1)
                    Button("元に戻す") {
                        do { try store.undo() } catch { self.error = error.localizedDescription }
                    }
                    .appFont(.subheadline.weight(.bold))
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .modifier(GlassCapsule())
                .padding(.bottom, 12)
                .coachTarget("undo")
                .onAppear { CoachCenter.shared.show(.undo(), after: 0.6) }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: c.id) {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if store.lastChange?.id == c.id { store.clearLastChange() }
                }
            }
        }
        .animation(.snappy, value: store.lastChange?.id)
        .alert("元に戻せませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}

/// iOS 26 以降は Liquid Glass、それより前はすりガラス
struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        }
    }
}

/// 画面確認用の見本（起動オプション -demoLayout のとき）
enum DemoMode {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-demoLayout") }
    static var printPage: Bool { enabled && ProcessInfo.processInfo.arguments.contains("-demoPrintPage") }
    static func flag(_ name: String) -> Bool { enabled && ProcessInfo.processInfo.arguments.contains(name) }
    static var staffing: Bool { enabled && ProcessInfo.processInfo.arguments.contains("-demoStaffing") }
    static var hourly: Bool { enabled && ProcessInfo.processInfo.arguments.contains("-demoHourly") }
    static var printLandscape: Bool { ProcessInfo.processInfo.arguments.contains("-demoLandscapePage") }

    static func book() -> ShiftBook {
        var b = ShiftBook()
        b.departments = [
            Department(id: "hall", name: "ホール", colorIndex: 0, sortOrder: 0),
            Department(id: "kitchen", name: "キッチン", colorIndex: 2, sortOrder: 1)
        ]
        b.templates = [
            TimeBlock(id: "t1", label: "早番", short: "早", inMinutes: 9 * 60, outMinutes: 18 * 60, colorIndex: 2),
            TimeBlock(id: "t2", label: "遅番", short: "遅", inMinutes: 13 * 60, outMinutes: 22 * 60, colorIndex: 3),
            TimeBlock(id: "t3", label: "夜勤", short: "夜", inMinutes: 21 * 60, outMinutes: 9 * 60, colorIndex: 8)
        ] + BackupFile.defaultOffBlocks
        let names = ["佐藤", "鈴木", "高橋", "田中", "伊藤", "渡辺", "山本", "中村"]
        let weeks: [[String?]] = [
            ["off1", "t1", "t1", "t1", "t1", "t1", "off1"],
            ["t2", "t2", "off1", "t2", "t2", "off1", "t2"],
            ["t3", "off1", "t3", "off1", "t3", "t3", "off1"],
            ["off1", "t1", "t2", "t1", "t2", "off1", "t1"]
        ]
        b.staff = names.enumerated().map { i, n in
            StaffMember(id: "\(i + 1)", number: i < 5 ? i + 1 : i - 4, name: n, departmentID: i < 5 ? "hall" : "kitchen", active: true,
                        joinDate: "", leaveDate: "", timeBlocks: [],
                        patterns: [WeekPattern(id: "p\(i)", label: "通常", colorIndex: 0, days: weeks[i % weeks.count], activeFrom: nil)],
                        activePatternID: "p\(i)", periodPatterns: [])
        }
        b.staffing.bands = [
            StaffingBand(departmentID: "hall", startHour: 9, endHour: 18, weekday: 2, saturday: 3, holiday: 3),
            StaffingBand(departmentID: "hall", startHour: 18, endHour: 23, weekday: 2, saturday: 2, holiday: 2),
            StaffingBand(departmentID: "kitchen", startHour: 10, endHour: 21, weekday: 1, saturday: 2, holiday: 2)
        ]
        let today = DayKey.today
        b.staffing.setType(.busy, for: today.adding(days: 2))
        b.cells[CellKey(staffID: "1", day: today)] = CellEntry(inTime: "10:00", outTime: "19:30", blockID: nil, isOff: false)
        b.cells[CellKey(staffID: "2", day: today.adding(days: 1))] = CellEntry(inTime: "", outTime: "", blockID: "off2", isOff: true)
        // 希望休（1人目は希望休の日に勤務が入っている → 注意が出る）
        b.staff[0].offRequests = [today.adding(days: 3).description]
        b.staff[3].offRequests = [today.adding(days: 5).description, today.adding(days: 6).description]
        // 夜勤明けの翌日に早番（勤務の間隔の注意）
        b.cells[CellKey(staffID: "3", day: today.adding(days: 1))] = CellEntry(inTime: "09:00", outTime: "18:00", blockID: "t1", isOff: false)
        b.staff[0].joinDate = "2024-04-01"
        // 2店舗：山本さんは別館にも掛け持ちで入る（明日は別館）。略称は空のまま（共通の頭を除いて「本館」「別館」と出る）
        b.stores = [Store(id: "main", name: "見本ホテル 本館", address: "神戸市中央区", hours: "24時間", colorIndex: 0, sortOrder: 0),
                    Store(id: "annex", name: "見本ホテル 別館", address: "神戸市中央区", hours: "24時間", colorIndex: 4, sortOrder: 1)]
        b.departments = b.departments.map { var d = $0; d.storeID = "main"; return d }
        b.departments.append(Department(id: "annex-hall", name: "ホール", colorIndex: 0, sortOrder: 2, storeID: "annex"))
        b.staff[6].extraStoreIDs = ["annex"]
        b.cells[CellKey(staffID: "7", day: today.adding(days: 1))] = CellEntry(inTime: "10:00", outTime: "19:00", blockID: nil,
                                                                              isOff: false, storeID: "annex")
        b.brandColor = 0x1E3A8A
        b.company.name = "見本ホテル株式会社"
        b.company.tagline = "スタッフの笑顔が、お客様の特別な時間をつくります。"
        if DemoMode.flag("-demoAppStore") {
            // App Store の画面写真用：人数が足りる日が多い、落ち着いた見本
            b.staffing.bands = [
                StaffingBand(departmentID: "hall", startHour: 9, endHour: 18, weekday: 2, saturday: 2, holiday: 2),
                StaffingBand(departmentID: "kitchen", startHour: 13, endHour: 21, weekday: 1, saturday: 1, holiday: 1)
            ]
            b.staffing.dayTypes = [:]
            b.stores[0].name = "ホテル神戸 本館"
            b.stores[1].name = "ホテル神戸 別館"
        }
        return b
    }
}
