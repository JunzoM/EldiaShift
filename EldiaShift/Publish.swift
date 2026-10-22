import Foundation

// MARK: - 公開と変更点（Android のスタッフには PDF と変更点の文章で知らせる）

/// スタッフに公開したときの内容（1か月分）
struct PublishedMonth: Codable, Equatable, Sendable {
    /// "yyyy-MM"
    var month: String
    var date: Date
    /// "スタッフID|yyyy-MM-dd" → 表示（例：「早番 9:00〜18:00」「公休」）。空き日は入れない
    var entries: [String: String]

    static func key(_ m: MonthKey) -> String { String(format: "%04d-%02d", m.year, m.month) }

    static func snapshot(of book: ShiftBook, month: MonthKey) -> PublishedMonth {
        var e: [String: String] = [:]
        for g in book.staffByDepartment(visibleIn: month) {
            for m in g.members {
                for d in month.days {
                    let t = label(Schedule.resolve(m, on: d, in: book), member: m, book: book)
                    if !t.isEmpty { e[CellKey(staffID: m.id, day: d).description] = t }
                }
            }
        }
        return PublishedMonth(month: key(month), date: Date(), entries: e)
    }

    /// 文章に出すときの書き方
    static func label(_ r: ResolvedShift?, member: StaffMember, book: ShiftBook) -> String {
        guard let r else { return "" }
        let block = book.block(r.blockID, for: member)
        if r.isOff { return block?.label ?? "休み" }
        let time = "\(r.inTime)〜\(r.outTime)"
        if let block, block.inTime == r.inTime, block.outTime == r.outTime { return "\(block.label) \(time)" }
        return time
    }
}

struct PublishChange: Equatable, Sendable {
    var day: DayKey
    var staffID: String
    var staffName: String
    var before: String
    var after: String
}

enum PublishDiff {
    /// 前に公開した内容からの変更（まだ公開していなければ nil）
    static func changes(_ book: ShiftBook, month: MonthKey) -> (since: Date, changes: [PublishChange])? {
        guard let old = book.published.first(where: { $0.month == PublishedMonth.key(month) }) else { return nil }
        let now = PublishedMonth.snapshot(of: book, month: month)
        let names = Dictionary(book.staff.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        // 並び：日付 → 部門・番号の順
        let order = Dictionary(book.staffByDepartment(visibleIn: month, includeInactive: true).flatMap(\.members)
            .enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [PublishChange] = []
        for k in Set(old.entries.keys).union(now.entries.keys) {
            let a = old.entries[k] ?? "", b = now.entries[k] ?? ""
            guard a != b, let key = CellKey(legacy: k) else { continue }
            out.append(PublishChange(day: key.day, staffID: key.staffID, staffName: names[key.staffID] ?? "（削除したスタッフ）",
                                     before: a, after: b))
        }
        out.sort { ($0.day, order[$0.staffID] ?? .max) < ($1.day, order[$1.staffID] ?? .max) }
        return (old.date, out)
    }

    /// LINE などに貼る文章
    static func text(_ changes: [PublishChange], month: MonthKey, title: String) -> String {
        let wd = ["日", "月", "火", "水", "木", "金", "土"]
        var lines = ["【シフト変更のお知らせ】\(title.isEmpty ? "" : title + " ")\(month.month)月分"]
        if changes.isEmpty {
            lines.append("前回の公開から変更はありません。")
        } else {
            var lastDay: DayKey?
            for c in changes {
                if c.day != lastDay {
                    lines.append("")
                    lines.append("■\(c.day.month)/\(c.day.day)（\(wd[c.day.weekday])）")
                    lastDay = c.day
                }
                lines.append("・\(c.staffName)：\(c.before.isEmpty ? "なし" : c.before) → \(c.after.isEmpty ? "なし" : c.after)")
            }
        }
        lines.append("")
        lines.append("最新のシフト表（PDF）を確認してください。")
        return lines.joined(separator: "\n")
    }
}

// MARK: - 希望休の文章を読む（LINE で届いた「10/5、12日、20〜22日 休み希望」など）

enum OffRequestParser {
    /// 文章から日付を取り出す。月が書いていない日は month の月（その前に月が書いてあればその月）
    static func parse(_ text: String, month: MonthKey) -> [DayKey] {
        var s = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        for (a, b) in [("〜", "~"), ("～", "~"), ("−", "-"), ("―", "-"), ("から", "~")] { s = s.replacingOccurrences(of: a, with: b) }
        // 時刻（9:00）や年（2026年・2026/）は日付と間違えないよう先に消す
        for pattern in [#"\d{1,2}:\d{2}"#, #"\d{4}\s*[年/]"#] {
            s = s.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        guard let re = try? NSRegularExpression(pattern: #"(?<!\d)(?:(\d{1,2})\s*(?:/|月)\s*)?(\d{1,2})(?!\d)\s*日?"#) else { return [] }
        let ns = s as NSString
        var current = month
        var result: [DayKey] = []
        var prev: (day: DayKey, end: Int)?
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            if m.range(at: 1).location != NSNotFound, let mo = Int(ns.substring(with: m.range(at: 1))), (1...12).contains(mo) {
                current = resolveYear(mo, near: month)
            }
            guard let d = Int(ns.substring(with: m.range(at: 2))), d >= 1, d <= current.days.count else { prev = nil; continue }
            let day = DayKey(current.year, current.month, d)
            // 前の日付との間が「~」「-」だけなら、その間を全部
            if let p = prev {
                let between = ns.substring(with: NSRange(location: p.end, length: m.range.location - p.end))
                    .trimmingCharacters(in: .whitespaces)
                if between == "~" || between == "-", p.day < day {
                    var x = p.day.adding(days: 1)
                    while x < day, result.count < 400 { result.append(x); x = x.adding(days: 1) }
                }
            }
            result.append(day)
            prev = (day, m.range.location + m.range.length)
        }
        var seen = Set<DayKey>()
        return result.filter { seen.insert($0).inserted }.sorted()
    }

    /// 月だけ書いてあるとき、表示している月にいちばん近い年にする（12月に「1/5」なら翌年）
    private static func resolveYear(_ mo: Int, near base: MonthKey) -> MonthKey {
        let candidates = [MonthKey(base.year - 1, mo), MonthKey(base.year, mo), MonthKey(base.year + 1, mo)]
        func distance(_ m: MonthKey) -> Int { abs((m.year * 12 + m.month) - (base.year * 12 + base.month)) }
        return candidates.min { distance($0) < distance($1) }!
    }
}
