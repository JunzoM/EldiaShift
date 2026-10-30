import Foundation

// MARK: - 都道府県の最低賃金（HOTEL-SHIFT から）
// 店舗ごとに都道府県を決めると、その県の最低賃金（時給）より低い時給に注意を出す。
// 表は毎年10月ごろに変わる。表と違うときは、店舗の設定で金額を手で入れられる。

enum MinimumWage {
    static let prefectures = ["北海道", "青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県", "茨城県", "栃木県", "群馬県",
                              "埼玉県", "千葉県", "東京都", "神奈川県", "新潟県", "富山県", "石川県", "福井県", "山梨県", "長野県",
                              "岐阜県", "静岡県", "愛知県", "三重県", "滋賀県", "京都府", "大阪府", "兵庫県", "奈良県", "和歌山県",
                              "鳥取県", "島根県", "岡山県", "広島県", "山口県", "徳島県", "香川県", "愛媛県", "高知県", "福岡県",
                              "佐賀県", "長崎県", "熊本県", "大分県", "宮崎県", "鹿児島県", "沖縄県"]

    /// アプリに入っている表（円・時給。HOTEL-SHIFT と同じ）
    static let table: [String: Int] = [
        "北海道": 1131, "青森県": 1029, "岩手県": 1031, "宮城県": 1098, "秋田県": 1090, "山形県": 1032, "福島県": 1094,
        "茨城県": 1136, "栃木県": 1125, "群馬県": 1120, "埼玉県": 1196, "千葉県": 1195, "東京都": 1280, "神奈川県": 1279,
        "新潟県": 1108, "富山県": 1119, "石川県": 1113, "福井県": 1112, "山梨県": 1052, "長野県": 1117, "岐阜県": 1121, "静岡県": 1154,
        "愛知県": 1195, "三重県": 1143, "滋賀県": 1136, "京都府": 1122, "大阪府": 1231, "兵庫県": 1172, "奈良県": 1107, "和歌山県": 1101,
        "鳥取県": 1090, "島根県": 1033, "岡山県": 1104, "広島県": 1085, "山口県": 1043, "徳島県": 1046, "香川県": 1092, "愛媛県": 1033,
        "高知県": 1023, "福岡県": 1114, "佐賀県": 1030, "長崎県": 1031, "熊本県": 1034, "大分県": 1035, "宮崎県": 1023, "鹿児島県": 1026,
        "沖縄県": 1023
    ]

    /// その店舗の最低賃金（手で入れた金額 → 表 の順）。都道府県を決めていなければ nil
    static func value(for store: Store?) -> Int? {
        guard let store else { return nil }
        if let v = store.minimumWageOverride, v > 0 { return v }
        return table[store.prefecture]
    }

    /// その人の店舗（部門の店舗）の最低賃金
    static func value(for m: StaffMember, in book: ShiftBook) -> Int? {
        value(for: book.store(book.homeStoreID(of: m)))
    }

    /// 時給が最低賃金に足りない分（円）。時給でない・足りている・最低賃金が決まっていないときは nil
    static func shortfall(_ w: WageEntry?, minimum: Int?) -> Int? {
        guard let w, w.kind == .hourly, w.amount > 0, let minimum, w.amount < minimum else { return nil }
        return minimum - w.amount
    }

    /// その日の時給が最低賃金に足りない分
    static func shortfall(of m: StaffMember, on day: DayKey, in book: ShiftBook) -> Int? {
        shortfall(m.wage(on: day), minimum: value(for: m, in: book))
    }

    /// 10円単位に切り上げる（1,201円 → 1,210円）
    static func roundUp10(_ v: Int) -> Int { v <= 0 ? v : (v + 9) / 10 * 10 }
}
