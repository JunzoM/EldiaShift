import SwiftUI

@main
struct EldiaShiftApp: App {
    @State private var db: ShiftDatabase
    @State private var store: ShiftStore

    init() {
        CoachTips.configure()
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
        _db = State(initialValue: d)
        _store = State(initialValue: s)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(db)
                .environment(store)
        }
    }
}

struct RootView: View {
    @Environment(ShiftDatabase.self) private var db
    @Environment(ShiftStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("viewMode") private var mode: GridMode = .month
    @State private var anchor = DayKey.today
    @State private var showSettings = false
    @State private var importing = false
    @State private var showPrint = ProcessInfo.processInfo.arguments.contains("-demoPrint")

    var body: some View {
        NavigationStack {
            Group {
                if DemoMode.printPage, let spec = PrintPlanner.pages(format: DemoMode.printLandscape ? .monthLandscape : .monthCombined,
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
            .navigationTitle(mode.title(around: anchor))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { anchor = mode.step(anchor, by: -1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel(mode.previousLabel)
                    Button(mode.todayLabel) { anchor = .today }
                        .disabled(mode.days(around: anchor).contains(.today))
                    Button { anchor = mode.step(anchor, by: 1) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel(mode.nextLabel)
                }
                ToolbarItem(placement: .principal) {
                    if !store.book.staff.isEmpty {
                        Picker("表示", selection: $mode) {
                            Text("月").tag(GridMode.month)
                            Text("週").tag(GridMode.week)
                            Text("日").tag(GridMode.day)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 168)
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !store.book.staff.isEmpty {
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
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("設定")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showPrint) { PrintSheet(anchor: anchor) }
            .backupImporter(isPresented: $importing)
        }
        .overlay(alignment: .bottom) { UndoBar() }
        .onChange(of: db.changeToken) { store.refreshIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refreshIfNeeded() }
        }
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
    @Environment(ShiftStore.self) private var store
    @State private var error: String?

    var body: some View {
        Group {
            if let c = store.lastChange {
                HStack(spacing: 12) {
                    Text("\(c.staffName) \(c.key.day.month)/\(c.key.day.day) を変更しました")
                        .font(.subheadline).lineLimit(1)
                    Button("元に戻す") {
                        do { try store.undo() } catch { self.error = error.localizedDescription }
                    }
                    .font(.subheadline.weight(.bold))
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .modifier(GlassCapsule())
                .padding(.bottom, 12)
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
        let today = DayKey.today
        b.cells[CellKey(staffID: "1", day: today)] = CellEntry(inTime: "10:00", outTime: "19:30", blockID: nil, isOff: false)
        b.cells[CellKey(staffID: "2", day: today.adding(days: 1))] = CellEntry(inTime: "", outTime: "", blockID: "off2", isOff: true)
        return b
    }
}
