import Foundation
import Testing
@testable import EldiaShift

@Suite("パターンの確認")
struct PatternChecksTests {
    private func period(_ id: String, _ s: String, _ e: String) -> PeriodPattern {
        PeriodPattern(id: id, label: id, colorIndex: 0, startDate: s, endDate: e, days: [:])
    }

    private func book() -> ShiftBook {
        var b = ShiftBook()
        b.templates = [TimeBlock(id: "early", label: "早番", short: "早", inMinutes: 360, outMinutes: 900, colorIndex: 0),
                       TimeBlock(id: "late", label: "遅番", short: "遅", inMinutes: 780, outMinutes: 1320, colorIndex: 1)]
        return b
    }

    private func member(_ block: String?, from: String? = nil) -> StaffMember {
        StaffMember(id: "s1", number: 1, name: "見本", departmentID: "d", active: true, joinDate: "", leaveDate: "",
                    timeBlocks: [], patterns: [WeekPattern(id: "p", label: "通常", colorIndex: 0,
                                                           days: Array(repeating: block, count: 7), activeFrom: from)],
                    activePatternID: "p", periodPatterns: [])
    }

    @Test("期間限定パターンの重なりを見つける")
    func overlap() {
        let a = period("a", "2026-12-28", "2027-01-04")
        let others = [a, period("b", "2027-01-04", "2027-01-10"), period("c", "2027-01-05", "2027-01-10")]
        #expect(PatternChecks.overlapping(a, in: others).map(\.id) == ["b"])
        // 自分自身・日付の無いものは数えない
        #expect(PatternChecks.overlapping(a, in: [a, period("x", "", "")]).isEmpty)
        // 終了日が開始日より前のものは数えない
        #expect(PatternChecks.overlapping(period("d", "2027-01-10", "2027-01-01"), in: others).isEmpty)
    }

    @Test("パターンを変えると、過去と今日以降の変わる日が分かる")
    func previewPastAndFuture() {
        let today = DayKey(2026, 10, 25)
        var b = book()
        b.cells[CellKey(staffID: "s1", day: today)] = CellEntry(inTime: "09:00", outTime: "18:00", blockID: nil, isOff: false)
        let p = PatternChecks.preview(old: member("early"), new: member("late"), book: b, today: today)
        #expect(!p.past.isEmpty)
        #expect(!p.upcoming.isEmpty)
        // 手で入れた日は変わらない
        #expect(!p.upcoming.contains(today))
        #expect(p.message.contains("適用開始日"))
    }

    @Test("適用開始日を入れれば、過去は変わらない")
    func previewFromToday() {
        let today = DayKey(2026, 10, 25)
        var new = member("early")
        new.patterns.append(WeekPattern(id: "q", label: "新", colorIndex: 0, days: Array(repeating: "late", count: 7),
                                        activeFrom: today.description))
        let p = PatternChecks.preview(old: member("early"), new: new, book: book(), today: today)
        #expect(p.past.isEmpty)
        #expect(p.upcoming.first == today)
        #expect(!p.message.contains("過去"))
    }

    @Test("何も変わらなければ確認しない")
    func previewNoChange() {
        var new = member("early")
        new.name = "名前だけ変更"
        #expect(PatternChecks.preview(old: member("early"), new: new, book: book(), today: DayKey(2026, 10, 25)).isEmpty)
    }
}
