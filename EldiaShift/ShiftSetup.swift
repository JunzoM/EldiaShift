import CoreData
import Foundation

// MARK: - 部門・時間のひな形・スタッフの追加・変更・削除

extension ShiftStore {
    /// 何も無いところから始める（例として部門・ひな形を入れる。あとで変えられる）
    func startNew() throws {
        try replaceAll(with: StarterBook.make())
    }

    func save(_ d: Department) throws {
        try ShiftRecords.upsert(d, in: db.viewContext)
        try db.save()
        reload()
    }

    func save(_ t: TimeBlock, sortOrder: Int? = nil) throws {
        let order = sortOrder ?? book.templates.firstIndex { $0.id == t.id } ?? book.templates.count
        try ShiftRecords.upsert(t, sortOrder: order, in: db.viewContext)
        try db.save()
        reload()
    }

    func save(_ s: StaffMember) throws {
        try ShiftRecords.upsert(s, in: db.viewContext)
        try db.save()
        reload()
    }

    /// 部門の並び替え（表の上からの順）
    func reorderDepartments(_ ordered: [Department]) throws {
        for (i, original) in ordered.enumerated() where original.sortOrder != i {
            var d = original
            d.sortOrder = i
            try ShiftRecords.upsert(d, in: db.viewContext)
        }
        try db.save()
        reload()
    }

    func reorderTemplates(_ ordered: [TimeBlock]) throws {
        for (i, t) in ordered.enumerated() {
            try ShiftRecords.upsert(t, sortOrder: i, in: db.viewContext)
        }
        try db.save()
        reload()
    }

    /// 部門の中のスタッフの並び替え
    func reorderStaff(_ ordered: [StaffMember]) throws {
        for (i, original) in ordered.enumerated() where original.number != i + 1 {
            var s = original
            s.number = i + 1
            try ShiftRecords.upsert(s, in: db.viewContext)
        }
        try db.save()
        reload()
    }

    /// 部門を消す（スタッフがいる部門は消さない）
    func deleteDepartment(_ d: Department) throws {
        guard !book.staff.contains(where: { $0.departmentID == d.id }) else { throw SetupError.departmentInUse }
        try ShiftRecords.delete(ShiftModel.Entity.department, key: d.id, in: db.viewContext)
        try db.save()
        reload()
    }

    func deleteTemplate(_ t: TimeBlock) throws {
        try ShiftRecords.delete(ShiftModel.Entity.template, key: t.id, in: db.viewContext)
        try db.save()
        reload()
    }

    /// スタッフを消す（その人のシフトも消す）
    func deleteStaff(_ s: StaffMember) throws {
        try ShiftRecords.delete(ShiftModel.Entity.staff, key: s.id, in: db.viewContext)
        let req = NSFetchRequest<NSManagedObject>(entityName: ShiftModel.Entity.cell)
        req.predicate = NSPredicate(format: "staffKey == %@", s.id)
        try db.viewContext.fetch(req).forEach(db.viewContext.delete)
        try db.save()
        if lastChange?.key.staffID == s.id { clearLastChange() }
        reload()
    }

    /// そのひな形を使っている数（週のくり返し・期間の予定・手入力）
    func usageCount(of templateID: String) -> Int {
        var n = book.cells.values.filter { $0.blockID == templateID }.count
        for s in book.staff {
            for p in s.patterns { n += p.days.filter { $0 == templateID }.count }
            for p in s.periodPatterns { n += p.days.values.filter { $0 == templateID }.count }
        }
        return n
    }

    func newStaff(in departmentID: String) -> StaffMember {
        let last = book.staff.filter { $0.departmentID == departmentID }.map(\.number).max() ?? 0
        return StaffMember(id: UUID().uuidString, number: last + 1, name: "", departmentID: departmentID, active: true,
                           joinDate: "", leaveDate: "", timeBlocks: [], patterns: [], activePatternID: nil, periodPatterns: [])
    }

    func newDepartment() -> Department {
        Department(id: UUID().uuidString, name: "", colorIndex: book.departments.count % Palette.colors.count,
                   sortOrder: (book.departments.map(\.sortOrder).max() ?? -1) + 1)
    }

    func newTemplate(off: Bool) -> TimeBlock {
        TimeBlock(id: UUID().uuidString, label: "", short: "", inMinutes: off ? nil : 9 * 60,
                  outMinutes: off ? nil : 18 * 60, colorIndex: off ? 4 : 0)
    }
}

enum SetupError: LocalizedError {
    case departmentInUse

    var errorDescription: String? {
        switch self {
        case .departmentInUse: "この部門にはスタッフがいるため消せません。先にスタッフを別の部門へ移してください。"
        }
    }
}

extension ShiftRecords {
    static func upsert(_ d: Department, in ctx: NSManagedObjectContext) throws {
        let r = try record(ShiftModel.Entity.department, key: d.id, in: ctx)
        r.setValue(d.name, forKey: "name")
        r.setValue(Int16(d.colorIndex), forKey: "colorIndex")
        r.setValue(Int32(clamping: d.sortOrder), forKey: "sortOrder")
        r.setValue(Date(), forKey: "updatedAt")
    }

    static func upsert(_ t: TimeBlock, sortOrder: Int, in ctx: NSManagedObjectContext) throws {
        let r = try record(ShiftModel.Entity.template, key: t.id, in: ctx)
        r.setValue(t.label, forKey: "label")
        r.setValue(t.short, forKey: "short")
        r.setValue(Int32(t.inMinutes ?? -1), forKey: "inMinutes")
        r.setValue(Int32(t.outMinutes ?? -1), forKey: "outMinutes")
        r.setValue(Int16(t.colorIndex), forKey: "colorIndex")
        r.setValue(Int32(clamping: sortOrder), forKey: "sortOrder")
        r.setValue(Date(), forKey: "updatedAt")
    }

    static func upsert(_ s: StaffMember, in ctx: NSManagedObjectContext) throws {
        let r = try record(ShiftModel.Entity.staff, key: s.id, in: ctx)
        r.setValue(Int32(clamping: s.number), forKey: "number")
        r.setValue(s.name, forKey: "name")
        r.setValue(s.departmentID, forKey: "departmentKey")
        r.setValue(s.active, forKey: "active")
        r.setValue(s.joinDate, forKey: "joinDate")
        r.setValue(s.leaveDate, forKey: "leaveDate")
        let detail = StaffDetail(timeBlocks: s.timeBlocks, patterns: s.patterns,
                                 activePatternID: s.activePatternID, periodPatterns: s.periodPatterns)
        r.setValue(try JSONEncoder().encode(detail), forKey: "detail")
        r.setValue(Date(), forKey: "updatedAt")
    }

    static func delete(_ entity: String, key: String, in ctx: NSManagedObjectContext) throws {
        let req = NSFetchRequest<NSManagedObject>(entityName: entity)
        req.predicate = NSPredicate(format: "key == %@", key)
        try ctx.fetch(req).forEach(ctx.delete)
    }

    /// そのキーの記録（無ければ作る。重複していれば1つにまとめる）
    private static func record(_ entity: String, key: String, in ctx: NSManagedObjectContext) throws -> NSManagedObject {
        let req = NSFetchRequest<NSManagedObject>(entityName: entity)
        req.predicate = NSPredicate(format: "key == %@", key)
        let rows = try ctx.fetch(req)
        if let first = rows.first {
            rows.dropFirst().forEach(ctx.delete)
            return first
        }
        let r = insert(entity, ctx, team: try currentTeam(ctx), now: Date())
        r.setValue(key, forKey: "key")
        return r
    }
}

// MARK: - 新しく始めるときの例

enum StarterBook {
    static func make() -> ShiftBook {
        var b = ShiftBook()
        b.departments = [
            Department(id: UUID().uuidString, name: "ホール", colorIndex: 0, sortOrder: 0),
            Department(id: UUID().uuidString, name: "キッチン", colorIndex: 2, sortOrder: 1)
        ]
        b.templates = [
            TimeBlock(id: UUID().uuidString, label: "早番", short: "早", inMinutes: 9 * 60, outMinutes: 18 * 60, colorIndex: 2),
            TimeBlock(id: UUID().uuidString, label: "遅番", short: "遅", inMinutes: 13 * 60, outMinutes: 22 * 60, colorIndex: 3),
            TimeBlock(id: UUID().uuidString, label: "夜勤", short: "夜", inMinutes: 22 * 60, outMinutes: 9 * 60, colorIndex: 8)
        ] + BackupFile.defaultOffBlocks
        return b
    }
}
