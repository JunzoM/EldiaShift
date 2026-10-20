import Foundation

/// バックアップファイル（JSON）の読み書き。
/// 旧シフト表（PC版）の「バックアップを保存」で作ったファイルと同じ形なので、
/// PC版のファイルをそのまま取り込め、このアプリで書き出したファイルも PC版で読み込める。
///
/// 形：{ "staff": [...], "globalTemplates": [...], "cellData": { "スタッフID|YYYY-MM-DD": {...} },
///       "departments": [...] ← このアプリで足した項目（PC版は読み飛ばす） }
enum BackupFile {
    enum Failure: LocalizedError {
        case notJSON
        case notShiftData
        case badField(String)

        var errorDescription: String? {
            switch self {
            case .notJSON: "ファイルを読み取れませんでした。シフト表のバックアップ（.json）を選んでください。"
            case .notShiftData: "シフト表のバックアップではないようです。"
            case .badField(let name): "「\(name)」の形式が正しくありません。"
            }
        }
    }

    /// 取り込んだ結果（件数は確認画面に出す）
    struct Summary: Equatable, Sendable {
        var staff: Int
        var templates: Int
        var cells: Int
        var firstDay: DayKey?
        var lastDay: DayKey?
        /// 読めずに飛ばした入力の数
        var skipped: Int
    }

    // MARK: 読み込み

    static func read(_ data: Data) throws -> (ShiftBook, Summary) {
        guard let any = try? JSONSerialization.jsonObject(with: data),
              let root = any as? [String: Any] else { throw Failure.notJSON }
        let staffRaw = root["staff"]
        let cellsRaw = root["cellData"]
        guard staffRaw is [Any] || cellsRaw is [String: Any] else { throw Failure.notShiftData }
        if let staffRaw, !(staffRaw is [Any]) { throw Failure.badField("スタッフ") }
        if let cellsRaw, !(cellsRaw is [String: Any]) { throw Failure.badField("シフト") }

        var skipped = 0
        var book = ShiftBook()

        // 時間のひな形（休みのひな形が無ければ足す）
        let templates = (root["globalTemplates"] as? [Any] ?? []).compactMap { block($0) }
        book.templates = templates
        for off in defaultOffBlocks where !book.templates.contains(where: { $0.id == off.id }) {
            book.templates.append(off)
        }

        // スタッフ
        for raw in staffRaw as? [Any] ?? [] {
            if let m = member(raw) { book.staff.append(m) } else { skipped += 1 }
        }

        // 部門：このアプリで書き出したものは一覧を持っている。PC版のファイルはスタッフの部門から作る
        if let list = root["departments"] as? [Any] {
            book.departments = list.enumerated().compactMap { (i, raw) -> Department? in
                guard let d = raw as? [String: Any], let id = string(d["id"]), !id.isEmpty else { return nil }
                return Department(id: id, name: string(d["label"]) ?? string(d["name"]) ?? id,
                                  colorIndex: Palette.index(int(d["colorIdx"]) ?? 0),
                                  sortOrder: int(d["sortOrder"]) ?? i)
            }
        }
        let known = Set(book.departments.map(\.id))
        let missing = orderedUnique(book.staff.map(\.departmentID)).filter { !known.contains($0) && !$0.isEmpty }
        for id in missing.sorted(by: { legacyOrder($0) < legacyOrder($1) }) {
            let legacy = legacyDepartments[id]
            book.departments.append(Department(id: id, name: legacy?.name ?? id, colorIndex: legacy?.color ?? 8,
                                               sortOrder: (book.departments.map(\.sortOrder).max() ?? -1) + 1))
        }

        // 1人×1日の入力
        for (key, raw) in cellsRaw as? [String: Any] ?? [:] {
            guard let k = CellKey(legacy: key), let c = raw as? [String: Any] else { skipped += 1; continue }
            let isOff = bool(c["isOff"]) ?? false
            let inTime = string(c["inTime"]) ?? ""
            let outTime = string(c["outTime"]) ?? ""
            let blockID = string(c["blockId"]).flatMap { $0.isEmpty ? nil : $0 }
            if !isOff, ClockTime.parse(inTime) == nil || ClockTime.parse(outTime) == nil, blockID == nil {
                skipped += 1
                continue
            }
            book.cells[k] = CellEntry(inTime: normalized(inTime), outTime: normalized(outTime), blockID: blockID, isOff: isOff)
        }

        let days = book.cells.keys.map(\.day)
        let summary = Summary(staff: book.staff.count, templates: templates.count, cells: book.cells.count,
                              firstDay: days.min(), lastDay: days.max(), skipped: skipped)
        return (book, summary)
    }

    // MARK: 書き出し

    static func write(_ book: ShiftBook) throws -> Data {
        let staff: [[String: Any]] = book.staff.map { s in
            [
                "id": Int(s.id).map { $0 as Any } ?? s.id,
                "no": s.number,
                "name": s.name,
                "deptId": s.departmentID,
                "active": s.active,
                "joinDate": s.joinDate,
                "leaveDate": s.leaveDate,
                "timeBlocks": s.timeBlocks.map(json),
                "patterns": s.patterns.map { p -> [String: Any] in
                    var o: [String: Any] = ["id": p.id, "label": p.label, "colorIdx": p.colorIndex,
                                            "days": p.days.map { $0.map { $0 as Any } ?? NSNull() }]
                    if let f = p.activeFrom { o["activeFrom"] = f }
                    return o
                },
                "activePatternId": s.activePatternID.map { $0 as Any } ?? NSNull(),
                "periodPatterns": s.periodPatterns.map { p -> [String: Any] in
                    ["id": p.id, "label": p.label, "colorIdx": p.colorIndex,
                     "startDate": p.startDate ?? "", "endDate": p.endDate ?? "", "days": p.days] as [String: Any]
                }
            ]
        }
        var cells: [String: Any] = [:]
        for (k, c) in book.cells {
            cells[k.description] = ["inTime": c.inTime, "outTime": c.outTime,
                                    "blockId": c.blockID.map { $0 as Any } ?? NSNull(),
                                    "isOff": c.isOff, "auto": false] as [String: Any]
        }
        let root: [String: Any] = [
            "staff": staff,
            "globalTemplates": book.templates.map(json),
            "cellData": cells,
            "departments": book.departments.sorted { $0.sortOrder < $1.sortOrder }.map {
                ["id": $0.id, "label": $0.name, "colorIdx": $0.colorIndex, "sortOrder": $0.sortOrder] as [String: Any]
            }
        ]
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: 初期値

    /// 休みのひな形（初めて使うとき・取り込んだファイルに無いときに足す）
    static let defaultOffBlocks: [TimeBlock] = [
        TimeBlock(id: "off1", label: "公休", short: "休", inMinutes: nil, outMinutes: nil, colorIndex: 4),
        TimeBlock(id: "off2", label: "有休", short: "有", inMinutes: nil, outMinutes: nil, colorIndex: 3),
        TimeBlock(id: "off3", label: "欠勤", short: "欠", inMinutes: nil, outMinutes: nil, colorIndex: 7)
    ]

    /// PC版の部門（PC版のファイルには部門の名前が入っていないため、取り込むときだけ使う）
    private static let legacyDepartments: [String: (name: String, color: Int, order: Int)] = [
        "make": ("メイク", 7, 0),
        "kitchen": ("キッチン", 2, 1),
        "front": ("フロント", 0, 2)
    ]

    private static func legacyOrder(_ id: String) -> Int { legacyDepartments[id]?.order ?? 100 }

    // MARK: 部品

    private static func member(_ raw: Any) -> StaffMember? {
        guard let s = raw as? [String: Any], let id = string(s["id"]), !id.isEmpty else { return nil }
        let name = (string(s["name"]) ?? "").trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        let patterns: [WeekPattern] = (s["patterns"] as? [Any] ?? []).compactMap { raw -> WeekPattern? in
            guard let p = raw as? [String: Any], let pid = string(p["id"]) else { return nil }
            var days = (p["days"] as? [Any] ?? []).map { string($0).flatMap { $0.isEmpty ? nil : $0 } }
            if days.count < 7 { days += Array(repeating: nil, count: 7 - days.count) }
            let from = string(p["activeFrom"]).flatMap { $0.isEmpty ? nil : $0 }
            return WeekPattern(id: pid, label: string(p["label"]) ?? "", colorIndex: Palette.index(int(p["colorIdx"]) ?? 0),
                               days: Array(days.prefix(7)), activeFrom: from)
        }
        let periods: [PeriodPattern] = (s["periodPatterns"] as? [Any] ?? []).compactMap { raw -> PeriodPattern? in
            guard let p = raw as? [String: Any], let pid = string(p["id"]) else { return nil }
            var days: [String: String] = [:]
            for (k, v) in p["days"] as? [String: Any] ?? [:] {
                if let b = string(v), !b.isEmpty, let d = DayKey(k) { days[d.description] = b }
            }
            return PeriodPattern(id: pid, label: string(p["label"]) ?? "", colorIndex: Palette.index(int(p["colorIdx"]) ?? 0),
                                 startDate: string(p["startDate"]).flatMap { DayKey($0)?.description },
                                 endDate: string(p["endDate"]).flatMap { DayKey($0)?.description },
                                 days: days)
        }
        return StaffMember(
            id: id,
            number: int(s["no"]) ?? 0,
            name: name,
            departmentID: string(s["deptId"]) ?? "",
            active: bool(s["active"]) ?? true,
            joinDate: string(s["joinDate"]).flatMap { DayKey($0)?.description } ?? "",
            leaveDate: string(s["leaveDate"]).flatMap { DayKey($0)?.description } ?? "",
            timeBlocks: (s["timeBlocks"] as? [Any] ?? []).compactMap { block($0) },
            patterns: patterns,
            activePatternID: string(s["activePatternId"]).flatMap { $0.isEmpty ? nil : $0 },
            periodPatterns: periods
        )
    }

    private static func block(_ raw: Any) -> TimeBlock? {
        guard let b = raw as? [String: Any], let id = string(b["id"]), !id.isEmpty else { return nil }
        func minutes(_ h: String, _ m: String) -> Int? {
            guard let hh = int(b[h]) else { return nil }
            return min(1440, max(0, hh * 60 + (int(b[m]) ?? 0)))
        }
        let label = string(b["label"]) ?? ""
        return TimeBlock(id: id, label: label, short: string(b["short"]) ?? String(label.prefix(2)),
                         inMinutes: minutes("inH", "inM"), outMinutes: minutes("outH", "outM"),
                         colorIndex: Palette.index(int(b["colorIdx"]) ?? 0))
    }

    private static func json(_ b: TimeBlock) -> [String: Any] {
        func part(_ v: Int?, _ div: Bool) -> Any { v.map { (div ? $0 / 60 : $0 % 60) as Any } ?? NSNull() }
        return ["id": b.id, "label": b.label, "short": b.short, "colorIdx": b.colorIndex,
                "inH": part(b.inMinutes, true), "inM": part(b.inMinutes, false),
                "outH": part(b.outMinutes, true), "outM": part(b.outMinutes, false)]
    }

    private static func normalized(_ t: String) -> String { ClockTime.parse(t).map(ClockTime.format) ?? "" }

    private static func string(_ v: Any?) -> String? {
        switch v {
        case let s as String: s
        case let n as NSNumber where CFGetTypeID(n) != CFBooleanGetTypeID(): n.stringValue
        default: nil
        }
    }

    private static func int(_ v: Any?) -> Int? {
        switch v {
        case let n as NSNumber: n.intValue
        case let s as String: Int(s)
        default: nil
        }
    }

    private static func bool(_ v: Any?) -> Bool? {
        switch v {
        case let n as NSNumber: n.boolValue
        case let s as String: s == "true" ? true : s == "false" ? false : nil
        default: nil
        }
    }

    private static func orderedUnique(_ xs: [String]) -> [String] {
        var seen = Set<String>()
        return xs.filter { seen.insert($0).inserted }
    }
}
