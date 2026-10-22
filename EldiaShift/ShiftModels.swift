import Foundation

// MARK: - シフト表のデータ（画面・計算で使う形）
// 保存は Core Data（ShiftDatabase）。読み込むとこの形になり、書き出し（バックアップ）もこの形から作る。
// 旧シフト表（PC版）のバックアップと同じ項目を持つので、行き来できる。

/// 部門（例：調理・ホール）。並び順の小さい方が上
struct Department: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var name: String
    var colorIndex: Int
    var sortOrder: Int
}

/// 時間のひな形（出勤〜退勤）。inMinutes が nil のものは「休み」
struct TimeBlock: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var label: String
    var short: String
    /// 0:00 からの分（0〜1440）。休みは nil
    var inMinutes: Int?
    var outMinutes: Int?
    var colorIndex: Int
    /// このひな形の休憩（分）。nil は「休憩の決まり」（設定）に従う
    var breakMinutes: Int? = nil

    var isOff: Bool { inMinutes == nil || outMinutes == nil }
    var inTime: String { inMinutes.map(ClockTime.format) ?? "" }
    var outTime: String { outMinutes.map(ClockTime.format) ?? "" }
}

/// 週ごとのくり返し（days[0]＝日曜 … days[6]＝土曜。値は TimeBlock の id。nil は空き）
struct WeekPattern: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var label: String
    var colorIndex: Int
    var days: [String?]
    /// この日（YYYY-MM-DD）から使う。nil はいつでも
    var activeFrom: String?
}

/// 期間を決めて日ごとに指定する予定（days は「YYYY-MM-DD → TimeBlock の id」）
struct PeriodPattern: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var label: String
    var colorIndex: Int
    var startDate: String?
    var endDate: String?
    var days: [String: String]
}

/// スタッフ
struct StaffMember: Identifiable, Hashable, Codable, Sendable {
    var id: String
    /// 部門内の並び順
    var number: Int
    var name: String
    var departmentID: String
    var active: Bool
    var joinDate: String
    var leaveDate: String
    /// この人専用の時間のひな形
    var timeBlocks: [TimeBlock]
    var patterns: [WeekPattern]
    var activePatternID: String?
    var periodPatterns: [PeriodPattern]
    /// 希望休の日（"yyyy-MM-dd"、日付順）
    var offRequests: [String] = []

    func requestsOff(_ d: DayKey) -> Bool { offRequests.contains(d.description) }
}

/// 1人×1日の入力（手で決めたもの）
struct CellEntry: Hashable, Codable, Sendable {
    var inTime: String
    var outTime: String
    var blockID: String?
    var isOff: Bool
}

/// 1人×1日を表すキー
struct CellKey: Hashable, Sendable, CustomStringConvertible {
    var staffID: String
    var day: DayKey

    /// 旧シフト表の書き方「スタッフID|YYYY-MM-DD」
    var description: String { "\(staffID)|\(day)" }

    init(staffID: String, day: DayKey) {
        self.staffID = staffID
        self.day = day
    }

    init?(legacy: String) {
        let parts = legacy.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, let d = DayKey(parts[1]) else { return nil }
        self.init(staffID: parts[0], day: d)
    }
}

/// シフト表まるごと
struct ShiftBook: Sendable, Equatable {
    var departments: [Department] = []
    /// 全員が使える時間のひな形（休みも含む）
    var templates: [TimeBlock] = []
    var staff: [StaffMember] = []
    var cells: [CellKey: CellEntry] = [:]
    /// 休憩の決まり（実働の計算に使う。会社ごとに設定で変えられる）
    var breakRules: BreakRules = .pcDefault
    /// 適正人員（部門ごと・時間帯ごとの必要人数）
    var staffing = StaffingPlan()
    /// 労務の注意（連勤・勤務間隔・週の時間・有休5日）
    var labor = LaborRules()
    /// スタッフに公開した内容（変更点を出すため。月ごと）
    var published: [PublishedMonth] = []

    /// まだ何も作っていない（スタッフ・部門・ひな形・シフトのどれも無い）
    var isEmpty: Bool { staff.isEmpty && cells.isEmpty && departments.isEmpty && templates.isEmpty }

    func block(_ id: String?, for member: StaffMember) -> TimeBlock? {
        guard let id, !id.isEmpty else { return nil }
        return member.timeBlocks.first { $0.id == id } ?? templates.first { $0.id == id }
    }

    /// 部門の並び順に、部門ごとのスタッフ（番号順）
    func staffByDepartment(visibleIn month: MonthKey, includeInactive: Bool = false) -> [DepartmentGroup] {
        let visible = staff.filter { includeInactive || $0.isVisible(in: month) }
        var result: [DepartmentGroup] = departments.sorted { $0.sortOrder < $1.sortOrder }.compactMap { dept -> DepartmentGroup? in
            let members = visible.filter { $0.departmentID == dept.id }.sorted(by: StaffMember.order)
            return members.isEmpty ? nil : DepartmentGroup(department: dept, members: members)
        }
        // 部門が見つからない人は最後に「その他」としてまとめる
        let known = Set(departments.map(\.id))
        let orphans = visible.filter { !known.contains($0.departmentID) }.sorted(by: StaffMember.order)
        if !orphans.isEmpty {
            result.append(DepartmentGroup(department: Department(id: "", name: "その他", colorIndex: 8, sortOrder: .max),
                                          members: orphans))
        }
        return result
    }
}

struct DepartmentGroup: Identifiable, Sendable {
    var department: Department
    var members: [StaffMember]
    var id: String { department.id }
}

extension StaffMember {
    static func order(_ a: StaffMember, _ b: StaffMember) -> Bool {
        (a.number, a.name) < (b.number, b.name)
    }

    /// その月の表に出すか（旧シフト表と同じ：退職日があれば退職月まで、なければ在籍中なら出す）
    func isVisible(in month: MonthKey) -> Bool {
        guard let leave = DayKey(leaveDate) else { return active }
        return MonthKey(leave.year, leave.month) >= month
    }

    /// 退職日より後の日か
    func hasLeft(on day: DayKey) -> Bool {
        guard let leave = DayKey(leaveDate) else { return false }
        return day > leave
    }
}

// MARK: - 日付（端末の暦。時刻は持たない）

struct DayKey: Hashable, Comparable, Sendable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    init(_ year: Int, _ month: Int, _ day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// "YYYY-MM-DD"（"YYYY/M/D"・"YYYYMMDD" も受け付ける）
    init?(_ text: String) {
        let s = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let parts: [Int]
        if s.count == 8, s.allSatisfy(\.isNumber) {
            parts = [Int(s.prefix(4))!, Int(s.dropFirst(4).prefix(2))!, Int(s.suffix(2))!]
        } else {
            parts = s.split(separator: "-").compactMap { Int($0) }
        }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]), parts[0] > 1900 else { return nil }
        self.init(parts[0], parts[1], parts[2])
    }

    init(_ date: Date, calendar: Calendar = .shift) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(c.year!, c.month!, c.day!)
    }

    var date: Date { Calendar.shift.date(from: DateComponents(year: year, month: month, day: day))! }

    /// 0＝日曜 … 6＝土曜
    var weekday: Int { Calendar.shift.component(.weekday, from: date) - 1 }

    func adding(days n: Int) -> DayKey { DayKey(Calendar.shift.date(byAdding: .day, value: n, to: date)!) }

    var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    static func < (a: DayKey, b: DayKey) -> Bool { (a.year, a.month, a.day) < (b.year, b.month, b.day) }

    static var today: DayKey { DayKey(Date()) }
}

struct MonthKey: Hashable, Comparable, Sendable, CustomStringConvertible {
    let year: Int
    let month: Int

    init(_ year: Int, _ month: Int) {
        self.year = year
        self.month = month
    }

    init(_ day: DayKey) { self.init(day.year, day.month) }

    var days: [DayKey] {
        let first = DayKey(year, month, 1)
        let n = Calendar.shift.range(of: .day, in: .month, for: first.date)!.count
        return (1...n).map { DayKey(year, month, $0) }
    }

    func adding(months n: Int) -> MonthKey {
        let total = year * 12 + (month - 1) + n
        return MonthKey(total / 12, total % 12 + 1)
    }

    var description: String { "\(year)年\(month)月" }

    static func < (a: MonthKey, b: MonthKey) -> Bool { (a.year, a.month) < (b.year, b.month) }

    static var current: MonthKey { MonthKey(DayKey.today) }
}

extension Calendar {
    /// シフト表で使う暦（グレゴリオ暦・端末の時間帯）
    static let shift: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        c.locale = Locale(identifier: "ja_JP")
        return c
    }()
}

// MARK: - 時刻（"HH:mm" ⇔ 分）

enum ClockTime {
    static func format(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    /// "9:00"・"09:00"・"24:00" を分に。読めなければ nil
    static func parse(_ text: String) -> Int? {
        let p = text.split(separator: ":").map(String.init)
        guard p.count == 2, let h = Int(p[0]), let m = Int(p[1]), (0...24).contains(h), (0..<60).contains(m) else { return nil }
        let v = h * 60 + m
        return v <= 1440 ? v : nil
    }

    /// 勤務時間（時間）。退勤が出勤以前なら日をまたいだとみなす
    static func hours(from start: Int, to end: Int) -> Double {
        var d = end - start
        if d <= 0 { d += 1440 }
        return Double(d) / 60
    }
}

// MARK: - 色（旧シフト表と同じ10色）

enum Palette {
    /// (文字・線の色, 背景の色)
    static let colors: [(fg: UInt32, bg: UInt32)] = [
        (0x1D4ED8, 0xDBEAFE), // 0 青
        (0x6D28D9, 0xEDE9FE), // 1 紫
        (0x0F766E, 0xCCFBF1), // 2 青緑
        (0xB45309, 0xFEF3C7), // 3 黄土
        (0xDC2626, 0xFEE2E2), // 4 赤
        (0x059669, 0xD1FAE5), // 5 緑
        (0x0369A1, 0xE0F2FE), // 6 空
        (0xBE185D, 0xFCE7F3), // 7 桃
        (0x334155, 0xF1F5F9), // 8 灰
        (0x7C3AED, 0xF5F3FF)  // 9 菫
    ]

    static func index(_ i: Int) -> Int { colors.indices.contains(i) ? i : 0 }
}

// MARK: - 休憩の決まり

/// 勤務の長さに応じて引く休憩。例：4.5時間以上は30分、6.5時間以上は60分
struct BreakRules: Codable, Equatable, Sendable {
    struct Tier: Codable, Equatable, Sendable, Identifiable {
        var id = UUID()
        /// この長さ（分）から
        var afterMinutes: Int
        /// 引く休憩（分）
        var breakMinutes: Int

        enum CodingKeys: String, CodingKey { case afterMinutes, breakMinutes }
    }

    var tiers: [Tier]
    /// true：「以上」で数える（4.5時間ちょうどでも引く）／false：「を超える」で数える（労働基準法の書き方）
    var inclusive: Bool

    /// PC版と同じ：4.5時間以上は30分、6.5時間以上は60分
    static let pcDefault = BreakRules(tiers: [Tier(afterMinutes: 270, breakMinutes: 30), Tier(afterMinutes: 390, breakMinutes: 60)],
                                      inclusive: true)
    /// 労働基準法の最低限：6時間を超えたら45分、8時間を超えたら60分
    static let laborStandard = BreakRules(tiers: [Tier(afterMinutes: 360, breakMinutes: 45), Tier(afterMinutes: 480, breakMinutes: 60)],
                                          inclusive: false)
    /// 休憩を引かない（拘束時間＝実働）
    static let none = BreakRules(tiers: [], inclusive: true)

    /// 勤務の長さ（分）に対して引く休憩（分）
    func breakMinutes(forGross gross: Int) -> Int {
        tiers.filter { inclusive ? gross >= $0.afterMinutes : gross > $0.afterMinutes }
            .map(\.breakMinutes).max() ?? 0
    }

    /// 実働（時間）。override はひな形ごとの休憩（分）
    func netHours(gross: Double, override: Int? = nil) -> Double {
        let g = Int((gross * 60).rounded())
        let b = override ?? breakMinutes(forGross: g)
        return Double(max(0, g - b)) / 60
    }

    /// 決まりを文章で（例：「4時間30分以上は30分、6時間30分以上は60分」）
    var summary: String {
        if tiers.isEmpty { return "休憩を引かない" }
        let word = inclusive ? "以上は" : "を超えたら"
        return tiers.sorted { $0.afterMinutes < $1.afterMinutes }
            .map { "\(Self.duration($0.afterMinutes))\(word)\($0.breakMinutes)分" }
            .joined(separator: "、")
    }

    static func duration(_ m: Int) -> String {
        m % 60 == 0 ? "\(m / 60)時間" : "\(m / 60)時間\(m % 60)分"
    }

    static func == (a: BreakRules, b: BreakRules) -> Bool {
        a.inclusive == b.inclusive
            && a.tiers.map { [$0.afterMinutes, $0.breakMinutes] } == b.tiers.map { [$0.afterMinutes, $0.breakMinutes] }
    }
}
