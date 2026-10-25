import Foundation
import Testing
@testable import EldiaShift

@Suite("会社と店舗")
@MainActor
struct CompanyTests {
    @Test("会社の情報が端末内の保存・バックアップで残る")
    func persistence() throws {
        let store = ShiftStore(db: ShiftDatabase(inMemory: true))
        var c = CompanyInfo()
        c.name = "株式会社ベストディライト"
        c.tagline = "スタッフの笑顔が、お客様の特別な時間をつくります。"
        c.logo = Data([1, 2, 3])
        try store.setCompany(c)
        #expect(store.book.company == c)
        let loaded = try ShiftRecords.load(store.db.viewContext)
        #expect(loaded.company == c)
        let (again, _) = try BackupFile.read(try BackupFile.write(loaded))
        #expect(again.company == c)
    }

    @Test("前の版の設定（会社なし・項目が足りない）も読める")
    func older() throws {
        let c = try JSONDecoder().decode(CompanyInfo.self, from: Data(#"{"name":"A"}"#.utf8))
        #expect(c.name == "A")
        #expect(c.tagline.isEmpty)
        #expect(c.logo == nil)
    }

    @Test("店舗ごとの今日の出勤と承認待ちを数える（掛け持ちは入る店舗で数える）")
    func storeStats() {
        var b = ShiftBook()
        b.stores = [Store(id: "a", name: "A店", sortOrder: 0), Store(id: "b", name: "B店", sortOrder: 1)]
        b.departments = [Department(id: "da", name: "フロント", colorIndex: 0, sortOrder: 0, storeID: "a"),
                         Department(id: "db", name: "フロント", colorIndex: 0, sortOrder: 1, storeID: "b")]
        func m(_ id: String, _ dept: String) -> StaffMember {
            StaffMember(id: id, number: 1, name: id, departmentID: dept, active: true, joinDate: "", leaveDate: "",
                        timeBlocks: [], patterns: [], activePatternID: nil, periodPatterns: [])
        }
        var helper = m("h", "da")
        helper.extraStoreIDs = ["b"]
        var withRequest = m("r", "db")
        withRequest.leaveRequests = [LeaveRequest(id: "x", day: "2026-11-20", note: "", status: .pending, receivedAt: Date(), decidedAt: nil)]
        b.staff = [m("s1", "da"), helper, withRequest]
        let today = DayKey(2026, 11, 10)
        let work = CellEntry(inTime: "09:00", outTime: "18:00", blockID: nil, isOff: false)
        b.cells[CellKey(staffID: "s1", day: today)] = work
        b.cells[CellKey(staffID: "h", day: today)] = CellEntry(inTime: "09:00", outTime: "18:00", blockID: nil, isOff: false, storeID: "b")
        let s = StoreTodayStat.all(b, today: today)
        #expect(s["a"]?.working == 1)
        #expect(s["b"]?.working == 1)
        #expect(s["b"]?.pending == 1)
        #expect(s["a"]?.pending ?? 0 == 0)
    }
}
