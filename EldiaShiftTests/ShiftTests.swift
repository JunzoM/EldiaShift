import Foundation
import CoreData
import Testing
@testable import EldiaShift

/// PC版の「バックアップを保存」と同じ形の見本
private let legacyJSON = """
{
 "staff": [
  {"id": 1, "no": 2, "name": "見本A", "deptId": "front", "active": true, "joinDate": "2024-04-01", "leaveDate": "",
   "hourlyRate": 1000,
   "timeBlocks": [{"id": "b1", "label": "A_昼", "short": "昼", "inH": 9, "inM": 0, "outH": 15, "outM": 0, "colorIdx": 6}],
   "patterns": [{"id": "p1", "label": "通常", "colorIdx": 0, "days": ["off1", "b1", "b1", "b1", "b1", "b1", "off1"]}],
   "activePatternId": "p1", "periodPatterns": []},
  {"id": 2, "no": 1, "name": "見本B", "deptId": "make", "active": true, "joinDate": "2024/1/5", "leaveDate": "2026-10-15",
   "timeBlocks": [], "patterns": [], "activePatternId": null, "periodPatterns": [
     {"id": "pp1", "label": "研修", "colorIdx": 3, "startDate": "2026-10-01", "endDate": "2026-10-10",
      "days": {"2026-10-01": "g01", "2026-10-02": "", "2026-10-03": "off2"}}]},
  {"id": 3, "no": 1, "name": "見本C", "deptId": "kitchen", "active": false, "joinDate": "", "leaveDate": "",
   "timeBlocks": [], "patterns": [], "activePatternId": null, "periodPatterns": []},
  {"id": 4, "name": ""}
 ],
 "globalTemplates": [
  {"id": "g01", "label": "日勤", "short": "日", "inH": 10, "inM": 0, "outH": 22, "outM": 0, "colorIdx": 0},
  {"id": "g02", "label": "夜勤", "short": "夜", "inH": 22, "inM": 0, "outH": 10, "outM": 0, "colorIdx": 8}
 ],
 "cellData": {
  "1|2026-10-07": {"inTime": "10:00", "outTime": "19:30", "blockId": null, "isOff": false, "auto": false},
  "1|2026-10-08": {"inTime": "", "outTime": "", "blockId": "off2", "isOff": true, "auto": false},
  "2|2026-10-05": {"inTime": "9:00", "outTime": "18:00", "blockId": null, "isOff": false},
  "bad-key": {"inTime": "10:00", "outTime": "11:00"},
  "1|2026-10-09": {"inTime": "xx", "outTime": "", "blockId": null, "isOff": false}
 }
}
"""

private func legacyBook() throws -> (ShiftBook, BackupFile.Summary) {
    try BackupFile.read(Data(legacyJSON.utf8))
}

private func member(_ book: ShiftBook, _ id: String) -> StaffMember {
    book.staff.first { $0.id == id }!
}

@Suite("バックアップの取り込み")
struct BackupReadTests {
    @Test("PC版のファイルを読める（名前の無いスタッフ・壊れた入力は飛ばす）")
    func readsLegacy() throws {
        let (book, summary) = try legacyBook()
        #expect(book.staff.map(\.name).sorted() == ["見本A", "見本B", "見本C"])
        #expect(summary.staff == 3)
        #expect(summary.cells == 3)
        #expect(summary.skipped == 3)   // 名前なし1人 + キー不正1件 + 時刻不正1件
        #expect(summary.firstDay == DayKey(2026, 10, 5))
        #expect(summary.lastDay == DayKey(2026, 10, 8))
        #expect(book.cells[CellKey(staffID: "2", day: DayKey(2026, 10, 5))]?.inTime == "09:00")
        #expect(member(book, "2").joinDate == "2024-01-05")
    }

    @Test("部門はメイク→キッチン→フロントの順で作られる")
    func departmentsInLegacyOrder() throws {
        let (book, _) = try legacyBook()
        #expect(book.departments.sorted { $0.sortOrder < $1.sortOrder }.map(\.name) == ["メイク", "キッチン", "フロント"])
    }

    @Test("休みのひな形が無ければ足される")
    func addsOffBlocks() throws {
        let (book, summary) = try legacyBook()
        #expect(summary.templates == 2)
        #expect(book.templates.map(\.id) == ["g01", "g02", "off1", "off2", "off3"])
        #expect(book.templates.first { $0.id == "off1" }?.isOff == true)
    }

    @Test("シフト表でないファイルは断る")
    func rejectsOtherFiles() {
        #expect(throws: BackupFile.Failure.self) { try BackupFile.read(Data("[1,2,3]".utf8)) }
        #expect(throws: BackupFile.Failure.self) { try BackupFile.read(Data("{\"hello\": 1}".utf8)) }
        #expect(throws: BackupFile.Failure.self) { try BackupFile.read(Data("not json".utf8)) }
    }

    @Test("書き出して読み直すと同じ内容になる")
    func roundTrip() throws {
        let (book, _) = try legacyBook()
        let (again, summary) = try BackupFile.read(try BackupFile.write(book))
        #expect(summary.skipped == 0)
        #expect(again.staff.sorted { $0.id < $1.id } == book.staff.sorted { $0.id < $1.id })
        #expect(again.templates == book.templates)
        #expect(again.cells == book.cells)
        #expect(again.departments.sorted { $0.sortOrder < $1.sortOrder } == book.departments.sorted { $0.sortOrder < $1.sortOrder })
    }
}

@Suite("シフトの決まり方")
struct ScheduleTests {
    @Test("週のくり返し：日曜が days[0]")
    func weeklyPattern() throws {
        let (book, _) = try legacyBook()
        let a = member(book, "1")
        // 2026-10-04 は日曜 → off1（休み）、10-05 月曜 → b1（9:00〜15:00）
        #expect(DayKey(2026, 10, 4).weekday == 0)
        let sun = try #require(Schedule.resolve(a, on: DayKey(2026, 10, 4), in: book))
        #expect(sun.isOff && sun.isAuto && sun.blockID == "off1")
        let mon = try #require(Schedule.resolve(a, on: DayKey(2026, 10, 5), in: book))
        #expect(mon.inTime == "09:00" && mon.outTime == "15:00" && mon.patternLabel == "通常")
        #expect(mon.hours == 6)
    }

    @Test("手で入れた内容がくり返しより優先される")
    func manualWins() throws {
        let (book, _) = try legacyBook()
        let r = try #require(Schedule.resolve(member(book, "1"), on: DayKey(2026, 10, 7), in: book))
        #expect(!r.isAuto && r.inTime == "10:00" && r.outTime == "19:30")
        #expect(r.hours == 9.5)
    }

    @Test("期間の予定：指定がない日は空き、退職日の翌日からは出ない")
    func periodAndLeave() throws {
        let (book, _) = try legacyBook()
        let b = member(book, "2")
        let d1 = try #require(Schedule.resolve(b, on: DayKey(2026, 10, 1), in: book))
        #expect(d1.isPeriod && d1.blockID == "g01")
        #expect(Schedule.resolve(b, on: DayKey(2026, 10, 2), in: book) == nil)
        #expect(Schedule.resolve(b, on: DayKey(2026, 10, 4), in: book) == nil)
        #expect(Schedule.resolve(b, on: DayKey(2026, 10, 3), in: book)?.isOff == true)
        #expect(b.hasLeft(on: DayKey(2026, 10, 15)) == false)
        #expect(b.hasLeft(on: DayKey(2026, 10, 16)))
    }

    @Test("使い始めの日がいちばん新しいくり返しが使われる")
    func activeFrom() {
        let old = WeekPattern(id: "a", label: "旧", colorIndex: 0, days: Array(repeating: "x", count: 7), activeFrom: "2026-01-01")
        let new = WeekPattern(id: "b", label: "新", colorIndex: 0, days: Array(repeating: "y", count: 7), activeFrom: "2026-10-10")
        let m = StaffMember(id: "1", number: 0, name: "n", departmentID: "", active: true, joinDate: "", leaveDate: "",
                            timeBlocks: [], patterns: [old, new], activePatternID: "a", periodPatterns: [])
        #expect(Schedule.weeklyPattern(for: m, on: "2026-10-09")?.id == "a")
        #expect(Schedule.weeklyPattern(for: m, on: "2026-10-10")?.id == "b")
        #expect(Schedule.weeklyPattern(for: m, on: "2025-12-31") == nil)
    }

    @Test("夜勤（日またぎ）の時間")
    func overnight() {
        #expect(ClockTime.hours(from: 22 * 60, to: 10 * 60) == 12)
        #expect(ClockTime.hours(from: 10 * 60, to: 10 * 60) == 24)
        #expect(ClockTime.parse("24:00") == 1440)
        #expect(ClockTime.parse("25:00") == nil)
    }

    @Test("表に出す人：退職月までは出し、在籍していない人は出さない")
    func visibility() throws {
        let (book, _) = try legacyBook()
        let oct = book.staffByDepartment(visibleIn: MonthKey(2026, 10)).flatMap(\.members).map(\.name)
        #expect(oct == ["見本B", "見本A"])   // メイク → フロント の順。見本C は在籍していない
        let nov = book.staffByDepartment(visibleIn: MonthKey(2026, 11)).flatMap(\.members).map(\.name)
        #expect(nov == ["見本A"])
    }

    @Test("月の集計")
    func monthSummary() throws {
        let (book, _) = try legacyBook()
        let s = MonthSummary.of(member(book, "1"), month: MonthKey(2026, 10), in: book)
        // 10月：平日22日（うち 10/7 は手入力 9.5h、10/8 は有休）、日・土 9日 は休み
        #expect(s.workDays == 21)
        #expect(s.offDays == 10)
        #expect(s.hours == 20 * 6 + 9.5)
    }
}

@Suite("端末内の保存")
@MainActor
struct StorageTests {
    @Test("保存して読み直すと同じ内容になる")
    func saveAndLoad() throws {
        let (book, _) = try legacyBook()
        let store = ShiftStore(db: ShiftDatabase(inMemory: true))
        try store.replaceAll(with: book)
        #expect(store.book.staff.sorted { $0.id < $1.id } == book.staff.sorted { $0.id < $1.id })
        #expect(store.book.templates == book.templates)
        #expect(store.book.cells == book.cells)
        #expect(store.book.departments == book.departments.sorted { $0.sortOrder < $1.sortOrder })
    }

    @Test("同じ人・同じ日の記録が2つあれば、新しい方を残す")
    func dedupe() throws {
        let db = ShiftDatabase(inMemory: true)
        let ctx = db.viewContext
        let team = try ShiftRecords.currentTeam(ctx)
        for (time, at) in [("09:00", Date(timeIntervalSince1970: 100)), ("13:00", Date(timeIntervalSince1970: 200))] {
            let r = NSEntityDescription.insertNewObject(forEntityName: ShiftModel.Entity.cell, into: ctx)
            r.setValue(team, forKey: "team")
            r.setValue("1", forKey: "staffKey")
            r.setValue("2026-10-01", forKey: "day")
            r.setValue(time, forKey: "inTime")
            r.setValue("18:00", forKey: "outTime")
            r.setValue(at, forKey: "updatedAt")
        }
        try db.save()
        let book = try ShiftRecords.load(ctx)
        #expect(book.cells.count == 1)
        #expect(book.cells.values.first?.inTime == "13:00")
        let left = try ctx.fetch(NSFetchRequest<NSManagedObject>(entityName: ShiftModel.Entity.cell))
        #expect(left.count == 1)
    }

    @Test("取り込み直すと前の内容は消える")
    func replaceRemovesOld() throws {
        let (book, _) = try legacyBook()
        let store = ShiftStore(db: ShiftDatabase(inMemory: true))
        try store.replaceAll(with: book)
        var smaller = book
        smaller.staff = Array(book.staff.prefix(1))
        smaller.cells = [:]
        try store.replaceAll(with: smaller)
        #expect(store.book.staff.count == 1)
        #expect(store.book.cells.isEmpty)
    }
}

@Suite("祝日")
struct HolidayTests {
    @Test("2026年の祝日")
    func holidays2026() {
        let expected = ["2026-01-01", "2026-01-12", "2026-02-11", "2026-02-23", "2026-03-20", "2026-04-29",
                        "2026-05-03", "2026-05-04", "2026-05-05", "2026-05-06", "2026-07-20", "2026-08-11",
                        "2026-09-21", "2026-09-22", "2026-09-23", "2026-10-12", "2026-11-03", "2026-11-23"]
        #expect(JapaneseHolidays.holidays(in: 2026).keys.sorted().map(\.description) == expected)
        #expect(JapaneseHolidays.name(DayKey(2026, 9, 22)) == "国民の休日")
        #expect(JapaneseHolidays.name(DayKey(2026, 5, 6)) == "振替休日")
    }
}
