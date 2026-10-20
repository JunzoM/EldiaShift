import CoreData
import Observation

/// シフト表の中身（画面が見るもの）。データベースから読み込み、取り込み・書き出しを受け持つ
@MainActor
@Observable
final class ShiftStore {
    private(set) var book = ShiftBook()
    private(set) var lastError: String?

    @ObservationIgnored let db: ShiftDatabase
    @ObservationIgnored private var loadedToken = -1

    init(db: ShiftDatabase) {
        self.db = db
        reload()
    }

    /// iCloud から変更が届いていたら読み直す
    func refreshIfNeeded() {
        if loadedToken != db.changeToken { reload() }
    }

    func reload() {
        loadedToken = db.changeToken
        do {
            book = try ShiftRecords.load(db.viewContext)
            lastError = nil
        } catch {
            lastError = "読み込めませんでした（\(error.localizedDescription)）"
        }
    }

    /// バックアップから取り込み、今の内容をすべて置き換える
    func replaceAll(with newBook: ShiftBook) throws {
        try ShiftRecords.replaceAll(with: newBook, in: db.viewContext)
        try db.save()
        reload()
    }

    func exportData() throws -> Data {
        try BackupFile.write(book)
    }
}

/// Core Data の記録 ⇔ ShiftBook の変換
enum ShiftRecords {
    /// スタッフ1人分の、個人のひな形・くり返し（JSON で1項目に入れる）
    struct StaffDetail: Codable {
        var timeBlocks: [TimeBlock]
        var patterns: [WeekPattern]
        var activePatternID: String?
        var periodPatterns: [PeriodPattern]
    }

    static func load(_ ctx: NSManagedObjectContext) throws -> ShiftBook {
        var book = ShiftBook()

        book.departments = try newestByKey(fetch(ShiftModel.Entity.department, ctx), key: "key", ctx: ctx).map { r in
            Department(id: r.str("key"), name: r.str("name"), colorIndex: Palette.index(r.int("colorIndex")),
                       sortOrder: r.int("sortOrder"))
        }.sorted { $0.sortOrder < $1.sortOrder }

        book.templates = try newestByKey(fetch(ShiftModel.Entity.template, ctx), key: "key", ctx: ctx)
            .sorted { $0.int("sortOrder") < $1.int("sortOrder") }
            .map { r in
                let i = r.int("inMinutes"), o = r.int("outMinutes")
                return TimeBlock(id: r.str("key"), label: r.str("label"), short: r.str("short"),
                                 inMinutes: i < 0 ? nil : i, outMinutes: o < 0 ? nil : o,
                                 colorIndex: Palette.index(r.int("colorIndex")))
            }

        let decoder = JSONDecoder()
        book.staff = try newestByKey(fetch(ShiftModel.Entity.staff, ctx), key: "key", ctx: ctx).map { r in
            let detail = (r.value(forKey: "detail") as? Data).flatMap { try? decoder.decode(StaffDetail.self, from: $0) }
            return StaffMember(id: r.str("key"), number: r.int("number"), name: r.str("name"),
                               departmentID: r.str("departmentKey"), active: r.value(forKey: "active") as? Bool ?? true,
                               joinDate: r.str("joinDate"), leaveDate: r.str("leaveDate"),
                               timeBlocks: detail?.timeBlocks ?? [], patterns: detail?.patterns ?? [],
                               activePatternID: detail?.activePatternID, periodPatterns: detail?.periodPatterns ?? [])
        }

        for r in try newestByKey(fetch(ShiftModel.Entity.cell, ctx), keyOf: { "\($0.str("staffKey"))|\($0.str("day"))" }, ctx: ctx) {
            guard let day = DayKey(r.str("day")) else { continue }
            let block = r.str("blockKey")
            book.cells[CellKey(staffID: r.str("staffKey"), day: day)] = CellEntry(
                inTime: r.str("inTime"), outTime: r.str("outTime"),
                blockID: block.isEmpty ? nil : block, isOff: r.value(forKey: "isOff") as? Bool ?? false)
        }
        if ctx.hasChanges { try ctx.save() }   // 重複を片付けた分
        return book
    }

    static func replaceAll(with book: ShiftBook, in ctx: NSManagedObjectContext) throws {
        let team = try currentTeam(ctx)
        for name in [ShiftModel.Entity.department, ShiftModel.Entity.template, ShiftModel.Entity.staff, ShiftModel.Entity.cell] {
            for r in try fetch(name, ctx) { ctx.delete(r) }
        }
        let now = Date()

        for d in book.departments {
            let r = insert(ShiftModel.Entity.department, ctx, team: team, now: now)
            r.setValue(d.id, forKey: "key")
            r.setValue(d.name, forKey: "name")
            r.setValue(Int16(d.colorIndex), forKey: "colorIndex")
            r.setValue(Int32(clamping: d.sortOrder), forKey: "sortOrder")
        }
        for (i, t) in book.templates.enumerated() {
            let r = insert(ShiftModel.Entity.template, ctx, team: team, now: now)
            r.setValue(t.id, forKey: "key")
            r.setValue(t.label, forKey: "label")
            r.setValue(t.short, forKey: "short")
            r.setValue(Int32(t.inMinutes ?? -1), forKey: "inMinutes")
            r.setValue(Int32(t.outMinutes ?? -1), forKey: "outMinutes")
            r.setValue(Int16(t.colorIndex), forKey: "colorIndex")
            r.setValue(Int32(i), forKey: "sortOrder")
        }
        let encoder = JSONEncoder()
        for s in book.staff {
            let r = insert(ShiftModel.Entity.staff, ctx, team: team, now: now)
            r.setValue(s.id, forKey: "key")
            r.setValue(Int32(clamping: s.number), forKey: "number")
            r.setValue(s.name, forKey: "name")
            r.setValue(s.departmentID, forKey: "departmentKey")
            r.setValue(s.active, forKey: "active")
            r.setValue(s.joinDate, forKey: "joinDate")
            r.setValue(s.leaveDate, forKey: "leaveDate")
            let detail = StaffDetail(timeBlocks: s.timeBlocks, patterns: s.patterns,
                                     activePatternID: s.activePatternID, periodPatterns: s.periodPatterns)
            r.setValue(try encoder.encode(detail), forKey: "detail")
        }
        for (k, c) in book.cells {
            let r = insert(ShiftModel.Entity.cell, ctx, team: team, now: now)
            r.setValue(k.staffID, forKey: "staffKey")
            r.setValue(k.day.description, forKey: "day")
            r.setValue(c.inTime, forKey: "inTime")
            r.setValue(c.outTime, forKey: "outTime")
            r.setValue(c.blockID ?? "", forKey: "blockKey")
            r.setValue(c.isOff, forKey: "isOff")
        }
    }

    /// このアプリのチーム（無ければ作る。複数あれば一番古いもの）
    static func currentTeam(_ ctx: NSManagedObjectContext) throws -> NSManagedObject {
        let req = NSFetchRequest<NSManagedObject>(entityName: ShiftModel.Entity.team)
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        if let t = try ctx.fetch(req).first { return t }
        let t = NSEntityDescription.insertNewObject(forEntityName: ShiftModel.Entity.team, into: ctx)
        t.setValue(UUID(), forKey: "id")
        t.setValue("シフト表", forKey: "name")
        t.setValue(Date(), forKey: "createdAt")
        return t
    }

    // MARK: 部品

    private static func fetch(_ name: String, _ ctx: NSManagedObjectContext) throws -> [NSManagedObject] {
        try ctx.fetch(NSFetchRequest<NSManagedObject>(entityName: name))
    }

    private static func insert(_ name: String, _ ctx: NSManagedObjectContext, team: NSManagedObject, now: Date) -> NSManagedObject {
        let r = NSEntityDescription.insertNewObject(forEntityName: name, into: ctx)
        r.setValue(team, forKey: "team")
        r.setValue(now, forKey: "updatedAt")
        return r
    }

    private static func newestByKey(_ rows: [NSManagedObject], key: String, ctx: NSManagedObjectContext) -> [NSManagedObject] {
        newestByKey(rows, keyOf: { $0.str(key) }, ctx: ctx)
    }

    /// 同じキーの記録が複数あれば、更新日時の新しいものを残してほかは消す
    static func newestByKey(_ rows: [NSManagedObject], keyOf: (NSManagedObject) -> String, ctx: NSManagedObjectContext) -> [NSManagedObject] {
        var keep: [String: NSManagedObject] = [:]
        for r in rows {
            let k = keyOf(r)
            guard !k.isEmpty else { ctx.delete(r); continue }
            if let old = keep[k] {
                let a = old.value(forKey: "updatedAt") as? Date ?? .distantPast
                let b = r.value(forKey: "updatedAt") as? Date ?? .distantPast
                if b > a { ctx.delete(old); keep[k] = r } else { ctx.delete(r) }
            } else {
                keep[k] = r
            }
        }
        return Array(keep.values)
    }
}

private extension NSManagedObject {
    func str(_ key: String) -> String { value(forKey: key) as? String ?? "" }
    func int(_ key: String) -> Int { (value(forKey: key) as? NSNumber)?.intValue ?? 0 }
}
