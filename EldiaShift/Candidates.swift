import Foundation

// MARK: - 足りない時間に入れられる人

struct ShortageCandidate: Identifiable, Sendable {
    var member: StaffMember
    /// 入れるひな形（足りない時間をいちばん多く埋めるもの）
    var block: TimeBlock
    /// 埋まる「人×時間」
    var covers: Int
    /// 今月の実働（入れる前）
    var monthHours: Double
    /// 入れたときに出る注意（連勤・間隔など）
    var issues: [LaborIssue]
    var otherDepartment: Bool
    var id: String { member.id }

    var entry: CellEntry { CellEntry(inTime: block.inTime, outTime: block.outTime, blockID: block.id, isOff: false) }
}

/// 人が足りない1日・1部門（Duo の見開きの左のページの1行）
struct ShortageItem: Identifiable, Equatable, Sendable {
    var department: Department
    var day: DayKey
    /// 足りない時台（0〜23）
    var hours: [Int]
    /// 足りない人×時間
    var short: Int
    var id: String { "\(department.id)-\(day)" }
    var target: ShortageTarget { ShortageTarget(department: department, day: day) }

    /// 続いている時台をまとめた時間帯（例：[9, 10, 21] → "9〜11時・21〜22時"）
    var hoursLabel: String {
        var ranges: [(Int, Int)] = []
        for h in hours {
            if let last = ranges.last, last.1 == h { ranges[ranges.count - 1].1 = h + 1 } else { ranges.append((h, h + 1)) }
        }
        return ranges.map { "\($0.0)〜\($0.1)時" }.joined(separator: "・")
    }
}

enum ShortageFinder {
    /// その日・その部門で人が足りない時台
    static func shortHours(_ book: ShiftBook, department: String, members: [StaffMember], on d: DayKey) -> [Int] {
        (0..<24).filter { h in
            guard let need = book.staffing.need(department, on: d, hour: h) else { return false }
            return Headcount.working(members, on: d, hour: h, in: book) < need
        }
    }

    /// ひな形がその時台にかかっているか（Headcount と同じ数え方）
    static func covers(_ b: TimeBlock, hour h: Int) -> Bool {
        guard let s = b.inMinutes, let e = b.outMinutes else { return false }
        let hs = h * 60, he = (h + 1) * 60
        return e > s ? (s < he && e > hs) : (s < he || e > hs)
    }

    /// 入れられる人（その日に勤務が無く、退職しておらず、有休・希望休でない人）
    /// 並び：注意が出ない人 → たくさん埋まる人 → 今月の時間が少ない人
    static func candidates(_ book: ShiftBook, department: String, on d: DayKey, includeOthers: Bool) -> [ShortageCandidate] {
        let month = MonthKey(d)
        let groups = book.staffByDepartment(visibleIn: month)
        let visible = groups.flatMap(\.members)
        // 表と同じ並び（掛け持ちでほかの店舗から入る人も、その部門の人として数える）
        let deptMembers = groups.first { $0.department.id == department }?.members ?? []
        let deptIDs = Set(deptMembers.map(\.id))
        let short = shortHours(book, department: department, members: deptMembers, on: d)
        guard !short.isEmpty else { return [] }

        let pool = includeOthers ? visible : deptMembers
        var out: [ShortageCandidate] = []
        for m in pool where !m.hasLeft(on: d) && !m.requestsOff(d) {
            let r = Schedule.resolve(m, on: d, in: book)
            if let r, !r.isOff { continue }                          // もう勤務が入っている
            if r?.blockID == PaidLeave.blockID { continue }          // 有休の日は呼ばない
            let blocks = (m.timeBlocks + book.templates).filter { !$0.isOff && $0.inMinutes != nil && $0.outMinutes != nil }
            let scored = blocks.map { b in (b, short.filter { covers(b, hour: $0) }.count) }.filter { $0.1 > 0 }
            guard let best = scored.max(by: { a, b in
                a.1 != b.1 ? a.1 < b.1 : length(a.0) > length(b.0)   // 同じだけ埋まるなら短いほう
            }) else { continue }

            // 入れたらどうなるかを試して、注意を調べる（その日と翌日：翌日の早番との間隔）
            var trial = book
            trial.cells[CellKey(staffID: m.id, day: d)] = CellEntry(inTime: best.0.inTime, outTime: best.0.outTime,
                                                                   blockID: best.0.id, isOff: false, storeID: book.scopeStoreID)
            let found = LaborCheck.issues(trial, members: [m], days: [d, d.adding(days: 1)])
            let issues = (found[CellKey(staffID: m.id, day: d)] ?? []) + (found[CellKey(staffID: m.id, day: d.adding(days: 1))] ?? [])
                .filter { if case .interval = $0 { return true } else { return false } }
            out.append(ShortageCandidate(member: m, block: best.0, covers: best.1,
                                         monthHours: MonthSummary.of(m, month: month, in: book).hours,
                                         issues: issues, otherDepartment: !deptIDs.contains(m.id)))
        }
        return out.sorted { a, b in
            if a.issues.isEmpty != b.issues.isEmpty { return a.issues.isEmpty }
            if a.otherDepartment != b.otherDepartment { return !a.otherDepartment }
            if a.covers != b.covers { return a.covers > b.covers }
            return a.monthHours < b.monthHours
        }
    }

    /// 人が足りない日・部門の一覧（Duo の見開きの「人が足りない」）。日付の順、同じ日は部門の並び順
    static func items(_ book: ShiftBook, days: [DayKey]) -> [ShortageItem] {
        guard !book.staffing.isEmpty, let first = days.first else { return [] }
        let groups = book.staffByDepartment(visibleIn: MonthKey(first)).filter { book.staffing.hasPlan(for: $0.department.id) }
        var out: [ShortageItem] = []
        for d in days {
            for g in groups {
                let members = g.members.filter { !$0.hasLeft(on: d) }
                var hours: [Int] = []
                var short = 0
                for h in 0..<24 {
                    guard let need = book.staffing.need(g.department.id, on: d, hour: h) else { continue }
                    let n = Headcount.working(members, on: d, hour: h, in: book)
                    if n < need { hours.append(h); short += need - n }
                }
                if !hours.isEmpty { out.append(ShortageItem(department: g.department, day: d, hours: hours, short: short)) }
            }
        }
        return out
    }

    private static func length(_ b: TimeBlock) -> Int {
        guard let s = b.inMinutes, let e = b.outMinutes else { return .max }
        return e > s ? e - s : e + 1440 - s
    }
}
