import Foundation
import Testing
@testable import EldiaShift

@Suite("人件費の概算")
struct PayrollTests {
    private let nov = MonthKey(2026, 11)

    private func book(_ m: StaffMember) -> ShiftBook {
        var b = ShiftBook()
        b.breakRules = .none          // 休憩を引かない（拘束時間＝実働）にして、数字を読みやすく
        b.staff = [m]
        return b
    }

    private func member(_ wages: [WageEntry], join: String = "") -> StaffMember {
        var m = StaffMember(id: "s1", number: 1, name: "見本", departmentID: "d", active: true, joinDate: join, leaveDate: "",
                            timeBlocks: [], patterns: [], activePatternID: nil, periodPatterns: [])
        m.wages = wages
        return m
    }

    private func hourly(_ amount: Int, from: String = "2026-01-01", id: String = "w") -> WageEntry {
        WageEntry(id: id, from: from, kind: .hourly, amount: amount)
    }

    private func work(_ b: inout ShiftBook, _ day: DayKey, _ start: String, _ end: String) {
        b.cells[CellKey(staffID: "s1", day: day)] = CellEntry(inTime: start, outTime: end, blockID: nil, isOff: false)
    }

    @Test("その日に使う給与は、その日までに始まったいちばん新しいもの")
    func wageOnDay() {
        let m = member([hourly(1000, from: "2026-04-01", id: "a"), hourly(1200, from: "2026-11-15", id: "b")])
        #expect(m.wage(on: DayKey(2026, 3, 31)) == nil)
        #expect(m.wage(on: DayKey(2026, 11, 14))?.amount == 1000)
        #expect(m.wage(on: DayKey(2026, 11, 15))?.amount == 1200)
    }

    @Test("時給：実働×時給、1日8時間を超えた分に25%")
    func hourlyDaily() {
        var b = book(member([hourly(1000)]))
        work(&b, DayKey(2026, 11, 10), "09:00", "17:00")   // 8時間
        work(&b, DayKey(2026, 11, 11), "09:00", "20:00")   // 11時間 → 時間外3時間
        let p = Payroll.pay(of: b.staff[0], month: nov, in: b, rules: PayRules())
        #expect(p.workDays == 2)
        #expect(p.netMinutes == 19 * 60)
        #expect(p.overtimeMinutes == 3 * 60)
        #expect(p.total == 19_000 + 750)
    }

    @Test("深夜（22時〜5時）に25%。日をまたぐ勤務も数える")
    func night() {
        #expect(Payroll.nightMinutes(start: 22 * 60, end: 31 * 60) == 7 * 60)   // 22:00〜翌7:00
        #expect(Payroll.nightMinutes(start: 3 * 60, end: 9 * 60) == 2 * 60)     // 3:00〜9:00
        #expect(Payroll.nightMinutes(start: 9 * 60, end: 18 * 60) == 0)
        var b = book(member([hourly(1000)]))
        work(&b, DayKey(2026, 11, 10), "23:00", "07:00")   // 8時間・うち深夜6時間
        let p = Payroll.pay(of: b.staff[0], month: nov, in: b, rules: PayRules())
        #expect(p.nightMinutes == 6 * 60)
        #expect(p.total == 8000 + 1500)
    }

    @Test("週40時間を超えた分に25%（1日の時間外は二重に数えない）")
    func weekly() {
        var b = book(member([hourly(1000)]))
        for d in 2...7 { work(&b, DayKey(2026, 11, d), "09:00", "17:00") }    // 月〜土 8時間×6日
        work(&b, DayKey(2026, 11, 8), "09:00", "19:00")                     // 日 10時間（1日2時間＋週8時間）
        let p = Payroll.pay(of: b.staff[0], month: nov, in: b, rules: PayRules())
        #expect(p.overtimeMinutes == (8 + 2 + 8) * 60)
        // 週を切ると、1日の超過だけ
        var rules = PayRules()
        rules.weeklyEnabled = false
        #expect(Payroll.pay(of: b.staff[0], month: nov, in: b, rules: rules).overtimeMinutes == 2 * 60)
    }

    @Test("月をまたぐ週は、前の月の日も合わせて数え、その月の日の分だけ入れる")
    func weekAcrossMonths() {
        var b = book(member([hourly(1000)]))
        for d in 26...31 { work(&b, DayKey(2026, 10, d), "09:00", "17:00") }   // 10/26(月)〜10/31(土) 48時間
        work(&b, DayKey(2026, 11, 1), "09:00", "17:00")                      // 11/1(日)
        let p = Payroll.pay(of: b.staff[0], month: nov, in: b, rules: PayRules())
        #expect(p.workDays == 1)
        #expect(p.overtimeMinutes == 8 * 60)   // 11/1 はまるごと週40時間の超過
        let oct = Payroll.pay(of: b.staff[0], month: MonthKey(2026, 10), in: b, rules: PayRules())
        #expect(oct.overtimeMinutes == 8 * 60) // 10/31（6日目）
    }

    @Test("月の途中で時給が変わると、その日から新しい時給")
    func wageChange() {
        var b = book(member([hourly(1000, from: "2026-01-01", id: "a"), hourly(1200, from: "2026-11-15", id: "b")]))
        work(&b, DayKey(2026, 11, 14), "09:00", "17:00")
        work(&b, DayKey(2026, 11, 16), "09:00", "17:00")
        #expect(Payroll.pay(of: b.staff[0], month: nov, in: b, rules: PayRules()).total == 8000 + 9600)
    }

    @Test("月給は在籍した日数で日割り、時間外は月給÷所定時間の125%")
    func monthly() {
        let full = member([WageEntry(id: "m", from: "2026-01-01", kind: .monthly, amount: 300_000)])
        #expect(Payroll.pay(of: full, month: nov, in: book(full), rules: PayRules()).total == 300_000)

        let joined = member([WageEntry(id: "m", from: "2026-11-16", kind: .monthly, amount: 300_000)], join: "2026-11-16")
        #expect(Payroll.pay(of: joined, month: nov, in: book(joined), rules: PayRules()).total == 150_000)

        var b = book(full)
        work(&b, DayKey(2026, 11, 10), "09:00", "19:00")   // 10時間 → 時間外2時間
        // 300000 ÷ 160 = 1875円/時 × 1.25 × 2時間 = 4687.5
        #expect(Payroll.pay(of: b.staff[0], month: nov, in: b, rules: PayRules()).total == 300_000 + 4688)
    }

    @Test("給与が無い日は数え、金額には入れない")
    func missingWage() {
        var b = book(member([hourly(1000, from: "2026-11-15")]))
        work(&b, DayKey(2026, 11, 10), "09:00", "17:00")
        work(&b, DayKey(2026, 11, 20), "09:00", "17:00")
        let p = Payroll.pay(of: b.staff[0], month: nov, in: b, rules: PayRules())
        #expect(p.missingWageDays == 1)
        #expect(p.total == 8000)
    }

    @Test("CSV は BOM 付きで、合計の行がある")
    func csv() {
        var b = book(member([hourly(1000)]))
        work(&b, DayKey(2026, 11, 10), "09:00", "17:00")
        let p = Payroll.pay(of: b.staff[0], month: nov, in: b, rules: PayRules())
        let text = Payroll.csv(rows: [(member: b.staff[0], department: "フロント, 本館", pay: p)], month: nov)
        #expect(text.hasPrefix("\u{FEFF}月,部門"))
        #expect(text.contains("\"フロント, 本館\""))
        #expect(text.contains(",合計,"))
        #expect(text.contains(",8000,"))
    }

    @Test("割増の決まり・給与はバックアップで読み戻せる")
    func backup() throws {
        var b = book(member([hourly(1100), WageEntry(id: "m", from: "2027-04-01", kind: .monthly, amount: 250_000)]))
        b.pay.overtimeRate = 30
        b.pay.monthlyStandardHours = 170
        let (again, _) = try BackupFile.read(try BackupFile.write(b))
        #expect(again.pay == b.pay)
        #expect(again.staff.first?.wages == b.staff[0].wages)
    }

    @Test("前の版の割増の決まり（項目が足りない）も読める")
    func olderRules() throws {
        let r = try JSONDecoder().decode(PayRules.self, from: Data(#"{"overtimeRate":30}"#.utf8))
        #expect(r.overtimeRate == 30)
        #expect(r.nightRate == 25)
        #expect(r.weeklyHours == 40)
    }
}
