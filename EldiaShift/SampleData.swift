import CoreData
import Foundation

// MARK: - 見本のデータで試す（HOTEL-SHIFT の「サンプルデータ」から）
// 見本の店舗・部門・ひな形・スタッフを足す。ID の頭に「sample-」を付けて見分け、あとでまとめて消せる。
// 今のデータには手を付けない（今の店舗・スタッフ・シフトはそのまま）。

enum SampleData {
    static let prefix = "sample-"
    static func isSample(_ id: String) -> Bool { id.hasPrefix(prefix) }

    struct Parts {
        var stores: [Store]
        var departments: [Department]
        var templates: [TimeBlock]
        var staff: [StaffMember]
    }

    /// 2店舗 × 2部門 × 6人。週のくり返しで、毎日だれかが勤務する
    /// - offBlockID: 休みの日に入れるひな形（無ければ空きのまま）
    /// - storeOrder / departmentOrder: 今ある店舗・部門の後ろに並べる番号
    static func make(offBlockID: String?, storeOrder: Int, departmentOrder: Int) -> Parts {
        let stores = [
            Store(id: prefix + "store-a", name: "見本ホテル 本館", address: "（見本）", hours: "24時間",
                  note: "見本のデータです。店舗管理の右上のメニューからまとめて消せます。", short: "本館", colorIndex: 4, sortOrder: storeOrder),
            Store(id: prefix + "store-b", name: "見本ホテル 別館", address: "（見本）", hours: "6:00〜24:00",
                  note: "見本のデータです。", short: "別館", colorIndex: 6, sortOrder: storeOrder + 1)
        ].enumerated().map { i, st -> Store in
            var st = st
            st.roomCount = i == 0 ? 120 : 48
            st.floorCount = i == 0 ? 10 : 4
            return st
        }
        let departments = [
            Department(id: prefix + "front-a", name: "フロント", colorIndex: 0, sortOrder: departmentOrder, storeID: stores[0].id),
            Department(id: prefix + "room-a", name: "客室", colorIndex: 2, sortOrder: departmentOrder + 1, storeID: stores[0].id),
            Department(id: prefix + "front-b", name: "フロント", colorIndex: 0, sortOrder: departmentOrder + 2, storeID: stores[1].id),
            Department(id: prefix + "room-b", name: "客室", colorIndex: 2, sortOrder: departmentOrder + 3, storeID: stores[1].id)
        ]
        let templates = [
            TimeBlock(id: prefix + "early", label: "早番（見本）", short: "早", inMinutes: 7 * 60, outMinutes: 16 * 60, colorIndex: 2),
            TimeBlock(id: prefix + "late", label: "遅番（見本）", short: "遅", inMinutes: 14 * 60, outMinutes: 23 * 60, colorIndex: 3),
            TimeBlock(id: prefix + "night", label: "夜勤（見本）", short: "夜", inMinutes: 22 * 60, outMinutes: 8 * 60, colorIndex: 8)
        ]
        let e = templates[0].id, l = templates[1].id, n = templates[2].id, o = offBlockID
        // 日〜土。人ごとにずらして使う
        let weeks: [[String?]] = [
            [o, e, e, e, e, e, o],
            [e, o, l, l, o, l, l],
            [l, l, o, e, e, o, e],
            [n, o, n, o, n, n, o],
            [o, l, e, o, l, e, l],
            [e, e, o, n, o, l, e]
        ]
        let surnames = ["佐藤", "鈴木", "高橋", "田中", "伊藤", "渡辺", "山本", "中村", "小林", "加藤", "吉田", "山田",
                        "佐々木", "山口", "松本", "井上", "木村", "林", "斎藤", "清水", "山崎", "森", "池田", "橋本"]
        let given = ["花子", "太郎", "美咲", "翔", "陽菜", "大輝"]
        var staff: [StaffMember] = []
        for (di, d) in departments.enumerated() {
            for k in 0..<6 {
                let i = di * 6 + k
                staff.append(StaffMember(
                    id: prefix + "staff-\(i + 1)", number: k + 1, name: "\(surnames[i]) \(given[k])", departmentID: d.id,
                    active: true, joinDate: "", leaveDate: "", timeBlocks: [],
                    patterns: [WeekPattern(id: prefix + "pattern-\(i + 1)", label: "通常", colorIndex: 0, days: weeks[(k + di) % weeks.count],
                                           activeFrom: nil)],
                    activePatternID: prefix + "pattern-\(i + 1)", periodPatterns: []))
            }
        }
        return Parts(stores: stores, departments: departments, templates: templates, staff: staff)
    }
}

extension ShiftStore {
    /// 見本のデータが入っているか
    var hasSampleData: Bool {
        book.stores.contains { SampleData.isSample($0.id) } || book.staff.contains { SampleData.isSample($0.id) }
    }

    /// 見本の店舗・部門・ひな形・スタッフを足す（今のデータはそのまま）
    func addSampleData() throws {
        guard !hasSampleData else { return }
        let offID = book.templates.first { $0.id == "off1" }?.id ?? book.templates.first(where: \.isOff)?.id
        let parts = SampleData.make(offBlockID: offID, storeOrder: book.allStores.count,
                                    departmentOrder: (book.departments.map(\.sortOrder).max() ?? -1) + 1)
        for st in parts.stores { try save(st) }
        for d in parts.departments { try save(d) }
        for t in parts.templates { try save(t) }
        for m in parts.staff { try save(m) }
    }

    /// 見本だけを消す（先に自動バックアップ）。見本のひな形は、見本でない人が使っていれば残す
    func removeSampleData() throws {
        guard hasSampleData else { return }
        try autoBackup(reason: "見本を消す前")
        let ctx = db.viewContext
        for m in book.staff where SampleData.isSample(m.id) {
            try ShiftRecords.delete(ShiftModel.Entity.staff, key: m.id, in: ctx)
            let req = NSFetchRequest<NSManagedObject>(entityName: ShiftModel.Entity.cell)
            req.predicate = NSPredicate(format: "staffKey == %@", m.id)
            try ctx.fetch(req).forEach(ctx.delete)
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
        reload()
    }
}
