import Foundation
import Testing
@testable import EldiaShift

/// HOTEL SHIFT から移した機能（顔写真・雇用形態・削除前の確認）
@Suite("スタッフの追加項目")
@MainActor
struct StaffExtrasTests {
    private func member(_ id: String = "s1") -> StaffMember {
        StaffMember(id: id, number: 1, name: "見本", departmentID: "d", active: true, joinDate: "", leaveDate: "",
                    timeBlocks: [], patterns: [], activePatternID: nil, periodPatterns: [])
    }

    @Test("雇用形態・顔写真が端末内の保存で残る")
    func storageRoundTrip() throws {
        let store = ShiftStore(db: ShiftDatabase(inMemory: true))
        var m = member()
        m.employment = "パート"
        m.photo = Data([0xFF, 0xD8, 0x01, 0x02, 0xFF, 0xD9])
        try store.save(m)
        let loaded = try ShiftRecords.load(store.db.viewContext)
        let back = try #require(loaded.staff.first { $0.id == "s1" })
        #expect(back.employment == "パート")
        #expect(back.photo == m.photo)
    }

    @Test("前の版の記録（雇用形態・写真なし）も読める")
    func olderDetail() throws {
        let old = #"{"timeBlocks":[],"patterns":[],"periodPatterns":[]}"#
        let d = try JSONDecoder().decode(ShiftRecords.StaffDetail.self, from: Data(old.utf8))
        #expect(d.employment == nil)
        #expect(d.photo == nil)
    }

    @Test("バックアップに雇用形態・顔写真が入り、読み戻せる")
    func backupRoundTrip() throws {
        var book = ShiftBook()
        var m = member()
        m.employment = "契約社員"
        m.photo = Data((0..<300).map { UInt8($0 % 256) })
        book.staff = [m, member("s2")]
        let (again, _) = try BackupFile.read(try BackupFile.write(book))
        #expect(again.staff.first { $0.id == "s1" }?.employment == "契約社員")
        #expect(again.staff.first { $0.id == "s1" }?.photo == m.photo)
        #expect(again.staff.first { $0.id == "s2" }?.employment == "")
        #expect(again.staff.first { $0.id == "s2" }?.photo == nil)
    }

    @Test("削除の前に、一緒に消えるものを数える")
    func deletionImpact() {
        var book = ShiftBook()
        var m = member()
        m.patterns = [WeekPattern(id: "p", label: "通常", colorIndex: 0, days: Array(repeating: nil, count: 7), activeFrom: nil)]
        m.offRequests = ["2026-11-03"]
        book.staff = [m, member("s2")]
        let entry = CellEntry(inTime: "09:00", outTime: "18:00", blockID: nil, isOff: false)
        book.cells[CellKey(staffID: "s1", day: DayKey(2026, 10, 1))] = entry
        book.cells[CellKey(staffID: "s1", day: DayKey(2026, 10, 25))] = entry
        book.cells[CellKey(staffID: "s1", day: DayKey(2026, 11, 2))] = entry
        book.cells[CellKey(staffID: "s2", day: DayKey(2026, 11, 2))] = entry

        let impact = StaffDeletionImpact(member: m, book: book, today: DayKey(2026, 10, 25))
        #expect(impact.enteredDays == 3)
        #expect(impact.upcomingDays == 2)
        #expect(impact.weekPatterns == 1)
        #expect(impact.offRequests == 1)
        #expect(impact.message.contains("3日分"))
        #expect(impact.message.contains("退職"))

        let empty = StaffDeletionImpact(member: member("s3"), book: book, today: DayKey(2026, 10, 25))
        #expect(empty.enteredDays == 0)
        #expect(empty.message.contains("まだありません"))
    }
}

@Suite("シフトのメモ・時間の刻み")
@MainActor
struct ShiftNoteTests {
    private func member() -> StaffMember {
        StaffMember(id: "s1", number: 1, name: "見本", departmentID: "d", active: true, joinDate: "", leaveDate: "",
                    timeBlocks: [], patterns: [], activePatternID: nil, periodPatterns: [])
    }

    @Test("メモは保存・バックアップで残り、時刻だけ変えても消えない")
    func noteKept() throws {
        let store = ShiftStore(db: ShiftDatabase(inMemory: true))
        try store.save(member())
        let key = CellKey(staffID: "s1", day: DayKey(2026, 11, 10))
        try store.setCell(key, to: CellEntry(inTime: "09:00", outTime: "18:00", blockID: nil, isOff: false, note: "鍵の受け渡し"))
        // 時刻だけ変える（メモを渡さない）
        try store.setCell(key, to: CellEntry(inTime: "10:00", outTime: "19:00", blockID: nil, isOff: false))
        #expect(store.book.cells[key]?.note == "鍵の受け渡し")
        #expect(store.book.cells[key]?.inTime == "10:00")
        let loaded = try ShiftRecords.load(store.db.viewContext)
        #expect(loaded.cells[key]?.note == "鍵の受け渡し")
        #expect(Schedule.resolve(loaded.staff[0], on: key.day, in: loaded)?.note == "鍵の受け渡し")
        let (again, _) = try BackupFile.read(try BackupFile.write(loaded))
        #expect(again.cells[key]?.note == "鍵の受け渡し")
        // 空の文字でメモを消す
        var cleared = try #require(store.book.cells[key])
        cleared.note = ""
        try store.setCell(key, to: cleared)
        #expect(store.book.cells[key]?.note == nil)
    }

    @Test("15分刻みでそろえる・動かす")
    func quarterStep() {
        #expect(TimelineMath.snap(22, step: 15) == 15)
        #expect(TimelineMath.snap(23, step: 15) == 30)
        #expect(TimelineMath.drag(.right, in0: 540, out0: 1080, delta: 15, step: 15) == (540, 1095))
        #expect(TimelineMath.drag(.right, in0: 540, out0: 1080, delta: -900, step: 15) == (540, 555))
@Suite("人件費の予算・明細")
@MainActor
struct LaborBudgetTests {
    @Test("予算の読み方")
    func parse() {
        #expect(LaborBudget.parse("1,200,000") == 1_200_000)
        #expect(LaborBudget.parse("¥ 980000円") == 980_000)
        #expect(LaborBudget.parse("１２０万") == 1_200_000)
        #expect(LaborBudget.parse("12.5万") == 125_000)
        #expect(LaborBudget.parse("abc") == nil)
        #expect(LaborBudget.parse("-5") == nil)
        #expect(LaborBudget.parse("") == nil)
    }

    @Test("月だけの予算 → 毎月の予算の順。前の版の設定も読める")
    func lookup() throws {
        var r = PayRules()
        r.budgets[LaborBudget.key(store: "s1", month: nil)] = 1_000_000
        r.budgets[LaborBudget.key(store: "s1", month: MonthKey(2026, 12))] = 1_500_000
        #expect(LaborBudget.value(store: "s1", month: MonthKey(2026, 11), rules: r) == 1_000_000)
        #expect(LaborBudget.value(store: "s1", month: MonthKey(2026, 12), rules: r) == 1_500_000)
        #expect(LaborBudget.value(store: "s2", month: MonthKey(2026, 12), rules: r) == nil)
        #expect(LaborBudget.usage(900_000, budget: 1_000_000) == 90)
        let back = try JSONDecoder().decode(PayRules.self, from: JSONEncoder().encode(r))
        #expect(back.budgets == r.budgets)
        let old = try JSONDecoder().decode(PayRules.self, from: Data(#"{"overtimeRate":25}"#.utf8))
        #expect(old.budgets.isEmpty)
        #expect(LaborCostView.change(1_100_000, from: 1_000_000) == "+10.0%")
    }

    @Test("シフト明細のCSVは勤務1日ずつ、合計は人件費と同じ")
    func detailCSV() {
        var book = ShiftBook()
        var m = StaffMember(id: "s1", number: 1, name: "見本", departmentID: "d", active: true, joinDate: "", leaveDate: "",
                            timeBlocks: [], patterns: [], activePatternID: nil, periodPatterns: [])
        m.wages = [WageEntry(id: "w", from: "2026-01-01", kind: .hourly, amount: 1200)]
        book.staff = [m]
        let e = CellEntry(inTime: "09:00", outTime: "18:00", blockID: nil, isOff: false)
        book.cells[CellKey(staffID: "s1", day: DayKey(2026, 11, 2))] = e
        book.cells[CellKey(staffID: "s1", day: DayKey(2026, 11, 3))] = e
        let csv = Payroll.detailCSV(rows: [(member: m, department: "フロント")], month: MonthKey(2026, 11), in: book)
        let lines = csv.split(separator: "\r\n")
        #expect(lines.count == 3)
        #expect(lines[1].hasPrefix("2026-11-02,月,フロント,見本"))
        let sum = lines.dropFirst().compactMap { Int($0.split(separator: ",", omittingEmptySubsequences: false)[16]) }.reduce(0, +)
        let pay = Payroll.pay(of: m, month: MonthKey(2026, 11), in: book, rules: book.pay)
        #expect(abs(sum - pay.total) <= 1)
    }
}
