import Foundation

/// 画面に出す1人×1日のシフト
struct ResolvedShift: Hashable, Sendable {
    var inTime: String
    var outTime: String
    var blockID: String?
    var isOff: Bool
    /// 手で入れたものではなく、週のくり返し・期間の予定から自動で決まったもの
    var isAuto: Bool
    var isPeriod: Bool = false
    var patternLabel: String?
    /// ひな形で決めた休憩（分）。nil は休憩の決まりに従う
    var breakOverride: Int? = nil
    /// 勤務する店舗（休みは nil）
    var storeID: String? = nil
    /// いま見ている店舗ではなく、ほかの店舗で勤務する日（掛け持ち）。人数には数えない
    var elsewhere = false

    /// 拘束時間（時間）。休み・時刻なしは nil
    var hours: Double? {
        guard !isOff, let a = ClockTime.parse(inTime), let b = ClockTime.parse(outTime) else { return nil }
        return ClockTime.hours(from: a, to: b)
    }

    /// 実働時間（休憩を引いた時間）
    func netHours(_ rules: BreakRules) -> Double? { hours.map { rules.netHours(gross: $0, override: breakOverride) } }

    /// 引いた休憩（分）
    func breakMinutes(_ rules: BreakRules) -> Int? {
        guard let h = hours else { return nil }
        return breakOverride ?? rules.breakMinutes(forGross: Int((h * 60).rounded()))
    }
}

/// どの日に誰が何の勤務かを決める（旧シフト表と同じ決め方）
/// 1. 手で入れた内容（cells）があればそれ
/// 2. 期間の予定に入っていれば、その日の指定（期間内で指定がない日は空き）
/// 3. 週のくり返し（その日までに使い始めたもののうち一番新しいもの。決まらなければ「使用中」のもの）
enum Schedule {
    static func resolve(_ member: StaffMember, on day: DayKey, in book: ShiftBook) -> ResolvedShift? {
        guard var r = resolveIgnoringStore(member, on: day, in: book) else { return nil }
        if !r.isOff {
            let sid: String
            if let cell = book.cells[CellKey(staffID: member.id, day: day)] { sid = book.storeID(of: cell, for: member) }
            else { sid = book.homeStoreID(of: member) }
            r.storeID = sid
            if let scope = book.scopeStoreID, scope != sid { r.elsewhere = true }
        }
        return r
    }

    private static func resolveIgnoringStore(_ member: StaffMember, on day: DayKey, in book: ShiftBook) -> ResolvedShift? {
        if member.hasLeft(on: day) { return nil }
        if let cell = book.cells[CellKey(staffID: member.id, day: day)] {
            var r = ResolvedShift(inTime: cell.inTime, outTime: cell.outTime, blockID: cell.blockID, isOff: cell.isOff, isAuto: false)
            // ひな形のまま入れた日は、そのひな形の休憩を使う（時刻を変えた日は決まりに従う）
            if let b = book.block(cell.blockID, for: member), b.inTime == cell.inTime, b.outTime == cell.outTime {
                r.breakOverride = b.breakMinutes
            }
            return r
        }
        return automatic(member, on: day, in: book)
    }

    /// 手で入れた内容を見ずに、くり返し・期間の予定だけから決める
    static func automatic(_ member: StaffMember, on day: DayKey, in book: ShiftBook) -> ResolvedShift? {
        let dStr = day.description

        if let period = member.periodPatterns.first(where: { p in
            guard let s = p.startDate, let e = p.endDate, !s.isEmpty, !e.isEmpty else { return false }
            return dStr >= s && dStr <= e
        }) {
            guard let bid = period.days[dStr], !bid.isEmpty, let b = book.block(bid, for: member) else { return nil }
            var r = shift(from: b)
            r.isPeriod = true
            return r
        }

        guard let pattern = weeklyPattern(for: member, on: dStr) else { return nil }
        let w = day.weekday
        guard pattern.days.indices.contains(w), let bid = pattern.days[w], !bid.isEmpty,
              let b = book.block(bid, for: member) else { return nil }
        var r = shift(from: b)
        r.patternLabel = pattern.label
        return r
    }

    /// その日に使う週のくり返し
    static func weeklyPattern(for member: StaffMember, on dStr: String) -> WeekPattern? {
        var picked: WeekPattern?
        var pickedFrom: String?
        for p in member.patterns {
            let from = p.activeFrom.flatMap { $0.isEmpty ? nil : $0 }
            if let from, from > dStr { continue }
            guard picked != nil else { picked = p; pickedFrom = from; continue }
            switch (from, pickedFrom) {
            case (nil, .some): continue                      // 日付指定のある方を優先
            case (.some, nil): picked = p; pickedFrom = from
            case let (.some(f), .some(b)) where f > b: picked = p; pickedFrom = from
            default: continue
            }
        }
        let undated = member.patterns.filter { ($0.activeFrom ?? "").isEmpty }.count
        if picked == nil || (pickedFrom == nil && undated > 1) {
            // どれか決まらないときは「使用中」に選ばれているもの
            if let id = member.activePatternID, let active = member.patterns.first(where: { $0.id == id }) {
                let from = active.activeFrom ?? ""
                if from.isEmpty || from <= dStr { picked = active }
            }
        }
        return picked
    }

    private static func shift(from b: TimeBlock) -> ResolvedShift {
        b.isOff
            ? ResolvedShift(inTime: "", outTime: "", blockID: b.id, isOff: true, isAuto: true)
            : ResolvedShift(inTime: b.inTime, outTime: b.outTime, blockID: b.id, isOff: false, isAuto: true, breakOverride: b.breakMinutes)
    }
}

// MARK: - 月の集計（勤務日数・実働時間）

struct MonthSummary: Hashable, Sendable {
    var workDays = 0
    var offDays = 0
    /// 実働時間（休憩を引いた時間）
    var hours: Double = 0

    static func of(_ member: StaffMember, month: MonthKey, in book: ShiftBook) -> MonthSummary {
        of(member, days: month.days, in: book)
    }

    /// 指定した日々（週など）の集計
    static func of(_ member: StaffMember, days: [DayKey], in book: ShiftBook) -> MonthSummary {
        var s = MonthSummary()
        for day in days {
            guard let r = Schedule.resolve(member, on: day, in: book) else { continue }
            if r.isOff {
                s.offDays += 1
            } else if let h = r.netHours(book.breakRules) {
                // 時刻が入っている日だけ数える（PC版と同じ）
                s.workDays += 1
                s.hours += h
            }
        }
        return s
    }
}

// MARK: - 時間帯別の人数（PC版と同じ数え方）

enum Headcount {
    /// その日の h 時台（h:00〜h+1:00）に勤務している人数（ほかの店舗で勤務する人は数えない）。
    /// 日をまたぐ勤務は、その日の出勤以降と、その日の退勤まで（＝前夜からの続きに見える部分）の両方を数える（PC版と同じ）
    static func working(_ members: [StaffMember], on day: DayKey, hour h: Int, in book: ShiftBook) -> Int {
        members.filter { m in
            guard let r = Schedule.resolve(m, on: day, in: book), !r.isOff, !r.elsewhere,
                  let s = ClockTime.parse(r.inTime), let e = ClockTime.parse(r.outTime) else { return false }
            let hs = h * 60, he = (h + 1) * 60
            return e > s ? (s < he && e > hs) : (s < he || e > hs)
        }.count
    }
}

// MARK: - 表の計算をまとめて1回で（速さのため）

/// 表に出す人×日の勤務を、描くたびではなく一度だけ決めておく
/// （時間帯別在籍人数は 24時間×日×人 を数えるので、毎回決めていると重い）
/// 出勤・退勤の文字列もここで一度だけ分に直しておき、人数を数えるときは整数の比較だけにする
struct ScheduleTable {
    private var resolved: [CellKey: ResolvedShift] = [:]
    /// この店舗で勤務する時間（分）。休み・ほかの店舗・時刻なしは入れない
    private var spans: [CellKey: (start: Int, end: Int)] = [:]
    let rules: BreakRules

    init(book: ShiftBook, members: [StaffMember], days: [DayKey]) {
        rules = book.breakRules
        resolved.reserveCapacity(members.count * days.count)
        for m in members {
            for d in days {
                guard let r = Schedule.resolve(m, on: d, in: book) else { continue }
                let k = CellKey(staffID: m.id, day: d)
                resolved[k] = r
                if !r.isOff, !r.elsewhere, let a = ClockTime.parse(r.inTime), let b = ClockTime.parse(r.outTime) {
                    spans[k] = (a, b)
                }
            }
        }
    }

    func get(_ m: StaffMember, _ d: DayKey) -> ResolvedShift? {
        resolved[CellKey(staffID: m.id, day: d)]
    }

    func summary(_ m: StaffMember, days: [DayKey]) -> MonthSummary {
        var s = MonthSummary()
        for d in days {
            guard let r = get(m, d) else { continue }
            if r.isOff { s.offDays += 1 } else if let h = r.netHours(rules) { s.workDays += 1; s.hours += h }
        }
        return s
    }

    /// その時間（分）の勤務が h 時台にかかっているか（Headcount.working と同じ数え方）
    @inline(__always)
    static func covers(_ s: Int, _ e: Int, hour h: Int) -> Bool {
        let hs = h * 60, he = (h + 1) * 60
        return e > s ? (s < he && e > hs) : (s < he || e > hs)
    }

    /// その日の h 時台に勤務している人数（Headcount.working と同じ数え方）
    func working(_ members: [StaffMember], on d: DayKey, hour h: Int) -> Int {
        var n = 0
        for m in members {
            if let sp = spans[CellKey(staffID: m.id, day: d)], Self.covers(sp.start, sp.end, hour: h) { n += 1 }
        }
        return n
    }

    /// その日の 0〜23時台それぞれの人数を、まとめて1回で数える（24回 working を呼ぶより速い）
    func counts(_ members: [StaffMember], on d: DayKey) -> [Int] {
        var c = [Int](repeating: 0, count: 24)
        for m in members {
            guard let sp = spans[CellKey(staffID: m.id, day: d)] else { continue }
            for h in 0..<24 where Self.covers(sp.start, sp.end, hour: h) { c[h] += 1 }
        }
        return c
    }
}

/// 部門ごと・日ごとの、時間帯別の人数（月の表を描くときに一度だけ数えて使い回す）
struct HourlyCounts {
    private var table: [String: [DayKey: [Int]]] = [:]

    init(groups: [DepartmentGroup], days: [DayKey], table t: ScheduleTable) {
        for g in groups {
            var byDay: [DayKey: [Int]] = [:]
            byDay.reserveCapacity(days.count)
            for d in days { byDay[d] = t.counts(g.members, on: d) }
            table[g.department.id] = byDay
        }
    }

    func count(_ department: String, on d: DayKey, hour h: Int) -> Int {
        table[department]?[d]?[h] ?? 0
    }
}
