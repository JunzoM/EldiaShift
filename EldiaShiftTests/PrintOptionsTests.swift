import Foundation
import PDFKit
import Testing
@testable import EldiaShift

@Suite("印刷：用紙・1か月の表・ページ分け・メモ")
@MainActor
struct PrintOptionsTests {
    private func book(staff n: Int) -> ShiftBook {
        var b = ShiftBook()
        b.departments = [Department(id: "a", name: "フロント", colorIndex: 0, sortOrder: 0)]
        b.staff = (1...n).map { i in
            StaffMember(id: "s\(i)", number: i, name: "スタッフ\(i)", departmentID: "a", active: true, joinDate: "", leaveDate: "",
                        timeBlocks: [], patterns: [], activePatternID: nil, periodPatterns: [])
        }
        return b
    }

    @Test("A3 は A4 を √2 倍にした大きさ。⑤は1か月を1つの横の表")
    func paper() {
        let d = [Department(id: "a", name: "A", colorIndex: 0, sortOrder: 0)]
        let day = DayKey(2026, 10, 22)
        let a4 = PrintPlanner.pages(format: .monthByDepartment, half: .first, departments: d, anchor: day)[0]
        #expect(abs(a4.size.width - 595.28) < 0.01 && abs(a4.size.height - 841.89) < 0.01)
        let a3 = PrintPlanner.pages(format: .monthByDepartment, half: .first, departments: d, anchor: day, paper: .a3)[0]
        #expect(abs(a3.size.width - 841.89) < 0.5 && abs(a3.size.height - 1190.55) < 0.5)
        let single = PrintPlanner.pages(format: .monthSingle, half: .first, departments: d, anchor: day, paper: .a3)
        #expect(single.count == 1 && single[0].landscape && single[0].tables.count == 1)
        #expect(single[0].tables[0].days.count == 31)
        #expect(single[0].size.width > single[0].size.height)
    }

    @Test("人数が少なければ1枚のまま、多ければ全員を一度ずつ載せて何枚かに分ける")
    func paginate() {
        let small = book(staff: 10)
        let d = small.departments
        let day = DayKey(2026, 10, 1)
        let one = PrintPlanner.pages(format: .monthByDepartment, half: .first, departments: d, anchor: day)
        #expect(PrintPlanner.paginate(one, book: small, options: PrintOptions()).count == 1)

        let big = book(staff: 80)
        let pages = PrintPlanner.paginate(one, book: big, options: PrintOptions())
        #expect(pages.count == 2)
        #expect(pages[0].label.hasSuffix("（1/2）") && pages[1].label.hasSuffix("（2/2）"))
        let keys = pages.compactMap(\.memberKeys)
        #expect(keys.reduce(0) { $0 + $1.count } == 80)
        #expect(keys[0].isDisjoint(with: keys[1]))
        // どの枚も行の高さが小さくなりすぎない
        for p in pages {
            let groups = PrintPlanner.groups(for: p, book: big)
            #expect(CGFloat(PrintLayout.rowCount(groups)) * PrintLayout.minRowHeight <= PrintLayout.rowsHeight(p, notes: false))
        }
        // ④（前半・後半を1枚に）は表が2つなので、少ない人数で分ける
        let ls = PrintPlanner.pages(format: .monthLandscape, half: .both, departments: d, anchor: day)
        #expect(PrintPlanner.paginate(ls, book: book(staff: 30), options: PrintOptions()).count == 2)
        // A3 は割り付けが A4 と同じなので、枚数も同じ
        let a3 = PrintPlanner.pages(format: .monthByDepartment, half: .first, departments: d, anchor: day, paper: .a3)
        #expect(PrintPlanner.paginate(a3, book: big, options: PrintOptions()).count == 2)
    }

    @Test("マスのメモは、その枚の日のものだけ。名前を出さないときは番号")
    func notes() {
        var b = book(staff: 2)
        b.cells[CellKey(staffID: "s1", day: DayKey(2026, 10, 3))] = CellEntry(inTime: "09:00", outTime: "18:00", blockID: nil, isOff: false, note: "鍵当番")
        b.cells[CellKey(staffID: "s2", day: DayKey(2026, 10, 20))] = CellEntry(inTime: "09:00", outTime: "18:00", blockID: nil, isOff: false, note: "研修")
        let first = PrintPlanner.pages(format: .monthByDepartment, half: .first, departments: b.departments, anchor: DayKey(2026, 10, 1))[0]
        let groups = PrintPlanner.groups(for: first, book: b)
        let named = PrintPlanner.notes(for: first, groups: groups, book: b, showNames: true)
        #expect(named == [PrintNote(day: DayKey(2026, 10, 3), who: "スタッフ1", text: "鍵当番")])
        #expect(PrintPlanner.notes(for: first, groups: groups, book: b, showNames: false).first?.who == "No.1")
        let month = PrintPlanner.pages(format: .monthSingle, half: .both, departments: b.departments, anchor: DayKey(2026, 10, 1))[0]
        #expect(PrintPlanner.notes(for: month, groups: PrintPlanner.groups(for: month, book: b), book: b, showNames: true).count == 2)
    }

    @Test("A3・名前なし・時刻なし・メモありでも PDF ができ、ページの大きさと枚数が合う")
    func pdf() throws {
        var b = book(staff: 80)
        b.cells[CellKey(staffID: "s1", day: DayKey(2026, 10, 3))] = CellEntry(inTime: "09:00", outTime: "18:00", blockID: nil, isOff: false, note: "鍵当番")
        let options = PrintOptions(paper: .a3, showNames: false, showTimes: false, showNotes: true)
        let pages = PrintPlanner.paginate(PrintPlanner.pages(format: .monthByDepartment, half: .first, departments: b.departments,
                                                             anchor: DayKey(2026, 10, 1), paper: .a3), book: b, options: options)
        let data = PDFMaker.make(pages: pages, book: b, title: "見本", options: options)
        let doc = try #require(PDFDocument(data: data))
        #expect(doc.pageCount == pages.count)
        let box = try #require(doc.page(at: 0)).bounds(for: .mediaBox)
        #expect(abs(box.width - 841.89) < 1 && abs(box.height - 1190.55) < 1)
    }
}
