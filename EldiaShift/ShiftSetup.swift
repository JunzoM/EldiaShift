import CoreData
import Foundation

// MARK: - 部門・時間のひな形・スタッフの追加・変更・削除

extension ShiftStore {
    /// 何も無いところから始める（例として部門・ひな形を入れる。あとで変えられる）
    func startNew() throws {
        try replaceAll(with: StarterBook.make())
    }

    // 1件の保存では、データベースを読み直さず、変えたものだけ入れ替える（速さのため）

    func save(_ d: Department) throws {
        try ShiftRecords.upsert(d, in: db.viewContext)
        try db.save()
        if let i = book.departments.firstIndex(where: { $0.id == d.id }) { book.departments[i] = d } else { book.departments.append(d) }
        book.departments.sort { $0.sortOrder < $1.sortOrder }
    }

    func save(_ t: TimeBlock, sortOrder: Int? = nil) throws {
        let order = sortOrder ?? book.templates.firstIndex { $0.id == t.id } ?? book.templates.count
        try ShiftRecords.upsert(t, sortOrder: order, in: db.viewContext)
        try db.save()
        if let i = book.templates.firstIndex(where: { $0.id == t.id }) { book.templates[i] = t } else { book.templates.append(t) }
    }

    func save(_ s: StaffMember) throws {
        try ShiftRecords.upsert(s, in: db.viewContext)
        try db.save()
        if let i = book.staff.firstIndex(where: { $0.id == s.id }) { book.staff[i] = s } else { book.staff.append(s) }
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

    /// 部門の中で1つ上・下へ（番号は振り直す）
    func moveStaff(_ s: StaffMember, by delta: Int) throws {
        var list = book.staff.filter { $0.departmentID == s.departmentID }.sorted(by: StaffMember.order)
        guard let i = list.firstIndex(where: { $0.id == s.id }), list.indices.contains(i + delta) else { return }
        list.swapAt(i, i + delta)
        try reorderStaff(list)
    }

    /// 部署の一括移動：移動元の全員を、移動先の末尾に（並び順を保って）付け替える（PC版と同じ）
    func moveAllStaff(from: String, to: String) throws {
        guard from != to else { return }
        let last = book.staff.filter { $0.departmentID == to }.map(\.number).max() ?? 0
        let moving = book.staff.filter { $0.departmentID == from }.sorted(by: StaffMember.order)
        for (i, original) in moving.enumerated() {
            var m = original
            m.departmentID = to
            m.number = last + i + 1
            try ShiftRecords.upsert(m, in: db.viewContext)
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
        // 同じ部門の番号を詰める（PC版と同じ）
        let rest = book.staff.filter { $0.departmentID == s.departmentID && $0.id != s.id }.sorted(by: StaffMember.order)
        for (i, original) in rest.enumerated() where original.number != i + 1 {
            var m = original
            m.number = i + 1
            try ShiftRecords.upsert(m, in: db.viewContext)
        }
        try db.save()
        dropHistory(for: s.id)
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

    /// 新しい部門（いま見ている店舗に作る）
    func newDepartment() -> Department {
        Department(id: UUID().uuidString, name: "", colorIndex: book.departments.count % Palette.colors.count,
                   sortOrder: (book.departments.map(\.sortOrder).max() ?? -1) + 1, storeID: currentStoreID)
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
        r.setValue(d.storeID, forKey: "storeKey")
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
        r.setValue(Int32(t.breakMinutes ?? -1), forKey: "breakMinutes")
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
        r.setValue(try JSONEncoder().encode(StaffDetail(s)), forKey: "detail")
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

// MARK: - データ管理（すべて消去・自動バックアップ）

extension ShiftStore {
    /// 自動バックアップの置き場所（「ファイル」アプリの「このiPad内」→「シフト表」→「自動バックアップ」から見られる）
    nonisolated static var autoBackupFolder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("自動バックアップ", isDirectory: true)
    }

    /// 今の内容をファイルに残す（消す・読み込む前に呼ぶ）。新しい30件だけ残す
    @discardableResult
    func autoBackup(reason: String) throws -> URL? {
        guard !book.isEmpty else { return nil }
        let dir = Self.autoBackupFolder
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let url = dir.appendingPathComponent("shift-\(f.string(from: Date()))-\(reason).json")
        try exportData().write(to: url, options: .atomic)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for old in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).dropFirst(30) {
            try? FileManager.default.removeItem(at: old)
        }
        return url
    }

    /// スタッフ・共通の時間・入力したシフトをすべて消す（部署と休みの種類は残す。PC版と同じ）
    func resetAll() throws {
        try autoBackup(reason: "消去前")
        var kept = ShiftBook()
        kept.departments = book.departments
        kept.stores = book.stores
        kept.brandColor = book.brandColor
        kept.breakRules = book.breakRules
        kept.staffing = book.staffing
        kept.labor = book.labor
        kept.pay = book.pay
        kept.templates = book.templates.filter(\.isOff)
        if kept.templates.isEmpty { kept.templates = BackupFile.defaultOffBlocks }
        try replaceAll(with: kept)
    }
}
