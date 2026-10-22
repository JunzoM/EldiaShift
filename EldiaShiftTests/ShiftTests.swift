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

@Suite("適正人員")
@MainActor
struct StaffingTests {
    private func band(_ s: Int, _ e: Int, _ wd: Int, _ sa: Int, _ ho: Int) -> StaffingBand {
        StaffingBand(departmentID: "d", startHour: s, endHour: e, weekday: wd, saturday: sa, holiday: ho)
    }

    @Test("日の型：カレンダーどおり（日曜・祝日は日祝）と、日ごとの切り替え")
    func dayTypes() {
        var p = StaffingPlan()
        #expect(p.type(of: DayKey(2026, 10, 5)) == .weekday)
        #expect(p.type(of: DayKey(2026, 10, 10)) == .saturday)
        #expect(p.type(of: DayKey(2026, 10, 11)) == .holiday)
        #expect(p.type(of: DayKey(2026, 10, 12)) == .holiday)   // スポーツの日
        p.setType(.busy, for: DayKey(2026, 10, 5))
        #expect(p.type(of: DayKey(2026, 10, 5)) == .busy)
        p.setType(.weekday, for: DayKey(2026, 10, 5))           // カレンダーどおりに戻すと記録は消える
        #expect(p.dayTypes.isEmpty)
    }

    @Test("時間帯：日をまたぐ・重なりは多いほう・繁忙と閑散の自動")
    func needs() {
        var p = StaffingPlan()
        p.bands = [band(9, 18, 2, 3, 4), band(12, 14, 3, 3, 3), band(22, 6, 1, 1, 1)]
        let mon = DayKey(2026, 10, 5)
        #expect(p.need("d", on: mon, hour: 8) == nil)
        #expect(p.need("d", on: mon, hour: 9) == 2)
        #expect(p.need("d", on: mon, hour: 12) == 3)
        #expect(p.need("d", on: mon, hour: 18) == nil)
        #expect(p.need("d", on: mon, hour: 23) == 1)
        #expect(p.need("d", on: mon, hour: 5) == 1)
        #expect(p.need("d", on: DayKey(2026, 10, 10), hour: 10) == 3)
        #expect(p.bands[0].need(.busy) == 5)
        #expect(p.bands[0].need(.quiet) == 1)
        #expect(p.need("other", on: mon, hour: 10) == nil)
    }

    @Test("不足と過剰を人×時間で数える")
    func gap() {
        var p = StaffingPlan()
        p.bands = [band(9, 12, 2, 2, 2)]
        // 9時台1人・10時台2人・11時台3人
        let g = StaffingCheck.gap(p, department: "d", members: [], on: DayKey(2026, 10, 5)) { _, _, h in h - 8 }
        #expect(g == StaffingGap(short: 1, over: 1, shortHours: 1))
    }

    @Test("実績から提案：同じ人数が続く時間をまとめる")
    func suggest() {
        var wd = Array(repeating: 0, count: 24)
        for h in 9..<12 { wd[h] = 2 }
        for h in 12..<15 { wd[h] = 3 }
        let bands = StaffingCheck.suggestBands(department: "d", averages: [.weekday: wd])
        #expect(bands.map { [$0.startHour, $0.endHour, $0.weekday, $0.saturday] } == [[9, 12, 2, 2], [12, 15, 3, 3]])
    }

    @Test("保存して読み直す・バックアップに入る")
    func persist() throws {
        let store = ShiftStore(db: ShiftDatabase(inMemory: true))
        try store.startNew()
        var p = StaffingPlan()
        p.bands = [band(9, 18, 2, 3, 4)]
        p.setType(.busy, for: DayKey(2026, 10, 5))
        try store.setStaffing(p)
        #expect(try ShiftRecords.load(store.db.viewContext).staffing == p)
        let (book, _) = try BackupFile.read(try store.exportData())
        #expect(book.staffing == p)
    }
}

// MARK: - 候補・労務の注意・公開・希望休・元に戻す

private func miniBook() -> ShiftBook {
    var b = ShiftBook()
    b.departments = [Department(id: "d", name: "フロント", colorIndex: 0, sortOrder: 0)]
    b.templates = [
        TimeBlock(id: "e", label: "早番", short: "早", inMinutes: 9 * 60, outMinutes: 18 * 60, colorIndex: 2),
        TimeBlock(id: "n", label: "夜勤", short: "夜", inMinutes: 21 * 60, outMinutes: 9 * 60, colorIndex: 8)
    ] + BackupFile.defaultOffBlocks
    b.staff = (1...3).map { i in
        StaffMember(id: "\(i)", number: i, name: "S\(i)", departmentID: "d", active: true, joinDate: "", leaveDate: "",
                    timeBlocks: [], patterns: [], activePatternID: nil, periodPatterns: [])
    }
    return b
}

private func put(_ b: inout ShiftBook, _ id: String, _ d: DayKey, _ block: String) {
    let t = b.templates.first { $0.id == block }!
    b.cells[CellKey(staffID: id, day: d)] = t.isOff
        ? CellEntry(inTime: "", outTime: "", blockID: t.id, isOff: true)
        : CellEntry(inTime: t.inTime, outTime: t.outTime, blockID: t.id, isOff: false)
}

@Suite("労務の注意")
struct LaborTests {
    @Test("6連勤と週40時間超え（10/5 月〜10/10 土、9:00〜18:00＝実働8時間）")
    func consecutiveAndWeekly() {
        var b = miniBook()
        let days = (5...10).map { DayKey(2026, 10, $0) }
        for d in days { put(&b, "1", d, "e") }
        let issues = LaborCheck.issues(b, members: b.staff, days: MonthKey(2026, 10).days)
        let last = issues[CellKey(staffID: "1", day: DayKey(2026, 10, 10))] ?? []
        #expect(last.contains(.consecutive(6)))
        #expect(last.contains(.weekly(hours: 48)))
        #expect(issues[CellKey(staffID: "1", day: DayKey(2026, 10, 9))]?.contains(.consecutive(5)) != true)
        // 週40時間を超えるのは6日目から
        #expect(issues[CellKey(staffID: "1", day: DayKey(2026, 10, 9))] == nil)
    }

    @Test("夜勤明けの日の早番は間隔の注意、希望休の日の勤務も注意")
    func intervalAndRequest() {
        var b = miniBook()
        put(&b, "2", DayKey(2026, 10, 5), "n")
        put(&b, "2", DayKey(2026, 10, 6), "e")
        b.staff[2].offRequests = ["2026-10-07"]
        put(&b, "3", DayKey(2026, 10, 7), "e")
        let issues = LaborCheck.issues(b, members: b.staff, days: MonthKey(2026, 10).days)
        #expect(issues[CellKey(staffID: "2", day: DayKey(2026, 10, 6))] == [.interval(minutes: 0)])
        #expect(issues[CellKey(staffID: "3", day: DayKey(2026, 10, 7))] == [.requestedOff])
        // 切ると出ない
        b.labor.intervalEnabled = false
        #expect(LaborCheck.issues(b, members: b.staff, days: [DayKey(2026, 10, 6)]).isEmpty)
    }

    @Test("有休の年5日：付与日から1年のうちに入れた有休を数える")
    func leaveObligation() {
        var b = miniBook()
        b.staff[0].joinDate = "2025-04-01"            // 18か月で11日付与（2026-10-01）
        put(&b, "1", DayKey(2026, 10, 15), "off2")
        put(&b, "1", DayKey(2026, 11, 2), "off2")
        put(&b, "1", DayKey(2026, 9, 30), "off2")      // 付与日より前は数えない
        let o = LaborCheck.leaveObligation(of: b.staff[0], in: b, today: DayKey(2026, 10, 20))
        #expect(o?.since == DayKey(2026, 10, 1))
        #expect(o?.deadline == DayKey(2027, 9, 30))
        #expect(o?.taken == 2)
        #expect(o?.needed == 3)
        // 入社6か月（10日付与）でも対象、6か月未満は対象外
        b.staff[1].joinDate = "2026-06-01"
        #expect(LaborCheck.leaveObligation(of: b.staff[1], in: b, today: DayKey(2026, 10, 20)) == nil)
    }
}

@Suite("足りない時間に入れられる人")
struct CandidateTests {
    @Test("勤務が無い人を出し、希望休の人は出さない。足りない時間を埋めるひな形を選ぶ")
    func candidates() {
        var b = miniBook()
        b.staffing.bands = [StaffingBand(departmentID: "d", startHour: 9, endHour: 18, weekday: 2, saturday: 2, holiday: 2)]
        let mon = DayKey(2026, 10, 5)
        put(&b, "1", mon, "e")
        b.staff[2].offRequests = [mon.description]
        #expect(ShortageFinder.shortHours(b, department: "d", members: b.staff, on: mon) == Array(9..<18))
        let list = ShortageFinder.candidates(b, department: "d", on: mon, includeOthers: false)
        #expect(list.map(\.member.id) == ["2"])
        #expect(list.first?.block.id == "e")
        #expect(list.first?.covers == 9)
        // 有休の人も出さない
        put(&b, "2", mon, "off2")
        #expect(ShortageFinder.candidates(b, department: "d", on: mon, includeOthers: false).isEmpty)
    }
}

@Suite("公開と変更点")
struct PublishTests {
    @Test("前回の公開からの変更を日付順に出し、文章にする")
    func diff() {
        var b = miniBook()
        let oct = MonthKey(2026, 10)
        put(&b, "1", DayKey(2026, 10, 5), "e")
        #expect(PublishDiff.changes(b, month: oct) == nil)
        b.published = [PublishedMonth.snapshot(of: b, month: oct)]
        #expect(PublishDiff.changes(b, month: oct)?.changes.isEmpty == true)

        put(&b, "1", DayKey(2026, 10, 5), "off1")
        put(&b, "2", DayKey(2026, 10, 3), "e")
        let c = PublishDiff.changes(b, month: oct)!.changes
        #expect(c.map(\.day) == [DayKey(2026, 10, 3), DayKey(2026, 10, 5)])
        #expect(c[1].before == "早番 09:00〜18:00")
        #expect(c[1].after == "公休")
        #expect(c[0].before == "")
        let text = PublishDiff.text(c, month: oct, title: "")
        #expect(text.contains("■10/5（月）"))
        #expect(text.contains("・S1：早番 09:00〜18:00 → 公休"))
        #expect(text.contains("・S2：なし → 早番 09:00〜18:00"))
    }
}

@Suite("希望休の文章を読む")
struct OffRequestParseTests {
    let oct = MonthKey(2026, 10)

    @Test("日付・月日・範囲")
    func basics() {
        #expect(OffRequestParser.parse("10/5、12日、20〜22日 休み希望", month: oct)
                == [5, 12, 20, 21, 22].map { DayKey(2026, 10, $0) })
        #expect(OffRequestParser.parse("11月3日と4日", month: oct) == [DayKey(2026, 11, 3), DayKey(2026, 11, 4)])
        #expect(OffRequestParser.parse("２５日でお願いします", month: oct) == [DayKey(2026, 10, 25)])
        #expect(OffRequestParser.parse("2026/10/8 から 10/9", month: oct) == [DayKey(2026, 10, 8), DayKey(2026, 10, 9)])
    }

    @Test("時刻は日付にしない・年をまたぐ・ない日は飛ばす")
    func edges() {
        #expect(OffRequestParser.parse("9:00から出られます", month: oct).isEmpty)
        #expect(OffRequestParser.parse("1/5", month: MonthKey(2026, 12)) == [DayKey(2027, 1, 5)])
        #expect(OffRequestParser.parse("11/31", month: oct).isEmpty)
    }
}

@Suite("元に戻す（何段階でも）")
@MainActor
struct UndoHistoryTests {
    @Test("まとめて入れた操作は1回で戻り、やり直せる。新しく変えるとやり直しは消える")
    func history() throws {
        let store = ShiftStore(db: ShiftDatabase(inMemory: true))
        try store.replaceAll(with: miniBook())
        let e = CellEntry(inTime: "09:00", outTime: "18:00", blockID: "e", isOff: false)
        let keys = (5...7).map { CellKey(staffID: "1", day: DayKey(2026, 10, $0)) }
        try store.setCells(keys.map { ($0, e) }, title: "3マス")
        try store.setCell(CellKey(staffID: "2", day: DayKey(2026, 10, 5)), to: e)
        #expect(store.undoStack.count == 2)

        try store.undo()
        #expect(store.book.cells[CellKey(staffID: "2", day: DayKey(2026, 10, 5))] == nil)
        #expect(store.book.cells.count == 3)
        try store.undo()
        #expect(store.book.cells.isEmpty)
        #expect(try ShiftRecords.load(store.db.viewContext).cells.isEmpty)
        #expect(!store.canUndo)

        try store.redo()
        #expect(store.book.cells.count == 3)
        #expect(store.canRedo)
        try store.setCell(CellKey(staffID: "3", day: DayKey(2026, 10, 9)), to: e)
        #expect(!store.canRedo)
    }

    @Test("希望休と労務の決まりは保存され、バックアップにも入る")
    func requestsPersist() throws {
        let store = ShiftStore(db: ShiftDatabase(inMemory: true))
        try store.replaceAll(with: miniBook())
        try store.setOffRequests([DayKey(2026, 10, 9), DayKey(2026, 10, 2)], for: "1")
        var rules = LaborRules()
        rules.consecutiveDays = 5
        try store.setLaborRules(rules)
        let loaded = try ShiftRecords.load(store.db.viewContext)
        #expect(loaded.staff.first { $0.id == "1" }?.offRequests == ["2026-10-02", "2026-10-09"])
        #expect(loaded.labor.consecutiveDays == 5)
        let (b, _) = try BackupFile.read(try store.exportData())
        #expect(b.staff.first { $0.id == "1" }?.offRequests == ["2026-10-02", "2026-10-09"])
        #expect(b.labor.consecutiveDays == 5)
    }

    @Test("公開済みにすると変更点が空になる")
    func publish() throws {
        let store = ShiftStore(db: ShiftDatabase(inMemory: true))
        var b = miniBook()
        put(&b, "1", DayKey(2026, 10, 5), "e")
        try store.replaceAll(with: b)
        try store.markPublished(MonthKey(2026, 10))
        #expect(PublishDiff.changes(store.book, month: MonthKey(2026, 10))?.changes.isEmpty == true)
        #expect(try ShiftRecords.load(store.db.viewContext).published.count == 1)
    }
}

@Suite("複数店舗・掛け持ち・会社の色")
@MainActor
struct MultiStoreTests {
    static let day = DayKey(2026, 11, 2)   // 月曜

    /// 本店（メイク：佐藤）・大阪店（メイク：鈴木。本店にも掛け持ち）。鈴木は毎日 9:00〜18:00 のパターン
    static func book() -> ShiftBook {
        var b = ShiftBook()
        b.stores = [Store(id: "kobe", name: "神戸本店", colorIndex: 0, sortOrder: 0),
                    Store(id: "osaka", name: "大阪店", colorIndex: 4, sortOrder: 1)]
        b.departments = [Department(id: "k-make", name: "メイク", colorIndex: 7, sortOrder: 0, storeID: "kobe"),
                         Department(id: "o-make", name: "メイク", colorIndex: 7, sortOrder: 1, storeID: "osaka"),
                         Department(id: "o-front", name: "フロント", colorIndex: 0, sortOrder: 2, storeID: "osaka")]
        b.templates = [TimeBlock(id: "t1", label: "日勤", short: "日", inMinutes: 9 * 60, outMinutes: 18 * 60, colorIndex: 0)]
            + BackupFile.defaultOffBlocks
        let every: [String?] = Array(repeating: "t1", count: 7)
        func member(_ id: String, _ name: String, _ dept: String, extra: [String] = []) -> StaffMember {
            StaffMember(id: id, number: 1, name: name, departmentID: dept, active: true, joinDate: "", leaveDate: "",
                        timeBlocks: [], patterns: [WeekPattern(id: "p\(id)", label: "通常", colorIndex: 0, days: every, activeFrom: nil)],
                        activePatternID: "p\(id)", periodPatterns: [], extraStoreIDs: extra)
        }
        b.staff = [member("1", "佐藤", "k-make"), member("2", "鈴木", "o-make", extra: ["kobe"]), member("3", "高橋", "o-front")]
        return b
    }

    @Test("店舗を作っていない前の版のデータは「本店」1つとして、今までどおり出る")
    func legacyIsOneStore() {
        var b = Self.book()
        b.stores = []
        b.departments = b.departments.map { var d = $0; d.storeID = ""; return d }
        b.scopeStoreID = Store.defaultID
        #expect(b.allStores.map(\.id) == [Store.defaultID])
        #expect(b.staffByDepartment(visibleIn: MonthKey(Self.day)).flatMap(\.members).map(\.name) == ["佐藤", "鈴木", "高橋"])
    }

    @Test("店舗ごとに部門を絞り、掛け持ちの人は同じ名前の部門の後ろに出る")
    func scopedGroups() {
        var b = Self.book()
        b.scopeStoreID = "kobe"
        let kobe = b.staffByDepartment(visibleIn: MonthKey(Self.day))
        #expect(kobe.map(\.department.id) == ["k-make"])
        #expect(kobe[0].members.map(\.name) == ["佐藤", "鈴木"])
        b.scopeStoreID = "osaka"
        #expect(b.staffByDepartment(visibleIn: MonthKey(Self.day)).flatMap(\.members).map(\.name) == ["鈴木", "高橋"])
        #expect(b.storeIDs(of: b.staff[1]) == ["kobe", "osaka"])
    }

    @Test("ほかの店舗で勤務する日は、その店舗の人数に数えない")
    func elsewhereNotCounted() {
        var b = Self.book()
        let suzuki = b.staff[1]
        b.scopeStoreID = "kobe"
        // パターンの勤務は自分の店舗（大阪）
        #expect(Schedule.resolve(suzuki, on: Self.day, in: b)?.elsewhere == true)
        #expect(Headcount.working(b.staff, on: Self.day, hour: 10, in: b) == 1)   // 佐藤だけ
        b.scopeStoreID = "osaka"
        #expect(Schedule.resolve(suzuki, on: Self.day, in: b)?.elsewhere == false)
        // 本店に入れた日は、大阪では数えず、本店で数える
        b.cells[CellKey(staffID: "2", day: Self.day)] = CellEntry(inTime: "09:00", outTime: "18:00", blockID: "t1", isOff: false, storeID: "kobe")
        #expect(Headcount.working([b.staff[1], b.staff[2]], on: Self.day, hour: 10, in: b) == 1)
        b.scopeStoreID = "kobe"
        #expect(Headcount.working(b.staff, on: Self.day, hour: 10, in: b) == 2)
    }

    @Test("見ている店舗で入れた勤務はその店舗になり、自分の店舗なら空になる。保存・読み直しでも同じ")
    func stampAndPersist() throws {
        let store = ShiftStore(db: ShiftDatabase(inMemory: true))
        try store.replaceAll(with: Self.book())
        store.currentStoreID = "kobe"
        let k2 = CellKey(staffID: "2", day: Self.day)
        try store.setCell(k2, to: CellEntry(inTime: "10:00", outTime: "19:00", blockID: nil, isOff: false))
        #expect(store.book.cells[k2]?.storeID == "kobe")
        let k1 = CellKey(staffID: "1", day: Self.day)
        try store.setCell(k1, to: CellEntry(inTime: "10:00", outTime: "19:00", blockID: nil, isOff: false))
        #expect(store.book.cells[k1]?.storeID == nil)
        // 掛け持ちしていない店舗には入らない（自分の店舗になる）
        store.currentStoreID = "osaka"
        let k3 = CellKey(staffID: "1", day: Self.day.adding(days: 1))
        try store.setCell(k3, to: CellEntry(inTime: "10:00", outTime: "19:00", blockID: nil, isOff: false))
        #expect(store.book.cells[k3]?.storeID == nil)
        // 休みは店舗を持たない
        try store.setCell(k2, to: CellEntry(inTime: "", outTime: "", blockID: "off1", isOff: true, storeID: "kobe"))
        #expect(store.book.cells[k2]?.storeID == nil)
        try store.undo()
        #expect(store.book.cells[k2]?.storeID == "kobe")

        try store.setBrandColor(0x1E3A8A)
        let loaded = try ShiftRecords.load(store.db.viewContext)
        #expect(loaded.stores.map(\.id) == ["kobe", "osaka"])
        #expect(loaded.departments.first { $0.id == "o-make" }?.storeID == "osaka")
        #expect(loaded.staff.first { $0.id == "2" }?.extraStoreIDs == ["kobe"])
        #expect(loaded.cells[k2]?.storeID == "kobe")
        #expect(loaded.brandColor == 0x1E3A8A)
    }

    @Test("バックアップに店舗・掛け持ち・会社の色が入り、読み戻せる")
    func backupRoundTrip() throws {
        var b = Self.book()
        b.brandColor = 0x0F766E
        b.cells[CellKey(staffID: "2", day: Self.day)] = CellEntry(inTime: "09:00", outTime: "18:00", blockID: "t1", isOff: false, storeID: "kobe")
        let (back, _) = try BackupFile.read(try BackupFile.write(b))
        #expect(back.stores == b.stores)
        #expect(back.departments.first { $0.id == "o-front" }?.storeID == "osaka")
        #expect(back.staff.first { $0.id == "2" }?.extraStoreIDs == ["kobe"])
        #expect(back.cells[CellKey(staffID: "2", day: Self.day)]?.storeID == "kobe")
        #expect(back.brandColor == 0x0F766E)
    }

    @Test("部門がある店舗・最後の店舗は消せない。消すと掛け持ち先からも外れる")
    func deleteStore() throws {
        let store = ShiftStore(db: ShiftDatabase(inMemory: true))
        try store.replaceAll(with: Self.book())
        #expect(throws: StoreError.self) { try store.deleteStore(store.book.store("osaka")!) }
        let extra = Store(id: "kyoto", name: "京都店", sortOrder: 2)
        try store.save(extra)
        var m = store.book.staff.first { $0.id == "1" }!
        m.extraStoreIDs = ["kyoto"]
        try store.save(m)
        try store.deleteStore(extra)
        #expect(store.book.allStores.map(\.id) == ["kobe", "osaka"])
        #expect(store.book.staff.first { $0.id == "1" }?.extraStoreIDs == [])
        // 消した店舗を見ていたら、最初の店舗に戻る
        store.currentStoreID = "kyoto"
        #expect(store.currentStoreID == "kobe")
    }

    @Test("公開の記録は店舗ごとに分かれる（最初の店舗は前の版と同じ書き方）")
    func publishPerStore() throws {
        let store = ShiftStore(db: ShiftDatabase(inMemory: true))
        try store.replaceAll(with: Self.book())
        let month = MonthKey(Self.day)
        store.currentStoreID = "kobe"
        try store.markPublished(month)
        store.currentStoreID = "osaka"
        try store.markPublished(month)
        #expect(Set(store.book.published.map(\.month)) == ["2026-11", "2026-11@osaka"])
        #expect(PublishDiff.changes(store.book, month: month)?.changes.isEmpty == true)
    }

    @Test("店舗の略称：決めていなければ、店舗名の共通の頭を除いて見分けられる名前にする")
    func storeShortName() {
        var b = ShiftBook()
        b.stores = [Store(id: "a", name: "ELDIA神戸 LUXURY"), Store(id: "b", name: "ELDIA神戸 MODERN", sortOrder: 1),
                    Store(id: "c", name: "大阪", short: "大", sortOrder: 2)]
        #expect(b.shortName(of: b.stores[2]) == "大")
        b.stores.removeLast()
        #expect(b.shortName(of: b.stores[0]) == "LU")
        #expect(b.shortName(of: b.stores[1]) == "MO")
        b.stores = [Store(id: "a", name: "本館"), Store(id: "b", name: "本館別棟", sortOrder: 1)]
        #expect(b.shortName(of: b.stores[0]) == "本館")
        #expect(b.shortName(of: b.stores[1]) == "別棟")
    }

    @Test("会社の色：明るすぎる色は白い文字が読みにくいと分かる")
    func brandContrast() {
        #expect(BrandColor.contrastWithWhite(0x1E3A8A) > 4.5)
        #expect(BrandColor.contrastWithWhite(0xFDE68A) < 3)
    }
}

@Suite("アプリの表示名")
struct BrandPrefixTests {
    @Test("「〇〇 SHIFT」の〇〇は店舗ごと。空なら HOTEL、前の版の記録も読める")
    func prefix() throws {
        var a = Store(id: "a", name: "本館")
        #expect(a.displayPrefix == "HOTEL")
        a.brandPrefix = "  ELDIA "
        #expect(a.displayPrefix == "ELDIA")
        let old = try JSONDecoder().decode(Store.self, from: Data(#"{"id":"x","name":"旧"}"#.utf8))
        #expect(old.brandPrefix == "" && old.displayPrefix == "HOTEL")
        let back = try JSONDecoder().decode(Store.self, from: JSONEncoder().encode(a))
        #expect(back.brandPrefix == "  ELDIA ")
    }
}
