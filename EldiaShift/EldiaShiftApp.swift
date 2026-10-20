import SwiftUI

@main
struct EldiaShiftApp: App {
    @State private var db: ShiftDatabase
    @State private var store: ShiftStore

    init() {
        // 画面確認用（CI のスクリーンショット）は、保存しないデータベースに見本を入れて表示する
        let d = ShiftDatabase(inMemory: DemoMode.enabled)
        let s = ShiftStore(db: d)
        if DemoMode.enabled { try? s.replaceAll(with: DemoMode.book()) }
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

    @State private var month = MonthKey.current
    @State private var showSettings = false
    @State private var importing = false

    var body: some View {
        NavigationStack {
            Group {
                if let error = db.loadError ?? store.lastError {
                    ContentUnavailableView("読み込めませんでした", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if store.book.isEmpty {
                    EmptyBookView(importing: $importing)
                } else {
                    MonthGridView(month: month)
                }
            }
            .navigationTitle(month.description)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { month = month.adding(months: -1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("前の月")
                    Button("今月") { month = .current }
                        .disabled(month == .current)
                    Button { month = month.adding(months: 1) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("次の月")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("設定")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .backupImporter(isPresented: $importing)
        }
        .onChange(of: db.changeToken) { store.refreshIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refreshIfNeeded() }
        }
    }
}

/// まだ何も入っていないとき
struct EmptyBookView: View {
    @Binding var importing: Bool

    var body: some View {
        ContentUnavailableView {
            Label("シフト表がまだありません", systemImage: "calendar.badge.plus")
        } description: {
            Text("今使っているシフト表のバックアップ（.json）を取り込むと、スタッフ・ひな形・シフトがそのまま表示されます。")
        } actions: {
            Button("バックアップを取り込む") { importing = true }
                .buttonStyle(.borderedProminent)
        }
    }
}

/// 画面確認用の見本（起動オプション -demoLayout のとき）
enum DemoMode {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-demoLayout") }

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
            StaffMember(id: "\(i + 1)", number: i, name: n, departmentID: i < 5 ? "hall" : "kitchen", active: true,
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
