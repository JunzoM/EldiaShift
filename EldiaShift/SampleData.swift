import CoreData
import Foundation

// MARK: - 見本のデータで試す（HOTEL-SHIFT の「サンプルデータ」から）
// 見本の会社・店舗・部門・ひな形・スタッフ・3年分のシフト・希望休の申請を足す。
// ID の頭に「sample-」を付けて見分け、あとでまとめて消せる。今のデータには手を付けない。

enum SampleData {
    static let prefix = "sample-"
    static func isSample(_ id: String) -> Bool { id.hasPrefix(prefix) }

    /// 見本の会社の名前（会社の情報が空のときだけ入れる。見本を消すと空に戻す）
    static let companyName = "見本ホテルグループ"
    /// 1店舗の人数
    static let staffPerStore = 25
    /// 1店舗の希望休の申請の数
    static let requestsPerStore = 30

    struct Parts {
        var stores: [Store]
        var departments: [Department]
        var templates: [TimeBlock]
        var staff: [StaffMember]
    }

    /// 4店舗 × 2部門 × 25人。去年・今年・来年の3年分のシフトと、店舗ごとに30件の希望休の申請
    /// - offBlockID: 休みの日に入れるひな形（無ければ空きのまま）
    /// - storeOrder / departmentOrder: 今ある店舗・部門の後ろに並べる番号
    /// - today: 3年の範囲と、希望休の日を決める基準の日
    static func make(offBlockID: String?, storeOrder: Int, departmentOrder: Int, today: DayKey = .today) -> Parts {
        let storeInfo: [(key: String, name: String, short: String, prefecture: String, hours: String, rooms: Int, floors: Int, color: Int)] = [
            ("a", "見本ホテル 本館", "本館", "東京都", "24時間", 180, 12, 4),
            ("b", "見本ホテル 別館", "別館", "東京都", "6:00〜24:00", 64, 5, 6),
            ("c", "見本ホテル 駅前", "駅前", "大阪府", "24時間", 120, 9, 2),
            ("d", "見本ホテル 空港", "空港", "福岡県", "24時間", 96, 7, 8)
        ]
        let stores = storeInfo.enumerated().map { i, s -> Store in
            var st = Store(id: prefix + "store-" + s.key, name: s.name, address: "（見本）", hours: s.hours,
                           note: i == 0 ? "見本のデータです。店舗管理の右上のメニューからまとめて消せます。" : "見本のデータです。",
                           short: s.short, colorIndex: s.color, sortOrder: storeOrder + i)
            st.prefecture = s.prefecture
            st.roomCount = s.rooms
            st.floorCount = s.floors
            return st
        }

        // 店舗ごとにフロント・客室
        var departments: [Department] = []
        for (i, st) in stores.enumerated() {
            let key = storeInfo[i].key
            departments.append(Department(id: prefix + "front-" + key, name: "フロント", colorIndex: 0,
                                          sortOrder: departmentOrder + i * 2, storeID: st.id))
            departments.append(Department(id: prefix + "room-" + key, name: "客室", colorIndex: 2,
                                          sortOrder: departmentOrder + i * 2 + 1, storeID: st.id))
        }

        let templates = [
            TimeBlock(id: prefix + "early", label: "早番（見本）", short: "早", inMinutes: 7 * 60, outMinutes: 16 * 60, colorIndex: 2),
            TimeBlock(id: prefix + "late", label: "遅番（見本）", short: "遅", inMinutes: 14 * 60, outMinutes: 23 * 60, colorIndex: 3),
            TimeBlock(id: prefix + "night", label: "夜勤（見本）", short: "夜", inMinutes: 22 * 60, outMinutes: 8 * 60, colorIndex: 8)
        ]
        let e = templates[0].id, l = templates[1].id, n = templates[2].id, o = offBlockID
        // 日〜土の週の形。人ごと・週ごとにずらして使う（週に2日は休み）
        let weeks: [[String?]] = [
            [o, e, e, e, e, e, o],
            [e, o, l, l, o, l, l],
            [l, l, o, e, e, o, e],
            [n, o, n, o, n, n, o],
            [o, l, e, o, l, e, l],
            [e, e, o, n, o, l, e]
        ]
        // 3年分：去年の1月1日〜来年の12月31日
        let first = DayKey(today.year - 1, 1, 1)
        let last = DayKey(today.year + 1, 12, 31)
        let weekStart = first.adding(days: -first.weekday)   // その週の日曜

        let surnames = ["佐藤", "鈴木", "高橋", "田中", "伊藤", "渡辺", "山本", "中村", "小林", "加藤", "吉田", "山田", "佐々木", "山口",
                        "松本", "井上", "木村", "林", "斎藤", "清水", "山崎", "森", "池田", "橋本", "阿部", "石川", "山下", "中島", "石井", "小川",
                        "前田", "岡田", "長谷川", "藤田", "後藤", "近藤", "村上", "遠藤", "青木", "坂本", "斉藤", "福田", "太田", "西村", "藤井",
                        "金子", "岡本", "藤原", "中野", "三浦"]
        let given = ["花子", "太郎", "美咲", "翔", "陽菜", "大輝", "結衣", "蓮", "さくら", "悠斗", "葵", "湊", "凛", "颯太", "芽依",
                     "陸", "七海", "樹", "彩花", "大和", "ひかり", "健太", "真央", "拓海", "優奈"]
        let reasons = ["家族の用事", "通院", "子どもの行事", "旅行", "引っ越し", "資格の試験", "冠婚葬祭", "役所の手続き", "", ""]

        var staff: [StaffMember] = []
        for (si, st) in stores.enumerated() {
            let key = storeInfo[si].key
            let depts = departments.filter { $0.storeID == st.id }
            let minimum = MinimumWage.table[storeInfo[si].prefecture] ?? 1100
            var members: [StaffMember] = []
            for k in 0..<staffPerStore {
                // 前の13人はフロント、あとの12人は客室
                let dept = k < 13 ? depts[0] : depts[1]
                let number = k < 13 ? k + 1 : k - 12
                let i = si * staffPerStore + k
                let id = prefix + "staff-\(key)-\(k + 1)"
                // 週ごとに形をずらす（毎週同じにならないように）
                var days: [String: String] = [:]
                var d = first
                while d <= last {
                    let week = (d.ordinal - weekStart.ordinal) / 7
                    if let bid = weeks[(k + week + si) % weeks.count][d.weekday] { days[d.description] = bid }
                    d = d.adding(days: 1)
                }
                let fullTime = k % 5 == 0
                let wage = fullTime
                    ? WageEntry(id: "\(id)-wage", from: "\(first.year)-01-01", kind: .monthly, amount: 240_000 + (k % 4) * 10_000)
                    : WageEntry(id: "\(id)-wage", from: "\(first.year)-01-01", kind: .hourly, amount: minimum + 20 + (k % 6) * 30)
                var m = StaffMember(
                    id: id, number: number, name: "\(surnames[i % surnames.count]) \(given[(k + si * 7) % given.count])",
                    departmentID: dept.id, active: true, joinDate: "", leaveDate: "", timeBlocks: [],
                    patterns: [WeekPattern(id: id + "-pattern", label: "通常", colorIndex: 0, days: weeks[(k + si) % weeks.count], activeFrom: nil)],
                    activePatternID: id + "-pattern",
                    periodPatterns: [PeriodPattern(id: id + "-period", label: "3年分（見本）", colorIndex: 3,
                                                   startDate: first.description, endDate: last.description, days: days)])
                m.employment = fullTime ? "正社員" : (k % 3 == 0 ? "アルバイト" : "パート")
                m.wages = [wage]
                members.append(m)
            }

            // 希望休の申請：今月と来月に30件（承認15・承認待ち10・却下5）
            let monthStart = DayKey(today.year, today.month, 1)
            for j in 0..<requestsPerStore {
                let who = (j * 7 + si) % members.count
                let day = monthStart.adding(days: (j * 2 + si + who % 3) % 56)
                let status: LeaveRequest.Status = j % 6 == 5 ? .rejected : (j % 3 == 1 ? .pending : .approved)
                let received = Calendar.shift.date(byAdding: .day, value: -(j % 10 + 1), to: Date()) ?? Date()
                let req = LeaveRequest(id: prefix + "request-\(key)-\(j + 1)", day: day.description, note: reasons[j % reasons.count],
                                       status: status, receivedAt: LeaveRequestInbox.stamp(received),
                                       decidedAt: status == .pending ? nil : LeaveRequestInbox.stamp(Date()))
                members[who].leaveRequests.append(req)
                if status == .approved {
                    // 承認した日は希望休に入れ、その日のシフトも休みにする
                    if !members[who].offRequests.contains(day.description) {
                        members[who].offRequests.append(day.description)
                        members[who].offRequests.sort()
                    }
                    members[who].periodPatterns[0].days[day.description] = o
                }
            }
            staff += members
        }
        return Parts(stores: stores, departments: departments, templates: templates, staff: staff)
    }
}

extension ShiftStore {
    /// 見本のデータが入っているか
    var hasSampleData: Bool {
        book.stores.contains { SampleData.isSample($0.id) } || book.staff.contains { SampleData.isSample($0.id) }
    }

    /// 見本の会社・店舗・部門・ひな形・スタッフを足す（今のデータはそのまま）
    func addSampleData(today: DayKey = .today) throws {
        guard !hasSampleData else { return }
        let offID = book.templates.first { $0.id == "off1" }?.id ?? book.templates.first(where: \.isOff)?.id
        let parts = SampleData.make(offBlockID: offID, storeOrder: book.allStores.count,
                                    departmentOrder: (book.departments.map(\.sortOrder).max() ?? -1) + 1, today: today)
        // 人数が多いので、まとめて入れてから1回だけ保存する
        let ctx = db.viewContext
        for d in parts.departments { try ShiftRecords.upsert(d, in: ctx) }
        for (i, t) in parts.templates.enumerated() { try ShiftRecords.upsert(t, sortOrder: book.templates.count + i, in: ctx) }
        for m in parts.staff { try ShiftRecords.upsert(m, in: ctx) }
        try db.save()
        for st in parts.stores { try save(st) }
        if book.company.name.isEmpty {
            var c = book.company
            c.name = SampleData.companyName
            try setCompany(c)
        }
        reload()
    }

    /// 見本だけを消す（先に自動バックアップ）。見本のひな形は、見本でない人が使っていれば残す
    func removeSampleData() throws {
        guard hasSampleData else { return }
        try autoBackup(reason: "見本を消す前")
        let ctx = db.viewContext
        for m in book.staff where SampleData.isSample(m.id) {
            try ShiftRecords.delete(ShiftModel.Entity.staff, key: m.id, in: ctx)
            try ShiftRecords.deleteCells(ofStaff: m.id, in: ctx)
            dropHistory(for: m.id)
        }
        for d in book.departments where SampleData.isSample(d.id) {
            try ShiftRecords.delete(ShiftModel.Entity.department, key: d.id, in: ctx)
        }
        let others = book.staff.filter { !SampleData.isSample($0.id) }
        let othersCells = book.cells.filter { !SampleData.isSample($0.key.staffID) }.values
        for t in book.templates where SampleData.isSample(t.id) {
            let used = othersCells.contains { $0.blockID == t.id }
                || others.contains { m in m.patterns.contains { $0.days.contains(t.id) } || m.periodPatterns.contains { $0.days.values.contains(t.id) } }
            if !used { try ShiftRecords.delete(ShiftModel.Entity.template, key: t.id, in: ctx) }
        }
        // 見本でない人の掛け持ち先から、見本の店舗を外す
        for var m in others where m.extraStoreIDs.contains(where: SampleData.isSample) {
            m.extraStoreIDs.removeAll(where: SampleData.isSample)
            try ShiftRecords.upsert(m, in: ctx)
        }
        try db.save()
        // 店舗は設定に入っているので、設定として保存し直す（見ていた店舗が見本なら、最初の店舗に戻る）
        let sampleStores = book.stores.filter { SampleData.isSample($0.id) }
        for st in sampleStores {
            if currentStoreID == st.id { currentStoreID = book.allStores.first { !SampleData.isSample($0.id) }?.id ?? Store.defaultID }
        }
        try removeStores(Set(sampleStores.map(\.id)))
        // 見本で入れた会社の名前なら、空に戻す
        if book.company.name == SampleData.companyName {
            var c = book.company
            c.name = ""
            try setCompany(c)
        }
        reload()
    }
}
