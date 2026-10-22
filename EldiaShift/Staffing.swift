import Foundation

// MARK: - 適正人員（部門ごと・時間帯ごとに、何人いてほしいか）

/// 日の型。カレンダーから自動で決まり（平日・土曜・日祝）、日ごとに「繁忙」「閑散」に変えられる
enum DayType: String, Codable, CaseIterable, Identifiable, Sendable {
    case quiet, weekday, saturday, holiday, busy
    var id: String { rawValue }

    var title: String {
        switch self {
        case .quiet: "閑散"
        case .weekday: "平日"
        case .saturday: "土曜"
        case .holiday: "日祝"
        case .busy: "繁忙"
        }
    }

    var short: String {
        switch self {
        case .quiet: "閑"
        case .weekday: "平"
        case .saturday: "土"
        case .holiday: "祝"
        case .busy: "繁"
        }
    }

    /// カレンダーどおりの型（日曜・祝日は日祝）
    static func calendar(_ d: DayKey) -> DayType {
        if d.weekday == 0 || JapaneseHolidays.isHoliday(d) { return .holiday }
        return d.weekday == 6 ? .saturday : .weekday
    }
}

/// 時間帯ひとつ分の必要人数（startHour 時〜endHour 時。end ≤ start は日をまたぐ）
struct StaffingBand: Codable, Equatable, Identifiable, Sendable {
    var id = UUID().uuidString
    var departmentID: String
    var startHour: Int
    var endHour: Int
    var weekday: Int
    var saturday: Int
    var holiday: Int
    /// 未設定なら「平日 −1」
    var quiet: Int?
    /// 未設定なら「平日・土曜・日祝でいちばん多い数 +1」
    var busy: Int?

    func need(_ t: DayType) -> Int {
        switch t {
        case .weekday: weekday
        case .saturday: saturday
        case .holiday: holiday
        case .quiet: quiet ?? max(0, weekday - 1)
        case .busy: busy ?? (max(weekday, saturday, holiday) + 1)
        }
    }

    func covers(hour h: Int) -> Bool {
        if startHour == endHour { return true }   // 24時間
        return startHour < endHour ? (h >= startHour && h < endHour) : (h >= startHour || h < endHour)
    }

    var hours: [Int] { (0..<24).filter(covers) }

    var timeText: String {
        startHour == endHour ? "24時間" : "\(startHour):00〜\(endHour <= startHour ? "翌" : "")\(endHour):00"
    }
}

/// 適正人員の設定まるごと（チーム全体の設定として保存）
struct StaffingPlan: Codable, Equatable, Sendable {
    var bands: [StaffingBand] = []
    /// 日ごとの型の変更（"yyyy-MM-dd" → 型）。カレンダーどおりの日は入れない
    var dayTypes: [String: DayType] = [:]

    var isEmpty: Bool { bands.isEmpty }

    func type(of d: DayKey) -> DayType { dayTypes[d.description] ?? DayType.calendar(d) }

    mutating func setType(_ t: DayType, for d: DayKey) {
        dayTypes[d.description] = (t == DayType.calendar(d)) ? nil : t
    }

    func bands(for departmentID: String) -> [StaffingBand] {
        bands.filter { $0.departmentID == departmentID }.sorted { $0.startHour < $1.startHour }
    }

    /// その部門・その日・その時台に必要な人数（決めていない時間帯は nil）。重なる時間帯は多いほう
    func need(_ departmentID: String, on d: DayKey, hour h: Int) -> Int? {
        let t = type(of: d)
        return bands.filter { $0.departmentID == departmentID && $0.covers(hour: h) }.map { $0.need(t) }.max()
    }

    func hasPlan(for departmentID: String) -> Bool { bands.contains { $0.departmentID == departmentID } }

    /// その日の 0〜23時台それぞれの必要人数（決めていない時間は nil）。日の型を1回だけ調べる
    func needs(_ departmentID: String, on d: DayKey) -> [Int?] {
        let t = type(of: d)
        let mine = bands.filter { $0.departmentID == departmentID }
        return (0..<24).map { h in mine.filter { $0.covers(hour: h) }.map { $0.need(t) }.max() }
    }
}

// MARK: - 実際の人数とくらべる

struct StaffingGap: Equatable, Sendable {
    /// 足りない人×時間（例：2人足りない時間が3時間 → 6）
    var short = 0
    /// 多すぎる人×時間
    var over = 0
    /// 足りない時間帯の数（時間）
    var shortHours = 0

    static func + (a: StaffingGap, b: StaffingGap) -> StaffingGap {
        StaffingGap(short: a.short + b.short, over: a.over + b.over, shortHours: a.shortHours + b.shortHours)
    }
}

enum StaffingCheck {
    /// 1日・1部門の不足／過剰（必要人数を決めている時間帯だけ）
    static func gap(_ plan: StaffingPlan, department: String, members: [StaffMember], on d: DayKey,
                    working: (_ members: [StaffMember], _ day: DayKey, _ hour: Int) -> Int) -> StaffingGap {
        var g = StaffingGap()
        let needs = plan.needs(department, on: d)
        for h in 0..<24 {
            guard let need = needs[h] else { continue }
            let n = working(members, d, h)
            if n < need { g.short += need - n; g.shortHours += 1 } else if n > need { g.over += n - need }
        }
        return g
    }

    /// 数えておいた24時間分の人数で、1日・1部門の不足／過剰を出す
    static func gap(_ plan: StaffingPlan, department: String, on d: DayKey, counts: [Int]) -> StaffingGap {
        var g = StaffingGap()
        let needs = plan.needs(department, on: d)
        for h in 0..<24 {
            guard let need = needs[h] else { continue }
            let n = h < counts.count ? counts[h] : 0
            if n < need { g.short += need - n; g.shortHours += 1 } else if n > need { g.over += n - need }
        }
        return g
    }

    /// 過去の実績から、型ごと・時台ごとの平均人数（四捨五入）を出す（「実績から提案」用）
    /// 返り値：型 → 24時間ぶんの人数
    static func averages(department members: [StaffMember], days: [DayKey], plan: StaffingPlan,
                         working: (_ members: [StaffMember], _ day: DayKey, _ hour: Int) -> Int) -> [DayType: [Int]] {
        var sum: [DayType: [Int]] = [:], count: [DayType: Int] = [:]
        for d in days {
            let t = plan.type(of: d)
            var row = sum[t] ?? Array(repeating: 0, count: 24)
            for h in 0..<24 { row[h] += working(members, d, h) }
            sum[t] = row
            count[t, default: 0] += 1
        }
        return sum.reduce(into: [:]) { out, kv in
            let c = Double(count[kv.key] ?? 1)
            out[kv.key] = kv.value.map { Int((Double($0) / c).rounded()) }
        }
    }

    /// 平均人数から時間帯を作る（同じ人数が続く時間をひとまとめ。0人の時間は作らない）
    static func suggestBands(department: String, averages: [DayType: [Int]]) -> [StaffingBand] {
        let wd = averages[.weekday] ?? Array(repeating: 0, count: 24)
        let sa = averages[.saturday] ?? wd
        let ho = averages[.holiday] ?? sa
        var out: [StaffingBand] = []
        func key(_ h: Int) -> [Int] { [wd[h], sa[h], ho[h]] }
        var start = 0
        for h in 1...24 where h == 24 || key(h) != key(start) {
            let v = key(start)
            if v.contains(where: { $0 > 0 }) {
                out.append(StaffingBand(departmentID: department, startHour: start, endHour: h % 24,
                                        weekday: v[0], saturday: v[1], holiday: v[2]))
            }
            start = h
        }
        return out
    }
}
