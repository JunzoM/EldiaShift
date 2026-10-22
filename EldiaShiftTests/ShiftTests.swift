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
        // 実働：6h → 5.5h（休憩30分）、9.5h → 8.5h（休憩1時間）
        #expect(s.hours == 20 * 5.5 + 8.5)
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

@Suite("日の表示")
struct DayModeTests {
    @Test("日は1日ずつ進む")
    func dayMode() {
        #expect(GridMode.day.days(around: DayKey(2026, 10, 22)) == [DayKey(2026, 10, 22)])
        #expect(GridMode.day.step(DayKey(2026, 10, 31), by: 1) == DayKey(2026, 11, 1))
        #expect(GridMode.day.title(around: DayKey(2026, 10, 22)) == "10月22日（木）")
    }
}

@Suite("時間帯別在籍人数・有休")
struct HeadcountAndLeaveTests {
    @Test("時間帯別の人数（日をまたぐ勤務を含む）")
    func headcount() throws {
        let (book, _) = try BackupFile.read(Data(legacyJSON.utf8))
        let a = book.staff.filter { $0.id == "1" }
        // 10/5（月）：見本A は 9:00〜15:00
        #expect(Headcount.working(a, on: DayKey(2026, 10, 5), hour: 9, in: book) == 1)
        #expect(Headcount.working(a, on: DayKey(2026, 10, 5), hour: 15, in: book) == 0)
        #expect(Headcount.working(a, on: DayKey(2026, 10, 4), hour: 9, in: book) == 0)   // 日曜は休み
    }

    @Test("有休の付与日数（PC版と同じ）")
    func grant() {
        let join = DayKey(2024, 4, 1)
        #expect(PaidLeave.grant(joinDate: join, weeklyDays: 5, weeklyHours: 40, today: DayKey(2024, 9, 30)) == nil)
        let g1 = PaidLeave.grant(joinDate: join, weeklyDays: 5, weeklyHours: 40, today: DayKey(2024, 10, 1))!
        #expect(g1.current == 10 && g1.previous == 0 && g1.since == DayKey(2024, 10, 1))
        let g2 = PaidLeave.grant(joinDate: join, weeklyDays: 5, weeklyHours: 40, today: DayKey(2026, 10, 22))!
        #expect(g2.current == 12 && g2.previous == 11 && g2.total == 23 && g2.since == DayKey(2026, 10, 1))
        let p = PaidLeave.grant(joinDate: join, weeklyDays: 3, weeklyHours: 18, today: DayKey(2026, 10, 22))!
        #expect(p.isProportional && p.current == 6 && p.previous == 6)
    }

    @Test("有休の残り：今期の付与日から表示月の末日までの使用を引く")
    func balance() throws {
        let (book, _) = try BackupFile.read(Data(legacyJSON.utf8))
        let a = book.staff.first { $0.id == "1" }!   // 入社 2024-04-01、週5日×6時間 → 比例付与なし
        let b = PaidLeave.balance(of: a, month: MonthKey(2026, 10), in: book, today: DayKey(2026, 10, 22))!
        // 10/8 に有休を1日使っている（今期の付与日 2026-10-01 以降）
        #expect(b.used == 1 && b.usedThisMonth == 1)
        #expect(b.remaining == b.grant.total - 1)
    }
}

@Suite("スタッフの設定")
@MainActor
struct StaffSettingTests {
    private func store(with names: [String]) throws -> ShiftStore {
        let store = ShiftStore(db: ShiftDatabase(inMemory: true))
        try store.startNew()
        for n in names {
            var m = store.newStaff(in: store.book.departments[0].id)
            m.name = n
            try store.save(m)
        }
        return store
    }

    @Test("削除すると同じ部署の番号が繰り上がる")
    func renumberOnDelete() throws {
        let s = try store(with: ["A", "B", "C"])
        let b = s.book.staff.first { $0.name == "B" }!
        try s.deleteStaff(b)
        #expect(s.book.staff.sorted(by: StaffMember.order).map { "\($0.number)\($0.name)" } == ["1A", "2C"])
    }

    @Test("↑↓で入れ替わる")
    func moveUpDown() throws {
        let s = try store(with: ["A", "B", "C"])
        try s.moveStaff(s.book.staff.first { $0.name == "C" }!, by: -1)
        #expect(s.book.staff.sorted(by: StaffMember.order).map(\.name) == ["A", "C", "B"])
        try s.moveStaff(s.book.staff.first { $0.name == "A" }!, by: -1)   // 先頭はそのまま
        #expect(s.book.staff.sorted(by: StaffMember.order).map(\.name) == ["A", "C", "B"])
    }

    @Test("部署の一括移動：移動先の末尾に並び順を保って付く")
    func bulkMove() throws {
        let s = try store(with: ["A", "B"])
        let kitchen = s.book.departments[1].id
        var k = s.newStaff(in: kitchen)
        k.name = "K"
        try s.save(k)
        try s.moveAllStaff(from: s.book.departments[0].id, to: kitchen)
        let list = s.book.staff.filter { $0.departmentID == kitchen }.sorted(by: StaffMember.order)
        #expect(list.map { "\($0.number)\($0.name)" } == ["1K", "2A", "3B"])
    }

    @Test("個人の時間・複数の週間パターン（適用開始日）・期間限定パターンが保存され、シフトに出る")
    func patterns() throws {
        let s = try store(with: ["A"])
        var m = s.book.staff[0]
        let mine = TimeBlock(id: "mine", label: "A_昼", short: "昼", inMinutes: 600, outMinutes: 960, colorIndex: 6)
        let early = s.book.templates.first { $0.label == "早番" }!
        m.timeBlocks = [mine]
        m.patterns = [
            WeekPattern(id: "p1", label: "通常", colorIndex: 0, days: Array(repeating: early.id, count: 7), activeFrom: nil),
            WeekPattern(id: "p2", label: "新", colorIndex: 1, days: Array(repeating: "mine", count: 7), activeFrom: "2026-11-01")
        ]
        m.activePatternID = "p1"
        m.periodPatterns = [PeriodPattern(id: "pp", label: "年末", colorIndex: 3, startDate: "2026-12-30", endDate: "2026-12-31",
                                          days: ["2026-12-30": "off1"])]
        try s.save(m)
        let saved = s.book.staff[0]
        #expect(saved.timeBlocks == [mine] && saved.patterns.count == 2 && saved.periodPatterns.count == 1)
        #expect(Schedule.resolve(saved, on: DayKey(2026, 10, 31), in: s.book)?.blockID == early.id)
        #expect(Schedule.resolve(saved, on: DayKey(2026, 11, 1), in: s.book)?.blockID == "mine")
        #expect(Schedule.resolve(saved, on: DayKey(2026, 12, 30), in: s.book)?.isOff == true)
        #expect(Schedule.resolve(saved, on: DayKey(2026, 12, 31), in: s.book) == nil)   // 期間内で未設定は空き
    }
}

@Suite("印刷・データ管理")
@MainActor
struct PrintAndDataTests {
    @Test("印刷の枚数（PC版と同じ）")
    func pageCounts() {
        let d = [Department(id: "a", name: "A", colorIndex: 0, sortOrder: 0), Department(id: "b", name: "B", colorIndex: 1, sortOrder: 1)]
        let day = DayKey(2026, 10, 22)
        #expect(PrintPlanner.pages(format: .weekByDepartment, half: .both, departments: d, anchor: day).count == 2)
        #expect(PrintPlanner.pages(format: .monthByDepartment, half: .both, departments: d, anchor: day).count == 4)
        #expect(PrintPlanner.pages(format: .monthByDepartment, half: .first, departments: d, anchor: day).count == 2)
        #expect(PrintPlanner.pages(format: .monthCombined, half: .both, departments: d, anchor: day).count == 2)
        let ls = PrintPlanner.pages(format: .monthLandscape, half: .first, departments: d, anchor: day)
        #expect(ls.count == 1 && ls[0].tables.count == 2 && ls[0].landscape)
        #expect(ls[0].tables[0].days.count == 15 && ls[0].tables[1].days.count == 16)
    }

    @Test("PDF ができる")
    func pdf() throws {
        let (book, _) = try BackupFile.read(Data(legacyJSON.utf8))
        let pages = PrintPlanner.pages(format: .monthByDepartment, half: .both, departments: book.departments, anchor: DayKey(2026, 10, 1))
        let data = PDFMaker.make(pages: pages, book: book, title: "見本")
        #expect(data.starts(with: Data("%PDF".utf8)))
        #expect(data.count > 1000)
    }

    @Test("すべて消去：部署と休みの種類は残り、自動バックアップが残る")
    func reset() throws {
        let (book, _) = try BackupFile.read(Data(legacyJSON.utf8))
        let store = ShiftStore(db: ShiftDatabase(inMemory: true))
        try store.replaceAll(with: book)
        let before = (try? FileManager.default.contentsOfDirectory(atPath: ShiftStore.autoBackupFolder.path))?.count ?? 0
        try store.resetAll()
        #expect(store.book.staff.isEmpty && store.book.cells.isEmpty)
        #expect(store.book.departments.count == book.departments.count)
        #expect(store.book.templates.allSatisfy(\.isOff) && !store.book.templates.isEmpty)
        let after = (try? FileManager.default.contentsOfDirectory(atPath: ShiftStore.autoBackupFolder.path))?.count ?? 0
        #expect(after == min(30, before + 1))
    }
}

@Suite("休憩の決まり")
@MainActor
struct BreakRuleTests {
    @Test("PC版と同じ決まり（以上）と労働基準法（超える）の違い")
    func rules() {
        let pc = BreakRules.pcDefault
        #expect(pc.breakMinutes(forGross: 269) == 0)
        #expect(pc.breakMinutes(forGross: 270) == 30)
        #expect(pc.breakMinutes(forGross: 390) == 60)
        let law = BreakRules.laborStandard
        #expect(law.breakMinutes(forGross: 360) == 0)      // ちょうど6時間は引かない
        #expect(law.breakMinutes(forGross: 361) == 45)
        #expect(law.breakMinutes(forGross: 480) == 45)
        #expect(law.breakMinutes(forGross: 481) == 60)
        #expect(BreakRules.none.netHours(gross: 9) == 9)
        #expect(pc.netHours(gross: 9, override: 120) == 7)
        #expect(pc.summary == "4時間30分以上は30分、6時間30分以上は60分")
        #expect(law.summary == "6時間を超えたら45分、8時間を超えたら60分")
    }

    @Test("決まりを変えると集計が変わり、保存・バックアップにも残る")
    func changeAndPersist() throws {
        let (book, _) = try BackupFile.read(Data(legacyJSON.utf8))
        let db = ShiftDatabase(inMemory: true)
        let store = ShiftStore(db: db)
        try store.replaceAll(with: book)
        let a = store.book.staff.first { $0.id == "1" }!
        #expect(MonthSummary.of(a, month: MonthKey(2026, 10), in: store.book).hours == 20 * 5.5 + 8.5)

        try store.setBreakRules(.none)
        #expect(MonthSummary.of(a, month: MonthKey(2026, 10), in: store.book).hours == 20 * 6 + 9.5)
        #expect(try ShiftRecords.load(db.viewContext).breakRules == .none)

        let (again, _) = try BackupFile.read(try store.exportData())
        #expect(again.breakRules == .none)
        // PC版のファイル（決まりなし）は PC版と同じ決まりになる
        #expect(book.breakRules == .pcDefault)
    }

    @Test("ひな形ごとの休憩：そのひな形のまま入れた日だけ使い、時刻を変えた日は決まりに従う")
    func templateOverride() throws {
        let (book0, _) = try BackupFile.read(Data(legacyJSON.utf8))
        var book = book0
        let i = book.templates.firstIndex { $0.id == "g02" }!   // 夜勤 22:00〜10:00（12時間）
        book.templates[i].breakMinutes = 120
        let store = ShiftStore(db: ShiftDatabase(inMemory: true))
        try store.replaceAll(with: book)
        #expect(store.book.templates.first { $0.id == "g02" }?.breakMinutes == 120)   // 保存される

        let a = store.book.staff.first { $0.id == "1" }!
        let day = DayKey(2026, 10, 20)
        try store.setCell(CellKey(staffID: a.id, day: day), to: CellEntry(inTime: "22:00", outTime: "10:00", blockID: "g02", isOff: false))
        #expect(Schedule.resolve(a, on: day, in: store.book)?.netHours(store.book.breakRules) == 10)
        try store.setCell(CellKey(staffID: a.id, day: day), to: CellEntry(inTime: "22:00", outTime: "09:00", blockID: "g02", isOff: false))
        #expect(Schedule.resolve(a, on: day, in: store.book)?.netHours(store.book.breakRules) == 10)   // 11h − 60分

        let (again, _) = try BackupFile.read(try store.exportData())
        #expect(again.templates.first { $0.id == "g02" }?.breakMinutes == 120)
    }

    @Test("すべて消去しても休憩の決まりは残る")
    func keepOnReset() throws {
        let store = ShiftStore(db: ShiftDatabase(inMemory: true))
        try store.startNew()
        try store.setBreakRules(.laborStandard)
        try store.resetAll()
        #expect(store.book.breakRules == .laborStandard)
    }
}

@Suite("速さの改良・不具合の修正")
@MainActor
struct PerfAndFixTests {
    @Test("まとめて計算した表は、1マスずつ計算したときと同じ結果になる")
    func tableMatches() throws {
        let (book, _) = try legacyBook()
        let days = MonthKey(2026, 10).days
        let table = ScheduleTable(book: book, members: book.staff, days: days)
        for m in book.staff {
            #expect(table.summary(m, days: days) == MonthSummary.of(m, days: days, in: book))
            for d in days { #expect(table.get(m, d) == Schedule.resolve(m, on: d, in: book)) }
        }
        for d in days.prefix(7) {
            for h in 0..<24 {
                #expect(table.working(book.staff, on: d, hour: h) == Headcount.working(book.staff, on: d, hour: h, in: book))
            }
        }
    }

    @Test("チームが2つできても、1つにまとめて記録は消えない")
    func mergeTeams() throws {
        let db = ShiftDatabase(inMemory: true)
        let ctx = db.viewContext
        let a = try ShiftRecords.currentTeam(ctx)
        let b = NSEntityDescription.insertNewObject(forEntityName: ShiftModel.Entity.team, into: ctx)
        b.setValue(UUID(), forKey: "id"); b.setValue("シフト表", forKey: "name")
        b.setValue(Date().addingTimeInterval(60), forKey: "createdAt")
        b.setValue(try JSONEncoder().encode(TeamSettings(breakRules: .laborStandard)), forKey: "settings")
        for (team, staffKey) in [(a, "1"), (b, "2")] {
            let r = NSEntityDescription.insertNewObject(forEntityName: ShiftModel.Entity.cell, into: ctx)
            r.setValue(team, forKey: "team"); r.setValue(staffKey, forKey: "staffKey")
            r.setValue("2026-10-01", forKey: "day"); r.setValue("09:00", forKey: "inTime")
            r.setValue("18:00", forKey: "outTime"); r.setValue(Date(), forKey: "updatedAt")
        }
        try db.save()
        let book = try ShiftRecords.load(ctx)
        try db.save()
        #expect(book.cells.count == 2)
        #expect(book.breakRules == .laborStandard)
        #expect(try ctx.fetch(NSFetchRequest<NSManagedObject>(entityName: ShiftModel.Entity.team)).count == 1)
        #expect(try ShiftRecords.load(ctx).cells.count == 2)
    }

    @Test("スタッフを保存すると、読み直さなくても表に反映され、読み直しても同じ")
    func inPlaceSave() throws {
        let store = ShiftStore(db: ShiftDatabase(inMemory: true))
        try store.startNew()
        var m = store.newStaff(in: store.book.departments[0].id)
        m.name = "見本"
        try store.save(m)
        #expect(store.book.staff.contains { $0.name == "見本" })
        m.name = "見本2"
        try store.save(m)
        #expect(store.book.staff.filter { $0.id == m.id }.map(\.name) == ["見本2"])
        let reloaded = try ShiftRecords.load(store.db.viewContext)
        #expect(reloaded.staff.first { $0.id == m.id }?.name == "見本2")
    }

    @Test("PDF を1枚ずつ作っても同じ枚数になる")
    func asyncPDF() async throws {
        let (book, _) = try legacyBook()
        let pages = PrintPlanner.pages(format: .monthByDepartment, half: .both, departments: book.departments, anchor: DayKey(2026, 10, 1))
        var seen = 0
        let data = await PDFMaker.makeAsync(pages: pages, book: book, title: "t") { seen = $0 }
        #expect(seen == pages.count)
        #expect(!data.isEmpty)
    }
}
