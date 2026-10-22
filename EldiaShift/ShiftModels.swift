import Foundation

// MARK: - シフト表のデータ（画面・計算で使う形）
// 保存は Core Data（ShiftDatabase）。読み込むとこの形になり、書き出し（バックアップ）もこの形から作る。
// 旧シフト表（PC版）のバックアップと同じ項目を持つので、行き来できる。

/// 店舗（例：本店・大阪店）。部門は店舗に属する
struct Store: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var name: String
    var address: String = ""
    var phone: String = ""
    /// 営業時間（例：「24時間」「6:00〜24:00」）
    var hours: String = ""
    var note: String = ""
    /// 表のマスに出す略称（例：「本館」）。空なら店舗名から自動で作る
    var short: String = ""
    /// 店舗を見分ける小さな色の印（Palette の番号）
    var colorIndex: Int = 0
    var sortOrder: Int = 0
    /// 店舗の写真（小さく縮めた JPEG。iCloud 同期・バックアップに入るので数十KBにする）
    var photo: Data? = nil
    /// アプリの中に出す名前「〇〇 SHIFT」の〇〇（空は HOTEL）
    var brandPrefix: String = ""

    /// 「〇〇 SHIFT」の〇〇（空なら HOTEL）
    var displayPrefix: String {
        let t = brandPrefix.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "HOTEL" : t
    }

    /// 店舗をまだ1つも作っていないとき（前の版のデータ）に使う店舗
    static let defaultID = "main"
    static func makeDefault() -> Store { Store(id: defaultID, name: "本店") }

    /// 表のマスに出す短い名前（略称。なければ先頭2文字）
    var shortName: String { short.isEmpty ? String(name.prefix(2)) : short }

    init(id: String, name: String, address: String = "", phone: String = "", hours: String = "",
         note: String = "", short: String = "", colorIndex: Int = 0, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.address = address
        self.phone = phone
        self.hours = hours
        self.note = note
        self.short = short
        self.colorIndex = colorIndex
        self.sortOrder = sortOrder
    }

    /// 項目が足りない記録（あとから足した項目）も読めるように
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        address = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
        phone = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
        hours = try c.decodeIfPresent(String.self, forKey: .hours) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        short = try c.decodeIfPresent(String.self, forKey: .short) ?? ""
        colorIndex = try c.decodeIfPresent(Int.self, forKey: .colorIndex) ?? 0
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        photo = try c.decodeIfPresent(Data.self, forKey: .photo)
        brandPrefix = try c.decodeIfPresent(String.self, forKey: .brandPrefix) ?? ""
    }
}

/// 部門（例：調理・ホール）。並び順の小さい方が上
struct Department: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var name: String
    var colorIndex: Int
    var sortOrder: Int
    /// 属する店舗。空は最初の店舗（前の版のデータ）
    var storeID: String = ""
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
    /// 掛け持ちで入る、ほかの店舗（自分の部門の店舗は含めない）
    var extraStoreIDs: [String] = []

    func requestsOff(_ d: DayKey) -> Bool { offRequests.contains(d.description) }
}

/// 1人×1日の入力（手で決めたもの）
struct CellEntry: Hashable, Codable, Sendable {
    var inTime: String
    var outTime: String
    var blockID: String?
    var isOff: Bool
    /// 勤務する店舗。nil はその人の部門の店舗（掛け持ちでほかの店舗に入る日だけ入れる）
    var storeID: String? = nil
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
    var departments: [Department] = [] { didSet { rebuildIndex() } }
    /// 全員が使える時間のひな形（休みも含む）
    var templates: [TimeBlock] = [] { didSet { rebuildIndex() } }
    var staff: [StaffMember] = []
    var cells: [CellKey: CellEntry] = [:]
    /// 休憩の決まり（実働の計算に使う。会社ごとに設定で変えられる）
    var breakRules: BreakRules = .pcDefault
    /// 適正人員（部門ごと・時間帯ごとの必要人数）
    var staffing = StaffingPlan()
    /// 労務の注意（連勤・勤務間隔・週の時間・有休5日）
    var labor = LaborRules()
    /// スタッフに公開した内容（変更点を出すため。月ごと・店舗ごと）
    var published: [PublishedMonth] = []
    /// 店舗（空なら「本店」1つとして扱う）
    var stores: [Store] = [] { didSet { rebuildIndex() } }
    /// 会社の色（アプリ全体の色。nil は標準の色）
    var brandColor: UInt32? = nil
    /// いま見ている店舗（保存しない。表・集計・人数はこの店舗に絞る。nil はすべて）
    var scopeStoreID: String? = nil

    /// まだ何も作っていない（スタッフ・部門・ひな形・シフトのどれも無い）
    var isEmpty: Bool { staff.isEmpty && cells.isEmpty && departments.isEmpty && templates.isEmpty }

    /// 引き（店舗の並び・部門→店舗・ひな形）。部門・ひな形・店舗が変わったときだけ作り直す。
    /// 1マスごとに配列を探したり並べ替えたりしないため（表を描くたびに何千回も呼ばれる）
    private(set) var index = BookIndex()

    private mutating func rebuildIndex() { index = BookIndex(departments: departments, templates: templates, stores: stores) }

    func block(_ id: String?, for member: StaffMember) -> TimeBlock? {
        guard let id, !id.isEmpty else { return nil }
        if !member.timeBlocks.isEmpty, let b = member.timeBlocks.first(where: { $0.id == id }) { return b }
        return index.templates[id]
    }

    // MARK: 店舗

    /// 店舗の一覧（並び順。作っていなければ「本店」1つ）
    var allStores: [Store] { index.sortedStores }

    /// 表に出す店舗の略称。略称が無ければ、店舗名の共通の頭（例：「ELDIA神戸」）を除いた先頭2文字
    func shortName(of st: Store) -> String {
        if !st.short.isEmpty { return st.short }
        let names = allStores.map(\.name).filter { !$0.isEmpty }
        guard names.count > 1, var common = names.first else { return String(st.name.prefix(2)) }
        for n in names.dropFirst() {
            while !n.hasPrefix(common) { common.removeLast() }
        }
        let rest = st.name.dropFirst(common.count).trimmingCharacters(in: .whitespaces)
        return String((rest.isEmpty ? st.name : rest).prefix(2))
    }

    func store(_ id: String?) -> Store? {
        guard let id else { return nil }
        return allStores.first { $0.id == id }
    }

    /// 部門の店舗（店舗が決まっていない・消した店舗なら最初の店舗）
    func storeID(ofDepartment id: String) -> String {
        index.departmentStore[id] ?? index.sortedStores[0].id
    }

    /// その人の店舗（部門の店舗）
    func homeStoreID(of m: StaffMember) -> String { storeID(ofDepartment: m.departmentID) }

    /// その人が入れる店舗（自分の店舗＋掛け持ち先。並び順）
    func storeIDs(of m: StaffMember) -> [String] {
        let home = homeStoreID(of: m)
        return allStores.map(\.id).filter { $0 == home || m.extraStoreIDs.contains($0) }
    }

    /// その店舗の部門（並び順）。店舗を決めていなければ全部
    func departments(in storeID: String?) -> [Department] {
        let sorted = departments.sorted { $0.sortOrder < $1.sortOrder }
        guard let storeID else { return sorted }
        return sorted.filter { self.storeID(ofDepartment: $0.id) == storeID }
    }

    /// いま見ている店舗の部門
    var scopedDepartments: [Department] { departments(in: scopeStoreID) }

    /// 手で入れたマスの店舗（消した店舗・未指定なら、その人の店舗）
    func storeID(of entry: CellEntry, for m: StaffMember) -> String {
        if let s = entry.storeID, index.storeOrder[s] != nil { return s }
        return homeStoreID(of: m)
    }

    /// 部門の並び順に、部門ごとのスタッフ（番号順）。
    /// 店舗を見ているときは、その店舗の部門だけ。掛け持ちでほかの店舗から入る人は、同じ名前の部門の後ろ
    /// （同じ名前の部門が無ければ「応援」）に並べる
    func staffByDepartment(visibleIn month: MonthKey, includeInactive: Bool = false) -> [DepartmentGroup] {
        let visible = staff.filter { includeInactive || $0.isVisible(in: month) }
        let depts = scopedDepartments
        var result: [DepartmentGroup] = depts.map { dept in
            DepartmentGroup(department: dept,
                            members: visible.filter { $0.departmentID == dept.id }.sorted(by: StaffMember.order))
        }
        let known = Set(departments.map(\.id))
        let first = allStores[0].id
        // 部門が見つからない人は最後に「その他」としてまとめる（最初の店舗に出す）
        var orphans: [StaffMember] = []
        if scopeStoreID == nil || scopeStoreID == first {
            orphans = visible.filter { !known.contains($0.departmentID) }.sorted(by: StaffMember.order)
        }
        // 掛け持ちでこの店舗にも入る人
        var support: [StaffMember] = []
        if let scope = scopeStoreID {
            let helpers = visible.filter { known.contains($0.departmentID) && homeStoreID(of: $0) != scope && $0.extraStoreIDs.contains(scope) }
            for h in helpers.sorted(by: helperOrder) {
                let homeName = departments.first { $0.id == h.departmentID }?.name ?? ""
                if let i = result.firstIndex(where: { $0.department.name == homeName }) {
                    result[i].members.append(h)
                } else {
                    support.append(h)
                }
            }
        }
        result = result.filter { !$0.members.isEmpty }
        if !support.isEmpty {
            result.append(DepartmentGroup(department: Department(id: "support-\(scopeStoreID ?? "")", name: "応援（ほかの店舗から）",
                                                                 colorIndex: 8, sortOrder: .max - 1, storeID: scopeStoreID ?? ""),
                                          members: support))
        }
        if !orphans.isEmpty {
            result.append(DepartmentGroup(department: Department(id: "", name: "その他", colorIndex: 8, sortOrder: .max),
                                          members: orphans))
        }
        return result
    }

    /// 掛け持ちの人の並び：店舗 → 部門 → 番号
    private func helperOrder(_ a: StaffMember, _ b: StaffMember) -> Bool {
        let order = index.storeOrder
        let da = index.departmentOrder[a.departmentID] ?? 0
        let db = index.departmentOrder[b.departmentID] ?? 0
        return (order[homeStoreID(of: a)] ?? 0, da, a.number, a.name) < (order[homeStoreID(of: b)] ?? 0, db, b.number, b.name)
    }
}

/// ShiftBook の引き（部門・ひな形・店舗から作る。中身は ShiftBook と同じことを早く引けるようにしただけ）
struct BookIndex: Sendable, Equatable {
    var sortedStores: [Store] = [Store.makeDefault()]
    /// 店舗ID → 並び順
    var storeOrder: [String: Int] = [Store.defaultID: 0]
    /// 部門ID → 店舗ID（店舗が決まっていない・消した店舗なら最初の店舗）
    var departmentStore: [String: String] = [:]
    var departmentOrder: [String: Int] = [:]
    var templates: [String: TimeBlock] = [:]

    init() {}

    init(departments: [Department], templates: [TimeBlock], stores: [Store]) {
        sortedStores = stores.isEmpty ? [Store.makeDefault()] : stores.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        storeOrder = Dictionary(sortedStores.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        let first = sortedStores[0].id
        for d in departments {
            departmentStore[d.id] = storeOrder[d.storeID] != nil ? d.storeID : first
            departmentOrder[d.id] = d.sortOrder
        }
        // 同じIDが複数あれば先のもの（first(where:) と同じ）
        for t in templates where self.templates[t.id] == nil { self.templates[t.id] = t }
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

    // 曜日・日のずらしは、表を描くたびに何万回も呼ばれるので Calendar を使わず整数の計算で出す
    // （1970-01-01 からの日数。グレゴリオ暦。Calendar と同じ結果になることはテストで確かめている）

    /// 1970-01-01 を 0 とした通し日数
    var ordinal: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    init(ordinal: Int) {
        let z = ordinal + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let y = yoe + era * 400
        self.init(m <= 2 ? y + 1 : y, m, d)
    }

    /// 0＝日曜 … 6＝土曜（1970-01-01 は木曜）
    var weekday: Int { ((ordinal % 7) + 7 + 4) % 7 }

    func adding(days n: Int) -> DayKey { DayKey(ordinal: ordinal + n) }

    /// "YYYY-MM-DD"（String(format:) は遅いので、手で組み立てる）
    var description: String {
        var s = String(year)
        s.reserveCapacity(10)
        s += month < 10 ? "-0" : "-"
        s += String(month)
        s += day < 10 ? "-0" : "-"
        s += String(day)
        return s
    }

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
        let n = DayKey(adding(months: 1).year, adding(months: 1).month, 1).ordinal - first.ordinal
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
        // 数字と「:」を1文字ずつ読む（split で配列を作らない。表を描くたびに何万回も呼ばれるため）
        var h = 0, m = 0, hd = 0, md = 0, colon = false
        for c in text.utf8 {
            switch c {
            case UInt8(ascii: "0")...UInt8(ascii: "9"):
                let v = Int(c - UInt8(ascii: "0"))
                if colon { m = m * 10 + v; md += 1 } else { h = h * 10 + v; hd += 1 }
                if hd > 2 || md > 2 { return nil }
            case UInt8(ascii: ":"):
                if colon { return nil }
                colon = true
            default:
                return nil
            }
        }
        guard colon, hd > 0, md > 0, h <= 24, m < 60 else { return nil }
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
