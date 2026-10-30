import Foundation

// MARK: - 希望休の申請（HOTEL SHIFT の「申請中・承認・却下」を移植）
// スタッフは LINE・AirDrop などで文章を送る（スタッフの端末にアプリは要らない）。
// 管理者はその文章を貼り付けて「承認待ち」にし、承認すると希望休（offRequests）に入る。

struct LeaveRequest: Identifiable, Hashable, Codable, Sendable {
    enum Status: String, Codable, Sendable, CaseIterable {
        case pending, approved, rejected
        var label: String {
            switch self {
            case .pending: "承認待ち"
            case .approved: "承認"
            case .rejected: "却下"
            }
        }
    }

    var id: String
    /// 休みたい日（YYYY-MM-DD）
    var day: String
    /// 理由・届いた文章
    var note: String
    var status: Status
    var receivedAt: Date
    var decidedAt: Date?
}

enum LeaveRequestInbox {
    /// 日時は秒まで（バックアップの読み書きで値がずれないように）
    static func stamp(_ d: Date) -> Date { Date(timeIntervalSinceReferenceDate: d.timeIntervalSinceReferenceDate.rounded()) }

    /// 申請フォーム（壁の QR コードから開くページ）で作った文章の項目
    struct FormText: Equatable, Sendable {
        var name: String
        var dates: String
        var reason: String
        /// 「店舗：」の行（無ければ空）
        var store: String = ""
    }

    /// 決まった形（「名前：」「休みたい日：」の行がある）なら、その項目。ほかの文章なら nil
    static func formFields(_ text: String) -> FormText? {
        var name: String?, dates: String?, reason = "", store = ""
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            func value(_ key: String) -> String? {
                for sep in ["：", ":"] where line.hasPrefix(key + sep) {
                    return String(line.dropFirst(key.count + sep.count)).trimmingCharacters(in: .whitespaces)
                }
                return nil
            }
            if let v = value("名前") { name = v } else if let v = value("休みたい日") { dates = v } else if let v = value("理由") { reason = v } else if let v = value("店舗") { store = v }
        }
        guard let name, !name.isEmpty, let dates, !dates.isEmpty else { return nil }
        return FormText(name: name, dates: dates, reason: reason, store: store)
    }

    /// 名前の比べ方（空白を取る）
    static func normalize(_ s: String) -> String {
        (s.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? s)
            .components(separatedBy: .whitespacesAndNewlines).joined()
    }

    /// 文章に名前が出てくるスタッフ。フルネームが入っていればそれ、なければ姓・名だけで1人に決まるとき
    static func detectStaff(in text: String, among staff: [StaffMember]) -> StaffMember? {
        let body = normalize(text)
        guard !body.isEmpty else { return nil }
        let full = staff.filter { let n = normalize($0.name); return n.count >= 2 && body.contains(n) }
        if let best = full.max(by: { normalize($0.name).count < normalize($1.name).count }) {
            // 同じ長さで複数見つかったら決めない
            let len = normalize(best.name).count
            return full.filter { normalize($0.name).count == len }.count == 1 ? best : nil
        }
        // 「山田 花子」の「山田」だけ書いてあるとき
        let partial = staff.filter { m in
            m.name.split(whereSeparator: { $0 == " " || $0 == "　" }).map(String.init)
                .contains { $0.count >= 2 && body.contains($0) }
        }
        return partial.count == 1 ? partial[0] : nil
    }

    /// 届いた日を承認待ちとして足す（同じ日の承認待ち・承認済み・すでに希望休の日は足さない）
    static func receive(_ days: [DayKey], note: String, into m: StaffMember, now: Date) -> (StaffMember, added: Int) {
        var m = m
        let taken = Set(m.leaveRequests.filter { $0.status != .rejected }.map(\.day)).union(m.offRequests)
        var added = 0
        for d in Set(days).sorted() where !taken.contains(d.description) {
            m.leaveRequests.append(LeaveRequest(id: UUID().uuidString, day: d.description, note: note,
                                                status: .pending, receivedAt: stamp(now), decidedAt: nil))
            added += 1
        }
        return (m, added)
    }

    /// 承認・却下・承認待ちに戻す。承認した日は希望休に入れ、承認を取り消した日は希望休から外す
    static func decide(_ ids: Set<String>, as status: LeaveRequest.Status, in m: StaffMember, now: Date) -> StaffMember {
        var m = m
        var off = Set(m.offRequests)
        for i in m.leaveRequests.indices where ids.contains(m.leaveRequests[i].id) {
            let old = m.leaveRequests[i].status
            guard old != status else { continue }
            if status == .approved { off.insert(m.leaveRequests[i].day) }
            if old == .approved { off.remove(m.leaveRequests[i].day) }
            m.leaveRequests[i].status = status
            m.leaveRequests[i].decidedAt = status == .pending ? nil : stamp(now)
        }
        m.offRequests = off.sorted()
        return m
    }

    /// 申請を消す（間違えて受け取ったときなど）。承認で入れた希望休・シフトはそのまま残す
    static func remove(_ ids: Set<String>, from m: StaffMember) -> StaffMember {
        var m = m
        m.leaveRequests.removeAll { ids.contains($0.id) }
        return m
    }

    /// 申請に書かれた店舗が、その人の店舗（掛け持ち先を含む）と違うときの注意。店舗が1つ・店舗の指定が無いときは nil
    static func storeWarning(requestStore: String, member: StaffMember, in book: ShiftBook) -> String? {
        let asked = normalize(requestStore)
        guard !asked.isEmpty, book.allStores.count > 1 else { return nil }
        // 名前が同じ・どちらかがもう一方を含む（「神戸」と「ELDIA神戸」）店舗
        let matched = book.allStores.filter { st in
            [st.name, st.short].map(normalize).contains { !$0.isEmpty && ($0 == asked || $0.contains(asked) || asked.contains($0)) }
        }
        let home = book.store(book.homeStoreID(of: member))?.name ?? ""
        if matched.isEmpty { return "申請の店舗「\(requestStore)」は、登録している店舗にありません。\(member.name)さんの店舗は「\(home)」です。" }
        guard !matched.contains(where: { book.storeIDs(of: member).contains($0.id) }) else { return nil }
        return "申請の店舗は「\(requestStore)」ですが、\(member.name)さんの店舗は「\(home)」です。"
    }

    /// 返事を送る相手と、その人の決まった申請（承認待ちに戻したものは入れない）。名前の順
    static func replyGroups(_ ids: Set<String>, staff: [StaffMember]) -> [(member: StaffMember, decided: [LeaveRequest])] {
        staff.compactMap { m -> (member: StaffMember, decided: [LeaveRequest])? in
            let decided = m.leaveRequests.filter { ids.contains($0.id) && $0.status != .pending }
            return decided.isEmpty ? nil : (m, decided)
        }
        .sorted { $0.member.name < $1.member.name }
    }

    /// スタッフへの返事（LINE などに貼る）
    static func reply(to m: StaffMember, _ decided: [LeaveRequest]) -> String {
        func days(_ s: LeaveRequest.Status) -> String {
            decided.filter { $0.status == s }.compactMap { DayKey($0.day) }.sorted()
                .map { "\($0.month)/\($0.day)（\(["日", "月", "火", "水", "木", "金", "土"][$0.weekday])）" }
                .joined(separator: "、")
        }
        var lines = ["\(m.name)さん", "希望休の申請の結果です。"]
        let ok = days(.approved), ng = days(.rejected)
        if !ok.isEmpty { lines.append("◯ お休みOK：\(ok)") }
        if !ng.isEmpty { lines.append("✕ 難しい日：\(ng)") }
        if !ng.isEmpty { lines.append("難しい日は、ほかの日にできないか相談させてください。") }
        return lines.joined(separator: "\n")
    }
}

extension ShiftStore {
    /// 届いた申請を承認待ちにする。足した件数を返す
    @discardableResult
    func receiveLeaveRequests(_ days: [DayKey], note: String, for staffID: String) throws -> Int {
        guard let m = book.staff.first(where: { $0.id == staffID }) else { return 0 }
        let (next, added) = LeaveRequestInbox.receive(days, note: note, into: m, now: Date())
        if added > 0 { try save(next) }
        return added
    }

    /// 申請を消す（希望休・シフトは変えない）
    func deleteLeaveRequests(_ ids: Set<String>, for staffID: String) throws {
        guard let m = book.staff.first(where: { $0.id == staffID }) else { return }
        let next = LeaveRequestInbox.remove(ids, from: m)
        guard next.leaveRequests.count != m.leaveRequests.count else { return }
        try save(next)
    }

    /// 承認・却下する。承認した日を休みにするときは offBlockID（休みのひな形）を渡す
    func decideLeaveRequests(_ ids: Set<String>, as status: LeaveRequest.Status, for staffID: String, offBlockID: String?) throws {
        guard let m = book.staff.first(where: { $0.id == staffID }) else { return }
        let next = LeaveRequestInbox.decide(ids, as: status, in: m, now: Date())
        try save(next)
        guard status == .approved, let offBlockID, !offBlockID.isEmpty else { return }
        let days = next.leaveRequests.filter { ids.contains($0.id) }.compactMap { DayKey($0.day) }
            .filter { Schedule.resolve(next, on: $0, in: book)?.isOff != true }
        guard !days.isEmpty else { return }
        try setCells(days.map { (CellKey(staffID: next.id, day: $0), CellEntry(inTime: "", outTime: "", blockID: offBlockID, isOff: true)) },
                     title: "\(next.name) の希望休 \(days.count)日を休みにしました")
    }
}

// MARK: - 申請フォームの「取り込み用リンク」
// フォームが作るリンク：https://facility-manager-phi.vercel.app/hotel-shift/r#<中身>
// 中身（名前・店舗・日付・理由の JSON を base64url にしたもの）は「#」より後ろなので、ブラウザはサーバーに送らない。
// iPad でリンクを押すと SHIFT が開き（ユニバーサルリンク、または eldiashift://request#<中身>）、受け取り画面に入る。

struct LeaveRequestLink: Identifiable, Equatable, Sendable {
    let id = UUID()
    var name: String
    var store: String
    var days: [DayKey]
    var reason: String

    static let host = "facility-manager-phi.vercel.app"
    static let path = "/hotel-shift/r"
    static let scheme = "eldiashift"

    private struct Payload: Codable {
        var v: Int
        var n: String
        var s: String?
        var d: [String]
        var r: String?
    }

    /// SHIFT で受け取るリンクか（ユニバーサルリンク・独自スキームのどちらも）
    static func decode(_ url: URL) -> LeaveRequestLink? {
        let isWeb = (url.scheme == "https" && url.host == host && url.path.hasPrefix(path))
        let isApp = (url.scheme == scheme && url.host == "request")
        guard isWeb || isApp, let fragment = url.fragment, !fragment.isEmpty, fragment.count <= 4000 else { return nil }
        var b64 = fragment.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let p = try? JSONDecoder().decode(Payload.self, from: data), p.v == 1 else { return nil }
        let name = String(p.n.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        let days = Array(Set(p.d.compactMap { DayKey($0) })).sorted().prefix(62)
        guard !name.isEmpty, !days.isEmpty else { return nil }
        return LeaveRequestLink(name: name, store: String((p.s ?? "").prefix(40)), days: Array(days),
                                reason: String((p.r ?? "").prefix(200)))
    }

    /// 受け取り画面に入れる文章（申請フォームと同じ決まった形）
    var formText: String {
        let wd = ["日", "月", "火", "水", "木", "金", "土"]
        var lines = ["【希望休の申請】", "名前：\(name)"]
        if !store.isEmpty { lines.append("店舗：\(store)") }
        lines.append("休みたい日：" + days.map { "\($0.month)/\($0.day)(\(wd[$0.weekday]))" }.joined(separator: "、"))
        if !reason.isEmpty { lines.append("理由：\(reason)") }
        return lines.joined(separator: "\n")
    }

    /// 「12日」などを読む月（いちばん早い日の月）
    var month: MonthKey { MonthKey(days[0]) }
}
