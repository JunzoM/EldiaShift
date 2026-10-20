import Foundation

// MARK: - 日本の祝日（祝日法：2020年以降の規定。春分・秋分は 1980〜2099 年で有効な近似式）
// 表の日付の色分けに使う。特例の祝日（五輪の年など）は対象外。

enum JapaneseHolidays {
    static func holidays(in year: Int) -> [DayKey: String] {
        if let cached = cache.withLock({ $0[year] }) { return cached }
        let made = make(year)
        cache.withLock { $0[year] = made }
        return made
    }

    static func isHoliday(_ d: DayKey) -> Bool { holidays(in: d.year)[d] != nil }

    static func name(_ d: DayKey) -> String? { holidays(in: d.year)[d] }

    private static let cache = Locked<[Int: [DayKey: String]]>([:])

    private static func make(_ y: Int) -> [DayKey: String] {
        let k = Double(y - 1980)
        let vernal = Int((20.8431 + 0.242194 * k - (k / 4).rounded(.down)).rounded(.down))
        let autumnal = Int((23.2488 + 0.242194 * k - (k / 4).rounded(.down)).rounded(.down))
        var list: [(DayKey, String)] = [
            (DayKey(y, 1, 1), "元日"),
            (nthMonday(y, 1, 2), "成人の日"),
            (DayKey(y, 2, 11), "建国記念の日"),
            (DayKey(y, 2, 23), "天皇誕生日"),
            (DayKey(y, 3, vernal), "春分の日"),
            (DayKey(y, 4, 29), "昭和の日"),
            (DayKey(y, 5, 3), "憲法記念日"),
            (DayKey(y, 5, 4), "みどりの日"),
            (DayKey(y, 5, 5), "こどもの日"),
            (nthMonday(y, 7, 3), "海の日"),
            (DayKey(y, 8, 11), "山の日"),
            (nthMonday(y, 9, 3), "敬老の日"),
            (DayKey(y, 9, autumnal), "秋分の日"),
            (nthMonday(y, 10, 2), "スポーツの日"),
            (DayKey(y, 11, 3), "文化の日"),
            (DayKey(y, 11, 23), "勤労感謝の日")
        ]

        // 国民の休日：前日と翌日が祝日で、その日自体は祝日でも日曜でもない日
        var days = Set(list.map(\.0))
        for (d, _) in list {
            let x = d.adding(days: 1)
            if days.contains(d.adding(days: 2)), !days.contains(x), x.weekday != 0 {
                list.append((x, "国民の休日"))
                days.insert(x)
            }
        }

        // 振替休日：日曜の祝日のあと、最初の祝日でない日
        for (d, _) in list where d.weekday == 0 {
            var x = d.adding(days: 1)
            while days.contains(x) { x = x.adding(days: 1) }
            list.append((x, "振替休日"))
            days.insert(x)
        }

        return Dictionary(list, uniquingKeysWith: { first, _ in first })
    }

    /// その月の第 n 月曜日
    private static func nthMonday(_ y: Int, _ m: Int, _ n: Int) -> DayKey {
        let first = DayKey(y, m, 1)
        let toMonday = (8 - first.weekday) % 7   // weekday: 0＝日 … 1＝月
        return first.adding(days: toMonday + 7 * (n - 1))
    }
}

final class Locked<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) { self.value = value }

    func withLock<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
