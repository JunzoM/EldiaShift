import Foundation

// MARK: - 人件費の概算（HOTEL SHIFT から移植。時給は「〇月〇日から時給〇円」の履歴で日ごとに決める）
// 給与計算ではなく、シフトを組むときの目安。法定休日の割増・月60時間超の割増・手当・交通費・社会保険は入れない。

/// 給与の決まり1件（この日から、この金額）
struct WageEntry: Identifiable, Hashable, Codable, Sendable {
    enum Kind: String, Codable, Sendable, CaseIterable, Identifiable {
        case hourly, monthly
        var id: String { rawValue }
        var label: String { self == .hourly ? "時給" : "月給" }
    }

    var id: String
    /// この日（YYYY-MM-DD）から使う
    var from: String
    var kind: Kind
    /// 円
    var amount: Int
}

extension StaffMember {
    /// その日に使う給与の決まり（その日までに始まったもののうち、いちばん新しいもの）
    func wage(on day: DayKey) -> WageEntry? {
        let d = day.description
        return wages.filter { DayKey($0.from) != nil && $0.from <= d }.max { $0.from < $1.from }
    }
}

/// 割増の決まり（会社ごと。設定で変えられる）
struct PayRules: Codable, Equatable, Sendable {
    /// 時間外の割増（%）
    var overtimeRate = 25
    /// 深夜（22:00〜5:00）の割増（%）
    var nightRate = 25
    /// 1日の実働がこれを超えた分は時間外
    var dailyEnabled = true
    var dailyHours = 8
    /// 週（月〜日）の実働がこれを超えた分は時間外（1日の時間外として数えた分は除く）
    var weeklyEnabled = true
    var weeklyHours = 40
    /// 月給の人の1時間あたり ＝ 月給 ÷ この時間（月の所定労働時間）
    var monthlyStandardHours = 160

    static let nightStart = 22 * 60
    static let nightEnd = 5 * 60

    init() {}

    /// 項目が足りない設定（あとから足した項目）も読めるように
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PayRules()
        overtimeRate = try c.decodeIfPresent(Int.self, forKey: .overtimeRate) ?? d.overtimeRate
        nightRate = try c.decodeIfPresent(Int.self, forKey: .nightRate) ?? d.nightRate
        dailyEnabled = try c.decodeIfPresent(Bool.self, forKey: .dailyEnabled) ?? d.dailyEnabled
        dailyHours = try c.decodeIfPresent(Int.self, forKey: .dailyHours) ?? d.dailyHours
        weeklyEnabled = try c.decodeIfPresent(Bool.self, forKey: .weeklyEnabled) ?? d.weeklyEnabled
        weeklyHours = try c.decodeIfPresent(Int.self, forKey: .weeklyHours) ?? d.weeklyHours
        monthlyStandardHours = max(1, try c.decodeIfPresent(Int.self, forKey: .monthlyStandardHours) ?? d.monthlyStandardHours)
    }
}

/// 1人・1か月の人件費
struct StaffPay: Equatable, Sendable {
    var workDays = 0
    /// 実働（分）
    var netMinutes = 0
    /// 時間外（分）。1日の超過と週の超過の合計
    var overtimeMinutes = 0
    /// 深夜（分）
    var nightMinutes = 0
    /// 時給の人の基本（実働×時給）
    var hourlyBase = 0.0
    /// 月給（その月に在籍した日の割合で日割り）
    var monthlyBase = 0.0
    var overtimePay = 0.0
    var nightPay = 0.0
    /// 勤務があるのに給与の決まりが無い日
    var missingWageDays = 0

    var total: Int { Int((hourlyBase + monthlyBase + overtimePay + nightPay).rounded()) }
    var hasMonthly: Bool { monthlyBase > 0 }

    static func + (a: StaffPay, b: StaffPay) -> StaffPay {
        StaffPay(workDays: a.workDays + b.workDays, netMinutes: a.netMinutes + b.netMinutes,
                 overtimeMinutes: a.overtimeMinutes + b.overtimeMinutes, nightMinutes: a.nightMinutes + b.nightMinutes,
                 hourlyBase: a.hourlyBase + b.hourlyBase, monthlyBase: a.monthlyBase + b.monthlyBase,
                 overtimePay: a.overtimePay + b.overtimePay, nightPay: a.nightPay + b.nightPay,
                 missingWageDays: a.missingWageDays + b.missingWageDays)
    }
}

enum Payroll {
    /// 勤務の中の深夜（22:00〜5:00）の分数（日をまたぐ勤務も数える）
    static func nightMinutes(start: Int, end: Int) -> Int {
        let windows = [(0, PayRules.nightEnd),
                       (PayRules.nightStart, 1440 + PayRules.nightEnd),
                       (1440 + PayRules.nightStart, 2880 + PayRules.nightEnd)]
        return windows.reduce(0) { sum, w in sum + max(0, min(end, w.1) - max(start, w.0)) }
    }

    /// その月の1人分。週の時間外は月をまたぐ週も前後の日を見て数え、その月の日の分だけを入れる。
    /// 店舗を見ているときは、その店舗で勤務した日だけ（月給は自分の店舗に入れる）。週の時間は全店舗の合計で数える
    static func pay(of m: StaffMember, month: MonthKey, in book: ShiftBook, rules: PayRules) -> StaffPay {
        let days = month.days
        guard let first = days.first, let last = days.last else { return StaffPay() }
        let from = first.adding(days: -((first.weekday + 6) % 7))   // その週の月曜
        let to = last.adding(days: (7 - last.weekday) % 7)           // その週の日曜
        let inMonth = Set(days)
        let scope = book.scopeStoreID
        let countMonthly = scope == nil || scope == book.homeStoreID(of: m)

        var out = StaffPay()
        var weekRegular = 0
        var weekStart: DayKey?
        var d = from
        while d <= to {
            defer { d = d.adding(days: 1) }
            let monday = d.adding(days: -((d.weekday + 6) % 7))
            if monday != weekStart { weekStart = monday; weekRegular = 0 }
            let wage = m.wage(on: d)

            // 月給は在籍している日だけ日割り
            if inMonth.contains(d), countMonthly, let w = wage, w.kind == .monthly, !m.hasLeft(on: d),
               DayKey(m.joinDate).map({ d >= $0 }) ?? true {
                out.monthlyBase += Double(w.amount) / Double(days.count)
            }

            guard let r = Schedule.resolve(m, on: d, in: book), !r.isOff,
                  let sp = LaborCheck.span(r), let netH = r.netHours(book.breakRules) else { continue }
            let net = Int((netH * 60).rounded())
            let daily = rules.dailyEnabled ? max(0, net - rules.dailyHours * 60) : 0
            let before = weekRegular
            weekRegular += net - daily
            let limit = rules.weeklyHours * 60
            let weekly = rules.weeklyEnabled ? max(0, weekRegular - limit) - max(0, before - limit) : 0

            guard inMonth.contains(d), !(scope != nil && r.elsewhere) else { continue }
            let night = min(nightMinutes(start: sp.start, end: sp.end), net)
            let ot = daily + weekly
            out.workDays += 1
            out.netMinutes += net
            out.overtimeMinutes += ot
            out.nightMinutes += night

            guard let w = wage, w.amount > 0 else { out.missingWageDays += 1; continue }
            let otRate = Double(rules.overtimeRate) / 100
            let nightRate = Double(rules.nightRate) / 100
            switch w.kind {
            case .hourly:
                let rate = Double(w.amount)
                out.hourlyBase += rate * Double(net) / 60
                out.overtimePay += rate * otRate * Double(ot) / 60
                out.nightPay += rate * nightRate * Double(night) / 60
            case .monthly:
                // 月給は所定の時間分を含むので、時間外は1時間あたりの125%（割増込み）、深夜は割増分だけ
                let rate = Double(w.amount) / Double(max(1, rules.monthlyStandardHours))
                out.overtimePay += rate * (1 + otRate) * Double(ot) / 60
                out.nightPay += rate * nightRate * Double(night) / 60
            }
        }
        return out
    }

    /// 人件費の CSV（Excel で開けるよう UTF-8 の BOM 付き）
    static func csv(rows: [(member: StaffMember, department: String, pay: StaffPay)], month: MonthKey) -> String {
        func h(_ minutes: Int) -> String { String(format: "%.2f", Double(minutes) / 60) }
        func q(_ s: String) -> String { s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) ? "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" : s }
        var lines = ["月,部門,スタッフ,雇用形態,出勤日数,実働時間,時間外,深夜,時給分,月給分,時間外手当,深夜手当,合計,給与未設定の日"]
        for r in rows {
            let p = r.pay
            lines.append([month.description, q(r.department), q(r.member.name), q(r.member.employment), "\(p.workDays)",
                          h(p.netMinutes), h(p.overtimeMinutes), h(p.nightMinutes),
                          "\(Int(p.hourlyBase.rounded()))", "\(Int(p.monthlyBase.rounded()))",
                          "\(Int(p.overtimePay.rounded()))", "\(Int(p.nightPay.rounded()))", "\(p.total)",
                          "\(p.missingWageDays)"].joined(separator: ","))
        }
        let total = rows.reduce(StaffPay()) { $0 + $1.pay }
        lines.append([month.description, "", "合計", "", "\(total.workDays)", h(total.netMinutes), h(total.overtimeMinutes),
                      h(total.nightMinutes), "\(Int(total.hourlyBase.rounded()))", "\(Int(total.monthlyBase.rounded()))",
                      "\(Int(total.overtimePay.rounded()))", "\(Int(total.nightPay.rounded()))", "\(total.total)",
                      "\(total.missingWageDays)"].joined(separator: ","))
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }
}
