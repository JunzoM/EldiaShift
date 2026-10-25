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
