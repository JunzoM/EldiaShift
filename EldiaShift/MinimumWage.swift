import Foundation

// MARK: - 都道府県の最低賃金
// 店舗ごとに都道府県を決めると、その県の最低賃金（時給）より低い時給に注意を出す。
// 最低賃金は毎年10月〜12月に都道府県ごとに違う日から変わるので、金額は「発効日つき」で持ち、その日の金額で比べる。
// 表はアプリに入っている（bundled）。新しい年の表は、リポジトリの minimum-wage.json を直すと、
// アプリが起動時に読み込んで使う（MinimumWageUpdater）。読めないときはアプリに入っている表を使う。
// 表と違うときは、店舗の設定で金額を手で入れられる（手で入れた金額がいちばん優先）。

/// 最低賃金の表（年度ごと。都道府県 → 発効日つきの金額）
struct MinimumWageTable: Codable, Equatable, Sendable {
    struct Rate: Codable, Equatable, Sendable {
        /// 発効日（"YYYY-MM-DD"）。nil は「次の金額の発効日の前日まで」
        var from: String?
        /// 時給（円）
        var amount: Int

        init(from: String? = nil, amount: Int) {
            self.from = from
            self.amount = amount
        }
    }

    /// 年度（新しい表かどうかを比べる）
    var year: Int
    /// 表を直した日
    var updated: String
    var note: String?
    var rates: [String: [Rate]]

    /// その日に使う金額（発効日がその日以前の金額のうち、いちばん新しいもの）
    func amount(_ prefecture: String, on day: DayKey) -> Int? {
        guard let list = rates[prefecture] else { return nil }
        return list
            .filter { r in r.from.flatMap { DayKey($0) }.map { $0 <= day } ?? true }
            .max { ($0.from ?? "") < ($1.from ?? "") }?
            .amount
    }

    /// その日のあとに変わる予定の金額（いちばん近いもの）
    func upcoming(_ prefecture: String, after day: DayKey) -> (from: DayKey, amount: Int)? {
        guard let list = rates[prefecture] else { return nil }
        return list
            .compactMap { r in r.from.flatMap { DayKey($0) }.map { (from: $0, amount: r.amount) } }
            .filter { $0.from > day }
            .min { $0.from < $1.from }
    }

    /// 47都道府県がそろっていて、金額と日付が正しく読めるか（ネットから読んだ表を使う前に確かめる）
    var isValid: Bool {
        guard Set(rates.keys) == Set(MinimumWage.prefectures) else { return false }
        return rates.values.allSatisfy { list in
            !list.isEmpty && list.allSatisfy { r in (500...5000).contains(r.amount) && (r.from == nil || DayKey(r.from!) != nil) }
        }
    }
}

enum MinimumWage {
    static let prefectures = ["北海道", "青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県", "茨城県", "栃木県", "群馬県",
                              "埼玉県", "千葉県", "東京都", "神奈川県", "新潟県", "富山県", "石川県", "福井県", "山梨県", "長野県",
                              "岐阜県", "静岡県", "愛知県", "三重県", "滋賀県", "京都府", "大阪府", "兵庫県", "奈良県", "和歌山県",
                              "鳥取県", "島根県", "岡山県", "広島県", "山口県", "徳島県", "香川県", "愛媛県", "高知県", "福岡県",
                              "佐賀県", "長崎県", "熊本県", "大分県", "宮崎県", "鹿児島県", "沖縄県"]

    /// アプリに入っている表（令和7年度 → 令和8年度。厚生労働省「地域別最低賃金の全国一覧」）。
    /// リポジトリの minimum-wage.json と同じ内容にする（テストで確かめる）
    static let bundled = MinimumWageTable(year: 2026, updated: "2026-10-31", note: nil, rates: [
            "北海道": [.init(amount: 1075), .init(from: "2026-10-01", amount: 1131)],
            "青森県": [.init(amount: 1029), .init(from: "2026-10-29", amount: 1090)],
            "岩手県": [.init(amount: 1031), .init(from: "2026-12-01", amount: 1090)],
            "宮城県": [.init(amount: 1038), .init(from: "2026-10-01", amount: 1098)],
            "秋田県": [.init(amount: 1031), .init(from: "2026-10-14", amount: 1090)],
            "山形県": [.init(amount: 1032), .init(from: "2026-10-30", amount: 1092)],
            "福島県": [.init(amount: 1033), .init(from: "2026-10-16", amount: 1094)],
            "茨城県": [.init(amount: 1074), .init(from: "2026-10-18", amount: 1136)],
            "栃木県": [.init(amount: 1068), .init(from: "2026-10-01", amount: 1125)],
            "群馬県": [.init(amount: 1063), .init(from: "2026-10-03", amount: 1120)],
            "埼玉県": [.init(amount: 1141), .init(from: "2026-10-01", amount: 1196)],
            "千葉県": [.init(amount: 1140), .init(from: "2026-10-01", amount: 1195)],
            "東京都": [.init(amount: 1226), .init(from: "2026-10-01", amount: 1280)],
            "神奈川県": [.init(amount: 1225), .init(from: "2026-10-01", amount: 1279)],
            "新潟県": [.init(amount: 1050), .init(from: "2026-10-01", amount: 1108)],
            "富山県": [.init(amount: 1062), .init(from: "2026-10-01", amount: 1119)],
            "石川県": [.init(amount: 1054), .init(from: "2026-10-03", amount: 1113)],
            "福井県": [.init(amount: 1053), .init(from: "2026-10-04", amount: 1112)],
            "山梨県": [.init(amount: 1052), .init(from: "2026-11-01", amount: 1113)],
            "長野県": [.init(amount: 1061), .init(from: "2026-10-02", amount: 1117)],
            "岐阜県": [.init(amount: 1065), .init(from: "2026-10-01", amount: 1121)],
            "静岡県": [.init(amount: 1097), .init(from: "2026-10-15", amount: 1154)],
            "愛知県": [.init(amount: 1140), .init(from: "2026-10-01", amount: 1195)],
            "三重県": [.init(amount: 1087), .init(from: "2026-10-01", amount: 1143)],
            "滋賀県": [.init(amount: 1080), .init(from: "2026-10-03", amount: 1136)],
            "京都府": [.init(amount: 1122), .init(from: "2026-11-16", amount: 1180)],
            "大阪府": [.init(amount: 1177), .init(from: "2026-10-01", amount: 1231)],
            "兵庫県": [.init(amount: 1116), .init(from: "2026-10-01", amount: 1172)],
            "奈良県": [.init(amount: 1051), .init(from: "2026-10-04", amount: 1107)],
            "和歌山県": [.init(amount: 1045), .init(from: "2026-10-03", amount: 1101)],
            "鳥取県": [.init(amount: 1030), .init(from: "2026-10-03", amount: 1090)],
            "島根県": [.init(amount: 1033), .init(from: "2026-10-10", amount: 1092)],
            "岡山県": [.init(amount: 1047), .init(from: "2026-10-02", amount: 1104)],
            "広島県": [.init(amount: 1085), .init(from: "2026-10-11", amount: 1141)],
            "山口県": [.init(amount: 1043), .init(from: "2026-10-08", amount: 1101)],
            "徳島県": [.init(amount: 1046), .init(from: "2026-11-01", amount: 1103)],
            "香川県": [.init(amount: 1036), .init(from: "2026-10-01", amount: 1092)],
            "愛媛県": [.init(amount: 1033), .init(from: "2026-11-01", amount: 1093)],
            "高知県": [.init(amount: 1023), .init(from: "2026-10-29", amount: 1086)],
            "福岡県": [.init(amount: 1057), .init(from: "2026-10-04", amount: 1114)],
            "佐賀県": [.init(amount: 1030), .init(from: "2026-11-15", amount: 1095)],
            "長崎県": [.init(amount: 1031), .init(from: "2026-11-02", amount: 1087)],
            "熊本県": [.init(amount: 1034), .init(from: "2026-12-01", amount: 1092)],
            "大分県": [.init(amount: 1035), .init(from: "2026-11-01", amount: 1096)],
            "宮崎県": [.init(amount: 1023), .init(from: "2026-10-24", amount: 1085)],
            "鹿児島県": [.init(amount: 1026), .init(from: "2026-10-25", amount: 1090)],
            "沖縄県": [.init(amount: 1023), .init(from: "2026-12-02", amount: 1086)],
    ])

    // ネットから読んだ表（アプリに入っている表より新しいときだけ使う）
    private static let lock = NSLock()
    nonisolated(unsafe) private static var downloaded: MinimumWageTable? = MinimumWageUpdater.loadSaved()

    /// いま使う表
    static var current: MinimumWageTable {
        lock.lock(); defer { lock.unlock() }
        if let d = downloaded, d.year >= bundled.year { return d }
        return bundled
    }

    /// ネットから読んだ表を使う。正しく読めて、アプリの表と同じか新しい年度のときだけ。使ったら true
    @discardableResult
    static func adopt(_ table: MinimumWageTable) -> Bool {
        guard table.isValid, table.year >= bundled.year else { return false }
        lock.lock(); defer { lock.unlock() }
        downloaded = table
        return true
    }

    /// テスト用：ネットから読んだ表を使わない
    static func resetDownloaded() {
        lock.lock(); defer { lock.unlock() }
        downloaded = nil
    }

    /// 都道府県のその日の最低賃金（表の金額）
    static func amount(for prefecture: String, on day: DayKey) -> Int? {
        current.amount(prefecture, on: day)
    }

    /// その店舗のその日の最低賃金（手で入れた金額 → 表 の順）。都道府県を決めていなければ nil
    static func value(for store: Store?, on day: DayKey = .today) -> Int? {
        guard let store else { return nil }
        if let v = store.minimumWageOverride, v > 0 { return v }
        return amount(for: store.prefecture, on: day)
    }

    /// その人の店舗（部門の店舗）のその日の最低賃金
    static func value(for m: StaffMember, in book: ShiftBook, on day: DayKey = .today) -> Int? {
        value(for: book.store(book.homeStoreID(of: m)), on: day)
    }

    /// 時給が最低賃金に足りない分（円）。時給でない・足りている・最低賃金が決まっていないときは nil
    static func shortfall(_ w: WageEntry?, minimum: Int?) -> Int? {
        guard let w, w.kind == .hourly, w.amount > 0, let minimum, w.amount < minimum else { return nil }
        return minimum - w.amount
    }

    /// その日の時給が、その日の最低賃金に足りない分
    static func shortfall(of m: StaffMember, on day: DayKey, in book: ShiftBook) -> Int? {
        shortfall(m.wage(on: day), minimum: value(for: m, in: book, on: day))
    }

    /// 10円単位に切り上げる（1,201円 → 1,210円）
    static func roundUp10(_ v: Int) -> Int { v <= 0 ? v : (v + 9) / 10 * 10 }
}

// MARK: - 新しい表の読み込み

/// リポジトリの minimum-wage.json を起動時に読み、手元に保存して使う（1日に1回まで）。
/// 毎年の改定は JSON を直すだけで、アプリの更新を待たずに届く
enum MinimumWageUpdater {
    static let url = URL(string: "https://raw.githubusercontent.com/JunzoM/EldiaShift/main/minimum-wage.json")!
    private static let savedKey = "minimumWageTable"
    private static let checkedKey = "minimumWageCheckedAt"

    /// 前に読んで保存した表
    static func loadSaved() -> MinimumWageTable? {
        guard let data = UserDefaults.standard.data(forKey: savedKey) else { return nil }
        return try? JSONDecoder().decode(MinimumWageTable.self, from: data)
    }

    /// 新しい表を読む。前に読んでから12時間たっていなければ何もしない。失敗しても何もしない（アプリの表のまま）
    static func refresh() async {
        // 画面確認用（CI のスクリーンショット）は、ネットを使わずアプリの表で出す
        guard !DemoMode.enabled else { return }
        let now = Date().timeIntervalSince1970
        let last = UserDefaults.standard.double(forKey: checkedKey)
        guard now - last > 12 * 3600 else { return }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let table = try? JSONDecoder().decode(MinimumWageTable.self, from: data) else { return }
        UserDefaults.standard.set(now, forKey: checkedKey)
        if MinimumWage.adopt(table) {
            UserDefaults.standard.set(data, forKey: savedKey)
        }
    }
}
