import Foundation

// MARK: - 労務の注意（法律の決まりに近づいたら知らせる。決めるのは管理者）

/// 注意の決まり（会社ごとに設定で変えられる）
struct LaborRules: Codable, Equatable, Sendable {
    /// 連勤：この日数以上続いたら注意
    var consecutiveEnabled = true
    var consecutiveDays = 6
    /// 勤務と勤務の間（退勤から次の出勤まで）がこの時間より短いと注意（勤務間インターバル）
    var intervalEnabled = true
    var intervalHours = 11
    /// 週（月〜日）の実働がこの時間を超えたら注意
    var weeklyEnabled = true
    var weeklyHours = 40
    /// 1日の実働がこの時間を超えたら注意（変形労働時間制なら切っておく）
    var dailyEnabled = false
    var dailyHours = 8
    /// 年5日の有休を取らせる義務（年10日以上付与される人）
    var leaveObligationEnabled = true
}

/// 1人×1日の注意
enum LaborIssue: Hashable, Sendable {
    case consecutive(Int)
    case interval(minutes: Int)
    case weekly(hours: Double)
    case daily(hours: Double)
    case requestedOff

    var text: String {
        switch self {
        case .consecutive(let n): "\(n)連勤"
        case .interval(let m): m < 0 ? "前の勤務と重なっています" : "前の勤務から\(Self.hm(m))しか空いていません"
        case .weekly(let h): "この週の実働 \(String(format: "%.1f", h))時間"
        case .daily(let h): "1日の実働 \(String(format: "%.1f", h))時間"
        case .requestedOff: "希望休の日に勤務が入っています"
        }
    }

    var short: String {
        switch self {
        case .consecutive(let n): "\(n)連勤"
        case .interval: "間隔"
        case .weekly: "週超過"
        case .daily: "日超過"
        case .requestedOff: "希望休"
        }
    }

    private static func hm(_ m: Int) -> String { m % 60 == 0 ? "\(m / 60)時間" : "\(m / 60)時間\(m % 60)分" }
}

enum LaborCheck {
    /// 勤務の始まりと終わり（その日の0時からの分。日をまたぐと 1440 を超える）
    static func span(_ r: ResolvedShift?) -> (start: Int, end: Int)? {
        guard let r, !r.isOff, let s = ClockTime.parse(r.inTime), let e = ClockTime.parse(r.outTime) else { return nil }
        return (s, e > s ? e : e + 1440)
    }

    /// 表に出す日々の、人×日ごとの注意。前後の日も見て数える（連勤・週の合計・前日からの間隔）
    static func issues(_ book: ShiftBook, members: [StaffMember], days: [DayKey]) -> [CellKey: [LaborIssue]] {
        guard let first = days.min(), let last = days.max() else { return [:] }
        let rules = book.labor
        // 連勤のために前を、週の合計のために前後の週を見る
        let lookBack = max(rules.consecutiveDays, 7)
        let from = first.adding(days: -lookBack)
        let to = last.adding(days: 6)
        var range: [DayKey] = []
        var d = from
        while d <= to { range.append(d); d = d.adding(days: 1) }
        let shown = Set(days)

        var out: [CellKey: [LaborIssue]] = [:]
        for m in members {
            let resolved = range.map { Schedule.resolve(m, on: $0, in: book) }
            var run = 0
            var weekKey: DayKey?
            var weekTotal = 0.0
            // その週の合計（超えた日以降の勤務日に出す）
            var weekTotals: [DayKey: Double] = [:]
            for (i, day) in range.enumerated() {
                let monday = day.adding(days: -((day.weekday + 6) % 7))
                if monday != weekKey { weekKey = monday; weekTotal = 0 }
                let r = resolved[i]
                let sp = span(r)
                let net = sp == nil ? nil : r?.netHours(book.breakRules)
                if let net { weekTotal += net }
                weekTotals[monday] = weekTotal
                run = sp == nil ? 0 : run + 1

                guard shown.contains(day), sp != nil else { continue }
                var list: [LaborIssue] = []
                if m.requestsOff(day) { list.append(.requestedOff) }
                if rules.consecutiveEnabled, run >= rules.consecutiveDays { list.append(.consecutive(run)) }
                if rules.intervalEnabled, i > 0, let prev = span(resolved[i - 1]), let cur = sp {
                    let gap = 1440 + cur.start - prev.end
                    if gap < rules.intervalHours * 60 { list.append(.interval(minutes: gap)) }
                }
                if rules.dailyEnabled, let net, net > Double(rules.dailyHours) { list.append(.daily(hours: net)) }
                if rules.weeklyEnabled, weekTotal > Double(rules.weeklyHours) { list.append(.weekly(hours: weekTotal)) }
                if !list.isEmpty { out[CellKey(staffID: m.id, day: day)] = list }
            }
            // 週の合計は、週の終わりまでの数字にそろえる（途中の日は途中の合計になるので）
            if rules.weeklyEnabled {
                for (k, list) in out where k.staffID == m.id {
                    let monday = k.day.adding(days: -((k.day.weekday + 6) % 7))
                    let total = weekTotals[monday] ?? 0
                    out[k] = list.map { (x: LaborIssue) -> LaborIssue in
                        if case .weekly = x { return .weekly(hours: total) }
                        return x
                    }
                }
            }
        }
        return out
    }

    // MARK: 年5日の有休

    struct LeaveObligation: Equatable, Sendable {
        /// 付与日（ここから1年のうちに5日）
        var since: DayKey
        var deadline: DayKey
        /// 期間内に入っている「有休」（これからの予定も含む）
        var taken: Int
        var needed: Int { max(0, 5 - taken) }
        /// 期限までの日数
        func daysLeft(from today: DayKey) -> Int {
            Calendar.shift.dateComponents([.day], from: today.date, to: deadline.date).day ?? 0
        }
    }

    /// 年10日以上の有休が付与される人だけ。付与されていない・10日未満なら nil
    static func leaveObligation(of m: StaffMember, in book: ShiftBook, today: DayKey) -> LeaveObligation? {
        guard book.labor.leaveObligationEnabled,
              let b = PaidLeave.balance(of: m, month: MonthKey(today), in: book, today: today),
              b.grant.current >= 10 else { return nil }
        let since = b.grant.since
        let deadline = DayKey(Calendar.shift.date(byAdding: DateComponents(year: 1, day: -1), to: since.date)!)
        let taken = book.cells.filter { k, c in
            k.staffID == m.id && c.blockID == PaidLeave.blockID && k.day >= since && k.day <= deadline
        }.count
        return LeaveObligation(since: since, deadline: deadline, taken: taken)
    }
}
