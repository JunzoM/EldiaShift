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

@Suite("タイムラインの計算")
struct TimelineTests {
    @Test("30分単位にそろえる")
    func snap() {
        #expect(TimelineMath.snap(44) == 30)
        #expect(TimelineMath.snap(46) == 60)
        #expect(TimelineMath.snap(-20) == -30)
    }

    @Test("移動：出勤は当日 23:30 まで、退勤は翌10:00まで")
    func move() {
        // 9:00〜18:00 を 3時間後ろへ
        #expect(TimelineMath.drag(.move, in0: 540, out0: 1080, delta: 180) == (720, 1260))
        // 夜勤 22:00〜翌10:00 はそれ以上後ろへ動かない
        #expect(TimelineMath.drag(.move, in0: 1320, out0: 2040, delta: 120) == (1320, 2040))
        // 朝5:00より前には動かない
        #expect(TimelineMath.drag(.move, in0: 360, out0: 900, delta: -300) == (300, 840))
    }

    @Test("長さを変える：30分より短く・24時間より長くはならない")
    func resize() {
        #expect(TimelineMath.drag(.left, in0: 540, out0: 1080, delta: 600) == (1050, 1080))
        #expect(TimelineMath.drag(.right, in0: 540, out0: 1080, delta: -900) == (540, 570))
        #expect(TimelineMath.drag(.right, in0: 540, out0: 1080, delta: 3000) == (540, 1980))
    }

    @Test("空きを押すと8時間（翌10:00まで）")
    func newSpan() {
        #expect(TimelineMath.newSpan(at: 600)! == (600, 1080))
        #expect(TimelineMath.newSpan(at: 1380)! == (1380, 1860))
        #expect(TimelineMath.newSpan(at: 1800) == nil)
        #expect(TimelineMath.newSpan(at: 100)! == (300, 780))
    }

    @Test("保存する形：日をまたぐ時刻は 0〜24時に戻し、読み直すと同じ位置になる")
    func entryRoundTrip() {
        let e = TimelineMath.entry(inM: 1320, outM: 2040)
        #expect(e.inTime == "22:00" && e.outTime == "10:00")
        let r = ResolvedShift(inTime: e.inTime, outTime: e.outTime, blockID: nil, isOff: false, isAuto: false)
        #expect(TimelineMath.span(of: r)! == (1320, 2040))
        #expect(TimelineMath.entry(inM: 960, outM: 1440).outTime == "00:00")
    }

    @Test("時間帯ごとの人数")
    func headcount() {
        let spans = [(inM: 540, outM: 1080), (inM: 1320, outM: 2040)]
        #expect(TimelineMath.headcount(spans, hour: 9) == 1)
        #expect(TimelineMath.headcount(spans, hour: 18) == 0)
        #expect(TimelineMath.headcount(spans, hour: 25) == 1)
    }
}

@Suite("1マスの編集")
@MainActor
struct EditTests {
    @Test("変える・自動に戻す・元に戻す が保存に反映される")
    func editAndUndo() throws {
        let (book, _) = try BackupFile.read(Data(legacyJSON.utf8))
        let db = ShiftDatabase(inMemory: true)
        let store = ShiftStore(db: db)
        try store.replaceAll(with: book)
        let key = CellKey(staffID: "1", day: DayKey(2026, 10, 5))

        // くり返しで 9:00〜15:00 の日を 10:00〜19:00 に
        try store.setCell(key, to: CellEntry(inTime: "10:00", outTime: "19:00", blockID: nil, isOff: false))
        #expect(store.book.cells[key]?.inTime == "10:00")
        #expect(try ShiftRecords.load(db.viewContext).cells[key]?.outTime == "19:00")
        #expect(store.lastChange?.before == nil)

        // 元に戻す → 手入力が消えて、くり返しに戻る
        try store.undo()
        #expect(store.book.cells[key] == nil)
        #expect(Schedule.resolve(store.book.staff.first { $0.id == "1" }!, on: key.day, in: store.book)?.isAuto == true)
        #expect(try ShiftRecords.load(db.viewContext).cells[key] == nil)

        // 手入力のある日を自動に戻す
        let manual = CellKey(staffID: "1", day: DayKey(2026, 10, 7))
        try store.setCell(manual, to: nil)
        #expect(store.book.cells[manual] == nil)
        try store.undo()
        #expect(store.book.cells[manual]?.outTime == "19:30")
    }

    @Test("同じ内容にしたときは何も変えない")
    func noChange() throws {
        let (book, _) = try BackupFile.read(Data(legacyJSON.utf8))
        let store = ShiftStore(db: ShiftDatabase(inMemory: true))
        try store.replaceAll(with: book)
        let key = CellKey(staffID: "1", day: DayKey(2026, 10, 7))
        try store.setCell(key, to: book.cells[key])
        #expect(store.lastChange == nil)
    }
}

@Suite("一から作る")
@MainActor
struct SetupTests {
    @Test("新しく作ると、部門と休みを含むひな形の例が入る")
    func startNew() throws {
        let store = ShiftStore(db: ShiftDatabase(inMemory: true))
        #expect(store.book.isEmpty)
        try store.startNew()
        #expect(!store.book.isEmpty)
        #expect(store.book.staff.isEmpty)
        #expect(store.book.departments.map(\.name) == ["ホール", "キッチン"])
        #expect(store.book.templates.contains { $0.isOff })
    }

    @Test("スタッフを追加し、週のくり返しを決めるとシフトに出る")
    func addStaffWithPattern() throws {
        let store = ShiftStore(db: ShiftDatabase(inMemory: true))
        try store.startNew()
        let early = try #require(store.book.templates.first { $0.label == "早番" })
        let off = try #require(store.book.templates.first { $0.isOff })
        var m = store.newStaff(in: store.book.departments[0].id)
        m.name = "新人"
        let p = WeekPattern(id: "p", label: "通常", colorIndex: 0,
                            days: [off.id, early.id, early.id, early.id, early.id, early.id, off.id], activeFrom: nil)
        m.patterns = [p]
        m.activePatternID = "p"
        try store.save(m)

        let saved = try #require(store.book.staff.first { $0.name == "新人" })
        #expect(saved.number == 1)
        let monday = try #require(Schedule.resolve(saved, on: DayKey(2026, 10, 5), in: store.book))
        #expect(monday.inTime == "09:00" && monday.outTime == "18:00")
        #expect(Schedule.resolve(saved, on: DayKey(2026, 10, 4), in: store.book)?.isOff == true)
        #expect(store.usageCount(of: early.id) == 5)

        // 名前を変えても1人のまま
        var renamed = saved
        renamed.name = "新人A"
        try store.save(renamed)
        #expect(store.book.staff.map(\.name) == ["新人A"])
    }

    @Test("スタッフのいる部門は消せない。スタッフを消すとその人のシフトも消える")
    func deleting() throws {
        let store = ShiftStore(db: ShiftDatabase(inMemory: true))
        try store.startNew()
        let dept = store.book.departments[0]
        var m = store.newStaff(in: dept.id)
        m.name = "A"
        try store.save(m)
        try store.setCell(CellKey(staffID: m.id, day: DayKey(2026, 10, 1)),
                          to: CellEntry(inTime: "09:00", outTime: "17:00", blockID: nil, isOff: false))
        #expect(throws: SetupError.self) { try store.deleteDepartment(dept) }

        try store.deleteStaff(m)
        #expect(store.book.staff.isEmpty)
        #expect(store.book.cells.isEmpty)
        try store.deleteDepartment(dept)
        #expect(store.book.departments.map(\.name) == ["キッチン"])
    }

    @Test("部門・スタッフの並べ替え")
    func reorder() throws {
        let store = ShiftStore(db: ShiftDatabase(inMemory: true))
        try store.startNew()
        try store.reorderDepartments(store.book.departments.reversed())
        #expect(store.book.departments.map(\.name) == ["キッチン", "ホール"])

        let d = store.book.departments[0].id
        for n in ["A", "B", "C"] {
            var m = store.newStaff(in: d)
            m.name = n
            try store.save(m)
        }
        let ordered = store.book.staff.sorted(by: StaffMember.order)
        try store.reorderStaff([ordered[2], ordered[0], ordered[1]])
        #expect(store.book.staff.sorted(by: StaffMember.order).map(\.name) == ["C", "A", "B"])
    }
}

@Suite("月・週の表示")
struct GridModeTests {
    @Test("週は月曜はじまりの7日（月をまたいでもよい）")
    func weekDays() {
        let w = GridMode.week.days(around: DayKey(2026, 11, 1))   // 日曜
        #expect(w.first == DayKey(2026, 10, 26) && w.last == DayKey(2026, 11, 1))
        #expect(GridMode.week.title(around: DayKey(2026, 11, 1)) == "10/26 〜 11/1")
        #expect(GridMode.week.step(DayKey(2026, 11, 1), by: 1) == DayKey(2026, 11, 8))
    }

    @Test("月は1日〜末日")
    func monthDays() {
        let m = GridMode.month.days(around: DayKey(2026, 2, 14))
        #expect(m.count == 28 && m.first == DayKey(2026, 2, 1))
        #expect(GridMode.month.step(DayKey(2026, 12, 31), by: 1) == DayKey(2027, 1, 1))
    }
}
