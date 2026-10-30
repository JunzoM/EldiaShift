import Foundation
import Testing
@testable import EldiaShift

@Suite("ホーム：在籍・承認待ち・人件費・月の出勤人数・バックアップのお知らせ")
@MainActor
struct HomeTests {
    private func book() -> ShiftBook {
        var b = ShiftBook()
        b.departments = [Department(id: "a", name: "フロント", colorIndex: 0, sortOrder: 0)]
        b.templates = [TimeBlock(id: "t1", label: "早番", short: "早", inMinutes: 9 * 60, outMinutes: 18 * 60, colorIndex: 0)]
            + BackupFile.defaultOffBlocks
        func member(_ id: String, leave: String = "") -> StaffMember {
            StaffMember(id: id, number: 1, name: "スタッフ\(id)", departmentID: "a", active: true, joinDate: "", leaveDate: leave,
                        timeBlocks: [], patterns: [], activePatternID: nil, periodPatterns: [])
        }
        var m1 = member("1")
        m1.leaveRequests = [LeaveRequest(id: "r1", day: "2026-11-20", note: "", status: .pending, receivedAt: Date(), decidedAt: nil),
                            LeaveRequest(id: "r2", day: "2026-11-21", note: "", status: .approved, receivedAt: Date(), decidedAt: Date())]
        // 3人目は11/5で辞めている
        b.staff = [m1, member("2"), member("3", leave: "2026-11-05")]
        func work(_ id: String, _ day: Int) {
            b.cells[CellKey(staffID: id, day: DayKey(2026, 11, day))] = CellEntry(inTime: "09:00", outTime: "18:00", blockID: "t1", isOff: false)
        }
        work("1", 10); work("2", 10); work("2", 11); work("3", 3)
        b.cells[CellKey(staffID: "1", day: DayKey(2026, 11, 11))] = CellEntry(inTime: "", outTime: "", blockID: "off1", isOff: true)
        b.pay.budgets[LaborBudget.key(store: nil, month: nil)] = 1_000_000
        return b
    }

    @Test("在籍の人数・承認待ち・月予算・人件費")
    func numbers() {
        let b = book()
        let info = HomeInfo(book: b, today: DayKey(2026, 11, 10))
        #expect(info.working.count == 2)
        #expect(info.enrolled == 2)            // 辞めた人は数えない
        #expect(info.pendingRequests == 1)     // 承認済みは数えない
        #expect(info.laborBudget == 1_000_000)
        #expect(info.laborCost == Payroll.total(month: MonthKey(2026, 11), in: b))
        // 辞める前の日は在籍に入る
        #expect(HomeInfo(book: b, today: DayKey(2026, 11, 3)).enrolled == 3)
    }

    @Test("月のカレンダーの出勤人数（休みは数えない）")
    func dayCounts() {
        let info = HomeInfo(book: book(), today: DayKey(2026, 11, 10))
        #expect(info.dayCounts.count == 30)
        #expect(info.dayCounts[DayKey(2026, 11, 10)] == 2)
        #expect(info.dayCounts[DayKey(2026, 11, 11)] == 1)
        #expect(info.dayCounts[DayKey(2026, 11, 3)] == 1)
        #expect(info.dayCounts[DayKey(2026, 11, 12)] == 0)
    }

    @Test("バックアップのお知らせは、まだ作っていないか30日たったら")
    func backupReminder() throws {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let day: Double = 86_400
        #expect(BackupReminder.isDue(last: 0, now: now))
        #expect(!BackupReminder.isDue(last: now.timeIntervalSinceReferenceDate - 10 * day, now: now))
        #expect(BackupReminder.isDue(last: now.timeIntervalSinceReferenceDate - 30 * day, now: now))
        #expect(BackupReminder.days(since: now.timeIntervalSinceReferenceDate - 45.5 * day, now: now) == 45)

        let defaults = try #require(UserDefaults(suiteName: "HomeTests.backup"))
        defaults.removePersistentDomain(forName: "HomeTests.backup")
        BackupReminder.record(now, defaults: defaults)
        #expect(defaults.double(forKey: BackupReminder.key) == now.timeIntervalSinceReferenceDate)
    }
}
