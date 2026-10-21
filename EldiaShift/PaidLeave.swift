import Foundation

/// 有給休暇（労働基準法 第39条）。PC版と同じ計算
/// ・入社6か月で付与、以後1年ごと（6・18・30・42・54・66・78か月）
/// ・週30時間未満かつ週4日以下は比例付与
/// ・今期の付与日数＋前期の付与日数（2年で時効）を「付与」とし、今期の付与日から表示月の末日までに使った「有休」の日数を引く
enum PaidLeave {
    /// 有休のひな形の id（PC版と同じ）
    static let blockID = "off2"

    struct Grant: Equatable, Sendable {
        var current: Int
        var previous: Int
        var total: Int { current + previous }
        var isProportional: Bool
        var weeklyDays: Int?
        /// 今期の付与日
        var since: DayKey
    }

    struct Balance: Equatable, Sendable {
        var grant: Grant
        var used: Int
        var remaining: Int { max(0, grant.total - used) }
        /// 表示月に使った日数
        var usedThisMonth: Int
    }

    private static let grantMonths = [6, 18, 30, 42, 54, 66, 78]
    private static let normal = [10, 11, 12, 14, 16, 18, 20]
    private static let proportional: [Int: [Int]] = [
        4: [7, 8, 9, 10, 12, 13, 15],
        3: [5, 6, 6, 8, 9, 10, 11],
        2: [3, 4, 4, 5, 6, 6, 7],
        1: [1, 2, 2, 2, 3, 3, 3]
    ]

    /// 付与日数（入社から6か月未満なら nil）
    static func grant(joinDate: DayKey, weeklyDays: Int?, weeklyHours: Double?, today: DayKey) -> Grant? {
        var months = (today.year - joinDate.year) * 12 + (today.month - joinDate.month)
        if today.day < joinDate.day { months -= 1 }
        let done = grantMonths.filter { months >= $0 }.count
        guard done > 0 else { return nil }
        let isProp = weeklyDays != nil && weeklyHours != nil && weeklyHours! < 30 && (1...4).contains(weeklyDays!)
        func days(_ i: Int) -> Int {
            let j = min(i, 6)
            return isProp ? proportional[max(1, min(4, weeklyDays!))]![j] : normal[j]
        }
        let since = addMonths(joinDate, grantMonths[done - 1])
        return Grant(current: days(done - 1), previous: done >= 2 ? days(done - 2) : 0,
                     isProportional: isProp, weeklyDays: isProp ? weeklyDays : nil, since: since)
    }

    /// その人の有休の残り（入社日が無い・6か月未満なら nil）
    static func balance(of member: StaffMember, month: MonthKey, in book: ShiftBook, today: DayKey = .today) -> Balance? {
        guard let join = DayKey(member.joinDate) else { return nil }
        // 今日使っている週間パターンから、週の所定日数・時間を出す
        var weeklyDays = 0
        var weeklyHours = 0.0
        if let pattern = Schedule.weeklyPattern(for: member, on: today.description) {
            for bid in pattern.days {
                guard let b = book.block(bid, for: member), let i = b.inMinutes, let o = b.outMinutes else { continue }
                let net = Breaks.net(ClockTime.hours(from: i, to: o))
                if net > 0 { weeklyDays += 1; weeklyHours += net }
            }
        }
        guard let g = grant(joinDate: join, weeklyDays: weeklyDays == 0 ? nil : weeklyDays,
                            weeklyHours: weeklyDays == 0 ? nil : weeklyHours, today: today) else { return nil }
        let monthEnd = month.days.last!
        var used = 0
        var thisMonth = 0
        for (k, c) in book.cells where k.staffID == member.id && c.blockID == blockID {
            if k.day >= g.since && k.day <= monthEnd { used += 1 }
            if MonthKey(k.day) == month { thisMonth += 1 }
        }
        return Balance(grant: g, used: used, usedThisMonth: thisMonth)
    }

    private static func addMonths(_ d: DayKey, _ n: Int) -> DayKey {
        DayKey(Calendar.shift.date(byAdding: .month, value: n, to: d.date)!)
    }
}
