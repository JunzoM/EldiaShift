import Foundation
import Testing
@testable import EldiaShift

/// 速さの計測（CI のログに「BENCH 名前 ミリ秒」を出す）。
/// 月のシフト表を1回描くときと同じ計算・ホーム・まとめて入力を、大きめの見本で測る
@Suite("速さの計測", .serialized)
@MainActor
struct PerfBench {
    /// 2店舗・4部門・60人（掛け持ちあり）・全部門に適正人員・手入力 300 マス
    static func bigBook() -> ShiftBook {
        var b = ShiftBook()
        b.stores = [Store(id: "a", name: "本館", sortOrder: 0), Store(id: "b", name: "別館", sortOrder: 1)]
        b.departments = [
            Department(id: "make", name: "メイク", colorIndex: 7, sortOrder: 0, storeID: "a"),
            Department(id: "kitchen", name: "キッチン", colorIndex: 2, sortOrder: 1, storeID: "a"),
            Department(id: "front", name: "フロント", colorIndex: 0, sortOrder: 2, storeID: "a"),
            Department(id: "b-make", name: "メイク", colorIndex: 7, sortOrder: 3, storeID: "b")
        ]
        b.templates = [
            TimeBlock(id: "t1", label: "早番", short: "早", inMinutes: 9 * 60, outMinutes: 18 * 60, colorIndex: 2),
            TimeBlock(id: "t2", label: "遅番", short: "遅", inMinutes: 13 * 60, outMinutes: 22 * 60, colorIndex: 3),
            TimeBlock(id: "t3", label: "夜勤", short: "夜", inMinutes: 21 * 60, outMinutes: 9 * 60, colorIndex: 8)
        ] + BackupFile.defaultOffBlocks
        let weeks: [[String?]] = [
            ["off1", "t1", "t1", "t1", "t1", "t1", "off1"],
            ["t2", "t2", "off1", "t2", "t2", "off1", "t2"],
            ["t3", "off1", "t3", "off1", "t3", "t3", "off1"]
        ]
        let depts = ["make", "kitchen", "front", "b-make"]
        b.staff = (0..<60).map { i in
            StaffMember(id: "s\(i)", number: i / 4 + 1, name: "スタッフ\(i)", departmentID: depts[i % 4], active: true,
                        joinDate: "", leaveDate: "", timeBlocks: [],
                        patterns: [WeekPattern(id: "p\(i)", label: "通常", colorIndex: 0, days: weeks[i % 3], activeFrom: nil)],
                        activePatternID: "p\(i)", periodPatterns: [],
                        offRequests: ["2026-11-\(String(format: "%02d", i % 28 + 1))"],
                        extraStoreIDs: i % 10 == 3 ? ["b"] : [])
        }
        b.staffing.bands = depts.flatMap { d in [
            StaffingBand(departmentID: d, startHour: 9, endHour: 18, weekday: 3, saturday: 4, holiday: 4),
            StaffingBand(departmentID: d, startHour: 18, endHour: 23, weekday: 2, saturday: 2, holiday: 2)
        ] }
        for i in 0..<300 {
            let d = DayKey(2026, 11, i % 30 + 1)
            b.cells[CellKey(staffID: "s\(i % 60)", day: d)] = CellEntry(inTime: "10:00", outTime: "19:00", blockID: nil, isOff: false,
                                                                       storeID: i % 7 == 0 ? "b" : nil)
        }
        b.scopeStoreID = "a"
        return b
    }

    /// 月のシフト表を1回描くときと同じ計算（表・注意・不足の印・時間帯別在籍人数・マスの見た目）
    static func gridWork(_ book: ShiftBook, days: [DayKey]) -> Int {
        let groups = book.staffByDepartment(visibleIn: MonthKey(days[0]))
        let shown = groups.flatMap(\.members)
        let table = ScheduleTable(book: book, members: shown, days: days)
        let issues = LaborCheck.issues(book, members: shown, days: days)
        var total = issues.count
        for d in days {
            for g in groups where book.staffing.hasPlan(for: g.department.id) {
                total += StaffingCheck.gap(book.staffing, department: g.department.id, members: g.members, on: d) {
                    table.working($0, on: $1, hour: $2)
                }.short
            }
        }
        for g in groups {
            for d in days {
                for h in 0..<24 { total += table.working(g.members, on: d, hour: h) }
            }
        }
        for m in shown {
            for d in days {
                if let r = table.get(m, d), book.block(r.blockID, for: m) != nil { total += 1 }
                if d.weekday == 0 || JapaneseHolidays.isHoliday(d) { total += 1 }
                if m.requestsOff(d) { total += 1 }
            }
        }
        return total
    }

    static func ms(_ name: String, repeat n: Int = 3, _ body: () throws -> Void) rethrows -> Double {
        let clock = ContinuousClock()
        try body()   // 1回目（キャッシュを温める）は数えない
        let t = try clock.measure { for _ in 0..<n { try body() } }
        let v = Double(t.components.seconds) * 1000 + Double(t.components.attoseconds) / 1e15
        let avg = v / Double(n)
        print("BENCH \(name) \(String(format: "%.1f", avg))ms")
        return avg
    }

    @Test("月のシフト表1回分の計算")
    func grid() {
        let book = Self.bigBook()
        let days = MonthKey(2026, 11).days
        var sink = 0
        _ = Self.ms("grid-month") { sink += Self.gridWork(book, days: days) }
        #expect(sink > 0)
    }

    @Test("ホームの数字")
    func home() {
        let book = Self.bigBook()
        var sink = 0
        _ = Self.ms("home") { sink += HomeInfo(book: book, today: DayKey(2026, 11, 2)).working.count }
        #expect(sink >= 0)
    }

    @Test("日付の計算（曜日・日をずらす）")
    func dates() {
        var sink = 0
        _ = Self.ms("dates-100k") {
            var d = DayKey(2026, 1, 1)
            for _ in 0..<100_000 { sink &+= d.weekday; d = d.adding(days: 1) }
        }
        #expect(sink != 0)
    }

    @Test("まとめて入力（300マス）")
    func batchWrite() throws {
        let store = ShiftStore(db: ShiftDatabase(inMemory: true))
        try store.replaceAll(with: Self.bigBook())
        var flip = false
        _ = try Self.ms("batch-300") {
            flip.toggle()
            let items: [(CellKey, CellEntry?)] = (0..<300).map { i in
                (CellKey(staffID: "s\(i % 60)", day: DayKey(2026, 11, i / 60 + 1)),
                 CellEntry(inTime: flip ? "09:00" : "10:00", outTime: "18:00", blockID: nil, isOff: false))
            }
            try store.setCells(items, title: "bench")
        }
        #expect(store.book.cells.count >= 300)
    }
}
