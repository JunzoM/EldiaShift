import Foundation

// MARK: - パターンの確認（HOTEL SHIFT の「適用前プレビュー」「期間限定の重なり検出」をこのアプリの形に合わせて移植）
// このアプリのパターンは書き込まず、表示のたびに決まる。そのため「パターンを変えると、どの日の表が変わるか」を保存前に見せる。

enum PatternChecks {
    /// 同じ人のほかの期間限定パターンで、日付が重なるもの（重なると、先に作った方だけが使われる）
    static func overlapping(_ pattern: PeriodPattern, in others: [PeriodPattern]) -> [PeriodPattern] {
        guard let s = DayKey(pattern.startDate ?? ""), let e = DayKey(pattern.endDate ?? ""), s <= e else { return [] }
        return others.filter { o in
            guard o.id != pattern.id, let os = DayKey(o.startDate ?? ""), let oe = DayKey(o.endDate ?? ""), os <= oe else { return false }
            return os <= e && s <= oe
        }
    }

    /// パターンを変えたときに表が変わる日
    struct Preview: Equatable, Sendable {
        /// 今日以降で変わる日
        var upcoming: [DayKey] = []
        /// 今日より前で変わる日（過去の表・集計が変わる）
        var past: [DayKey] = []

        var isEmpty: Bool { upcoming.isEmpty && past.isEmpty }

        /// 確認画面に出す文章
        var message: String {
            var lines: [String] = []
            if !upcoming.isEmpty { lines.append("今日以降 \(upcoming.count)日（\(Self.sample(upcoming))）") }
            if !past.isEmpty { lines.append("過去 \(past.count)日（\(Self.sample(past))）") }
            var text = "この変更で、表の自動で入る勤務が変わります。\n" + lines.joined(separator: "\n")
            text += "\n手で入れた日は変わりません。"
            if !past.isEmpty {
                text += "\n過去の表と集計も変わります。過去を変えたくないときは、週間パターンに「適用開始日」を入れてください。"
            }
            return text
        }

        private static func sample(_ days: [DayKey]) -> String {
            let head = days.prefix(3).map { "\($0.month)/\($0.day)" }.joined(separator: "・")
            return days.count > 3 ? head + " など" : head
        }
    }

    /// 前と後のスタッフ設定で、自動で入る勤務を比べる（手で入れた日・退職後は比べない）
    /// 見る範囲は、今日の3か月前の月初から6か月後の月末まで
    static func preview(old: StaffMember, new: StaffMember, book: ShiftBook, today: DayKey) -> Preview {
        let first = MonthKey(today).adding(months: -3).days.first ?? today
        let last = MonthKey(today).adding(months: 6).days.last ?? today
        var out = Preview()
        var d = first
        while d <= last {
            defer { d = d.adding(days: 1) }
            if book.cells[CellKey(staffID: new.id, day: d)] != nil { continue }
            if old.hasLeft(on: d) && new.hasLeft(on: d) { continue }
            let a = old.hasLeft(on: d) ? nil : Schedule.automatic(old, on: d, in: book)
            let b = new.hasLeft(on: d) ? nil : Schedule.automatic(new, on: d, in: book)
            guard !same(a, b) else { continue }
            if d >= today { out.upcoming.append(d) } else { out.past.append(d) }
        }
        return out
    }

    private static func same(_ a: ResolvedShift?, _ b: ResolvedShift?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return x.isOff == y.isOff && x.inTime == y.inTime && x.outTime == y.outTime && x.blockID == y.blockID
        default: return false
        }
    }
}
