import CoreData
import Observation

/// シフト表の中身（画面が見るもの）。データベースから読み込み、取り込み・書き出しを受け持つ
@MainActor
@Observable
final class ShiftStore {
    var book = ShiftBook()
    private(set) var lastError: String?
    /// 今日（日付が変わったら更新する。開いたまま日をまたいでも「今日」の印が古くならないように）
    private(set) var today = DayKey.today

    func refreshToday() {
        let t = DayKey.today
        if t != today { today = t }
    }

    /// 編集できる状態か（初期値：見るだけ。うっかり変えないように）
    var editing = false
    /// 直前の操作（下に数秒出す「元に戻す」の表示用。消えても履歴は残る）
    private(set) var lastChange: ChangeSet?
    /// 元に戻せる操作（新しいものが最後）。まとめて入れた操作は1つとして戻る
    private(set) var undoStack: [ChangeSet] = []
    private(set) var redoStack: [ChangeSet] = []
    private let historyLimit = 50

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    struct CellChange: Equatable {
        let key: CellKey
        let before: CellEntry?
        let after: CellEntry?
        let staffName: String
    }

    /// 1回の操作（1マスでも、まとめて入れた何マスでも）
    struct ChangeSet: Equatable, Identifiable {
        let id = UUID()
        let title: String
        let changes: [CellChange]
        /// 1マスだけの操作なら、そのマス（以前の「直前の変更」と同じ使い方用）
        var key: CellKey? { changes.count == 1 ? changes[0].key : nil }
        var before: CellEntry? { changes.first?.before }
        var after: CellEntry? { changes.first?.after }
    }

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
        clearHistory()
        reload()
    }

    /// 1人×1日を変える（nil は手入力を消して、くり返し・期間の予定に戻す）
    func setCell(_ key: CellKey, to entry: CellEntry?) throws {
        let name = book.staff.first { $0.id == key.staffID }?.name ?? ""
        try setCells([(key, entry)], title: "\(name) \(key.day.month)/\(key.day.day) を変更しました")
    }

    /// 何マスかをまとめて変える（元に戻すときも1回で戻る）。変わらないマスは飛ばす
    func setCells(_ items: [(CellKey, CellEntry?)], title: String) throws {
        var changes: [CellChange] = []
        var seen = Set<CellKey>()
        for (key, entry) in items where seen.insert(key).inserted {
            let before = book.cells[key]
            guard before != entry else { continue }
            let name = book.staff.first { $0.id == key.staffID }?.name ?? ""
            changes.append(CellChange(key: key, before: before, after: entry, staffName: name))
        }
        guard !changes.isEmpty else { return }
        try write(changes.map { ($0.key, $0.after) })
        let set = ChangeSet(title: title, changes: changes)
        undoStack.append(set)
        if undoStack.count > historyLimit { undoStack.removeFirst(undoStack.count - historyLimit) }
        redoStack.removeAll()
        lastChange = set
    }

    private func write(_ items: [(CellKey, CellEntry?)]) throws {
        for (k, e) in items { try ShiftRecords.upsertCell(k, e, in: db.viewContext) }
        try db.save()
        for (k, e) in items {
            if let e { book.cells[k] = e } else { book.cells.removeValue(forKey: k) }
        }
    }

    /// いちばん新しい操作を取り消す
    func undo() throws {
        guard let set = undoStack.last else { return }
        try write(set.changes.reversed().map { ($0.key, $0.before) })
        undoStack.removeLast()
        redoStack.append(set)
        lastChange = nil
    }

    /// 取り消した操作をやり直す
    func redo() throws {
        guard let set = redoStack.last else { return }
        try write(set.changes.map { ($0.key, $0.after) })
        redoStack.removeLast()
        undoStack.append(set)
        lastChange = nil
    }

    func clearLastChange() { lastChange = nil }

    /// 履歴を消す（取り込み・消去のあとなど、戻すと食い違うとき）
    func clearHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
        lastChange = nil
    }

    /// その人に関わる履歴を消す（スタッフを消したとき）
    func dropHistory(for staffID: String) {
        undoStack.removeAll { $0.changes.contains { $0.key.staffID == staffID } }
        redoStack.removeAll { $0.changes.contains { $0.key.staffID == staffID } }
        if lastChange?.changes.contains(where: { $0.key.staffID == staffID }) == true { lastChange = nil }
    }

    /// 休憩の決まりを変える
    func setBreakRules(_ rules: BreakRules) throws {
        var b = book
        b.breakRules = rules
        // 2台で同期を始めたときにチームが2つできていても、どちらにも書く
        for team in try ShiftRecords.allTeams(db.viewContext) { try ShiftRecords.saveSettings(b, team: team) }
        try db.save()
        book.breakRules = rules
    }

    func setStaffing(_ plan: StaffingPlan) throws {
        var b = book
        b.staffing = plan
        for team in try ShiftRecords.allTeams(db.viewContext) { try ShiftRecords.saveSettings(b, team: team) }
        try db.save()
        book.staffing = plan
    }

    /// チーム全体の設定（休憩・適正人員・労務・公開の記録）を book の内容で保存する
    private func updateSettings(_ change: (inout ShiftBook) -> Void) throws {
        var b = book
        change(&b)
        for team in try ShiftRecords.allTeams(db.viewContext) { try ShiftRecords.saveSettings(b, team: team) }
        try db.save()
        book.breakRules = b.breakRules
        book.staffing = b.staffing
        book.labor = b.labor
        book.published = b.published
    }

    func setLaborRules(_ rules: LaborRules) throws { try updateSettings { $0.labor = rules } }

    /// その月をスタッフに公開した（今の内容を「公開した内容」として残す。新しい3か月分だけ持つ）
    func markPublished(_ month: MonthKey) throws {
        let snap = PublishedMonth.snapshot(of: book, month: month)
        try updateSettings { b in
            b.published.removeAll { $0.month == snap.month }
            b.published.append(snap)
            b.published = Array(b.published.sorted { $0.month < $1.month }.suffix(3))
        }
    }

    /// 希望休を変える（その人の記録だけを書き換える）
    func setOffRequests(_ days: Set<DayKey>, for staffID: String) throws {
        guard var m = book.staff.first(where: { $0.id == staffID }) else { return }
        m.offRequests = days.map(\.description).sorted()
        try save(m)
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
        /// 希望休の日（"yyyy-MM-dd"）。前の版の記録には無い
        var offRequests: [String]? = nil
    }

    static func load(_ ctx: NSManagedObjectContext) throws -> ShiftBook {
        var book = ShiftBook()

        let teams = try ctx.fetch({ () -> NSFetchRequest<NSManagedObject> in
            let r = NSFetchRequest<NSManagedObject>(entityName: ShiftModel.Entity.team)
            r.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            return r
        }())
        if teams.count > 1 { try mergeTeams(ctx) }
        if let data = teams.first(where: { $0.value(forKey: "settings") != nil })?.value(forKey: "settings") as? Data,
           let settings = try? JSONDecoder().decode(TeamSettings.self, from: data) {
            book.breakRules = settings.breakRules
            book.staffing = settings.staffing ?? StaffingPlan()
            book.labor = settings.labor ?? LaborRules()
            book.published = settings.published ?? []
        }

        book.departments = try newestByKey(fetch(ShiftModel.Entity.department, ctx), key: "key", ctx: ctx).map { r in
            Department(id: r.str("key"), name: r.str("name"), colorIndex: Palette.index(r.int("colorIndex")),
                       sortOrder: r.int("sortOrder"))
        }.sorted { $0.sortOrder < $1.sortOrder }

        book.templates = try newestByKey(fetch(ShiftModel.Entity.template, ctx), key: "key", ctx: ctx)
            .sorted { $0.int("sortOrder") < $1.int("sortOrder") }
            .map { r in
                let i = r.int("inMinutes"), o = r.int("outMinutes")
                let br = (r.value(forKey: "breakMinutes") as? NSNumber)?.intValue ?? -1
                return TimeBlock(id: r.str("key"), label: r.str("label"), short: r.str("short"),
                                 inMinutes: i < 0 ? nil : i, outMinutes: o < 0 ? nil : o,
                                 colorIndex: Palette.index(r.int("colorIndex")), breakMinutes: br < 0 ? nil : br)
            }

        let decoder = JSONDecoder()
        book.staff = try newestByKey(fetch(ShiftModel.Entity.staff, ctx), key: "key", ctx: ctx).map { r in
            let detail = (r.value(forKey: "detail") as? Data).flatMap { try? decoder.decode(StaffDetail.self, from: $0) }
            return StaffMember(id: r.str("key"), number: r.int("number"), name: r.str("name"),
                               departmentID: r.str("departmentKey"), active: r.value(forKey: "active") as? Bool ?? true,
                               joinDate: r.str("joinDate"), leaveDate: r.str("leaveDate"),
                               timeBlocks: detail?.timeBlocks ?? [], patterns: detail?.patterns ?? [],
                               activePatternID: detail?.activePatternID, periodPatterns: detail?.periodPatterns ?? [],
                               offRequests: detail?.offRequests ?? [])
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
        try saveSettings(book, team: team)
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
            r.setValue(Int32(t.breakMinutes ?? -1), forKey: "breakMinutes")
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
                                     activePatternID: s.activePatternID, periodPatterns: s.periodPatterns,
                                     offRequests: s.offRequests)
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

    /// 1人×1日の記録を書き換える（nil なら消す）。同じ人・同じ日の記録が複数あれば1つにまとめる
    static func upsertCell(_ key: CellKey, _ entry: CellEntry?, in ctx: NSManagedObjectContext) throws {
        let req = NSFetchRequest<NSManagedObject>(entityName: ShiftModel.Entity.cell)
        req.predicate = NSPredicate(format: "staffKey == %@ AND day == %@", key.staffID, key.day.description)
        let rows = try ctx.fetch(req)
        guard let entry else {
            rows.forEach(ctx.delete)
            return
        }
        let r: NSManagedObject
        if let first = rows.first {
            r = first
            rows.dropFirst().forEach(ctx.delete)
        } else {
            r = insert(ShiftModel.Entity.cell, ctx, team: try currentTeam(ctx), now: Date())
            r.setValue(key.staffID, forKey: "staffKey")
            r.setValue(key.day.description, forKey: "day")
        }
        r.setValue(entry.inTime, forKey: "inTime")
        r.setValue(entry.outTime, forKey: "outTime")
        r.setValue(entry.blockID ?? "", forKey: "blockKey")
        r.setValue(entry.isOff, forKey: "isOff")
        r.setValue(Date(), forKey: "updatedAt")
    }

    /// チーム全体の設定を保存
    static func saveSettings(_ book: ShiftBook, team: NSManagedObject) throws {
        team.setValue(try JSONEncoder().encode(TeamSettings(breakRules: book.breakRules, staffing: book.staffing,
                                                                    labor: book.labor, published: book.published)), forKey: "settings")
    }

    static func allTeams(_ ctx: NSManagedObjectContext) throws -> [NSManagedObject] {
        let req = NSFetchRequest<NSManagedObject>(entityName: ShiftModel.Entity.team)
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        let teams = try ctx.fetch(req)
        return teams.isEmpty ? [try currentTeam(ctx)] : teams
    }

    /// 2台で同期を始めると、それぞれが作った「チーム」が2つになることがある。
    /// いちばん古いチームに記録を寄せ、設定の無いほうを片付ける（記録を先に移すので、チームを消しても記録は消えない）
    static func mergeTeams(_ ctx: NSManagedObjectContext) throws {
        let req = NSFetchRequest<NSManagedObject>(entityName: ShiftModel.Entity.team)
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        let teams = try ctx.fetch(req)
        guard teams.count > 1, let keep = teams.first else { return }
        for extra in teams.dropFirst() {
            if keep.value(forKey: "settings") == nil, let s = extra.value(forKey: "settings") { keep.setValue(s, forKey: "settings") }
            for rel in ["departments", "templates", "staff", "cells"] {
                for child in (extra.value(forKey: rel) as? Set<NSManagedObject>) ?? [] { child.setValue(keep, forKey: "team") }
            }
            ctx.delete(extra)
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

    static func fetch(_ name: String, _ ctx: NSManagedObjectContext) throws -> [NSManagedObject] {
        try ctx.fetch(NSFetchRequest<NSManagedObject>(entityName: name))
    }

    static func insert(_ name: String, _ ctx: NSManagedObjectContext, team: NSManagedObject, now: Date) -> NSManagedObject {
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

/// チーム全体の設定（保存用）
struct TeamSettings: Codable {
    var breakRules: BreakRules
    /// 前の版で保存した設定には無い
    var staffing: StaffingPlan?
    var labor: LaborRules?
    var published: [PublishedMonth]?
}
