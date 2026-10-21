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

    /// 拘束時間（時間）。休み・時刻なしは nil
    var hours: Double? {
        guard !isOff, let a = ClockTime.parse(inTime), let b = ClockTime.parse(outTime) else { return nil }
        return ClockTime.hours(from: a, to: b)
    }

    /// 実働時間（休憩を引いた時間。PC版と同じ）
    var netHours: Double? { hours.map(Breaks.net) }
}

/// どの日に誰が何の勤務かを決める（旧シフト表と同じ決め方）
/// 1. 手で入れた内容（cells）があればそれ
/// 2. 期間の予定に入っていれば、その日の指定（期間内で指定がない日は空き）
/// 3. 週のくり返し（その日までに使い始めたもののうち一番新しいもの。決まらなければ「使用中」のもの）
enum Schedule {
    static func resolve(_ member: StaffMember, on day: DayKey, in book: ShiftBook) -> ResolvedShift? {
        if member.hasLeft(on: day) { return nil }
        if let cell = book.cells[CellKey(staffID: member.id, day: day)] {
            return ResolvedShift(inTime: cell.inTime, outTime: cell.outTime, blockID: cell.blockID, isOff: cell.isOff, isAuto: false)
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
            : ResolvedShift(inTime: b.inTime, outTime: b.outTime, blockID: b.id, isOff: false, isAuto: true)
    }
}

// MARK: - 休憩（PC版と同じ：4.5時間以上は30分、6.5時間以上は1時間）

enum Breaks {
    static func breakHours(_ gross: Double) -> Double { gross >= 6.5 ? 1 : gross >= 4.5 ? 0.5 : 0 }
    static func net(_ gross: Double) -> Double { gross - breakHours(gross) }
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
            } else if let h = r.netHours {
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
    /// その日の h 時台（h:00〜h+1:00）に勤務している人数。
    /// 日をまたぐ勤務は、その日の出勤以降と、その日の退勤まで（＝前夜からの続きに見える部分）の両方を数える（PC版と同じ）
    static func working(_ members: [StaffMember], on day: DayKey, hour h: Int, in book: ShiftBook) -> Int {
        members.filter { m in
            guard let r = Schedule.resolve(m, on: day, in: book), !r.isOff,
                  let s = ClockTime.parse(r.inTime), let e = ClockTime.parse(r.outTime) else { return false }
            let hs = h * 60, he = (h + 1) * 60
            return e > s ? (s < he && e > hs) : (s < he || e > hs)
        }.count
    }
}
