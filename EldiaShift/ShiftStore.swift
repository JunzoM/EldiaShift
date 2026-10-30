import CoreData
import Observation

/// シフト表の中身（画面が見るもの）。データベースから読み込み、取り込み・書き出しを受け持つ
@MainActor
@Observable
final class ShiftStore {
    var book = ShiftBook() { didSet { revision &+= 1 } }
    /// book が変わるたびに増える番号（重い計算を、中身が変わったときだけやり直すための目印）
    @ObservationIgnored private(set) var revision = 0
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

    // MARK: 店舗

    /// いま見ている店舗（端末ごとに覚える）
    var currentStoreID: String {
        get { book.scopeStoreID ?? book.allStores[0].id }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.storeKey)
            book.scopeStoreID = validStore(newValue)
            clearLastChange()
        }
    }

    var currentStore: Store { book.store(currentStoreID) ?? book.allStores[0] }

    private static let storeKey = "currentStoreID"

    private func validStore(_ id: String?) -> String {
        let all = book.allStores
        return all.first { $0.id == id }?.id ?? all[0].id
    }

    /// 読み込んだあと、見ている店舗を当てはめ直す（消した店舗なら最初の店舗）
    private func applyScope() {
        book.scopeStoreID = validStore(UserDefaults.standard.string(forKey: Self.storeKey))
    }

    func reload() {
        loadedToken = db.changeToken
        do {
            book = try ShiftRecords.load(db.viewContext)
            applyScope()
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
        for (key, given) in items where seen.insert(key).inserted {
            // 時刻だけ変えたときもメモは残す（メモを消すときは空の文字を渡す）
            var raw = given
            if var e = raw {
                if e.note == nil { e.note = book.cells[key]?.note }
                if e.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true { e.note = nil }
                raw = e
            }
            let entry = stamped(raw, for: key.staffID)
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

    /// 勤務の店舗を決める。店舗を指定していない勤務は「いま見ている店舗」で入れる
    /// （その人の店舗なら空にする。休みは店舗を持たない）
    func stamped(_ entry: CellEntry?, for staffID: String) -> CellEntry? {
        guard var e = entry else { return nil }
        guard !e.isOff, let m = book.staff.first(where: { $0.id == staffID }) else {
            e.storeID = nil
            return e
        }
        let home = book.homeStoreID(of: m)
        let target = e.storeID ?? book.scopeStoreID ?? home
        // 入れない店舗（掛け持ちしていない店舗）は、その人の店舗にする
        e.storeID = (target == home || !book.storeIDs(of: m).contains(target)) ? nil : target
        return e
    }

    private func write(_ items: [(CellKey, CellEntry?)]) throws {
        // 1マスずつ探さず、関係する日の記録を1回でまとめて読んでから書き換える
        try ShiftRecords.upsertCells(items, in: db.viewContext)
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
        // 2台で同期を始めたときにチームが2つできていても、どちらにも書く（共有されたシフト表なら、そのチームだけ）
        for team in try ShiftRecords.settingsTeams(db.viewContext) { try ShiftRecords.saveSettings(b, team: team) }
        try db.save()
        book.breakRules = rules
    }

    func setStaffing(_ plan: StaffingPlan) throws {
        var b = book
        b.staffing = plan
        for team in try ShiftRecords.settingsTeams(db.viewContext) { try ShiftRecords.saveSettings(b, team: team) }
        try db.save()
        book.staffing = plan
    }

    /// チーム全体の設定（休憩・適正人員・労務・公開の記録）を book の内容で保存する
    private func updateSettings(_ change: (inout ShiftBook) -> Void) throws {
        var b = book
        change(&b)
        for team in try ShiftRecords.settingsTeams(db.viewContext) { try ShiftRecords.saveSettings(b, team: team) }
        try db.save()
        book.breakRules = b.breakRules
        book.staffing = b.staffing
        book.labor = b.labor
        book.pay = b.pay
        book.company = b.company
        book.published = b.published
        book.stores = b.stores
        book.brandColor = b.brandColor
        applyScope()
    }

    /// 店舗を足す・変える
    func save(_ st: Store) throws {
        try updateSettings { b in
            if b.stores.isEmpty { b.stores = [Store.makeDefault()] }   // 前の版の「本店」を残す
            if let i = b.stores.firstIndex(where: { $0.id == st.id }) { b.stores[i] = st } else { b.stores.append(st) }
        }
    }

    /// 店舗を消す（部門がある店舗・最後の1つは消さない）。掛け持ち先からも外す
    func deleteStore(_ st: Store) throws {
        guard book.allStores.count > 1 else { throw StoreError.lastStore }
        guard book.departments(in: st.id).isEmpty else { throw StoreError.storeInUse }
        try updateSettings { b in
            if b.stores.isEmpty { b.stores = [Store.makeDefault()] }
            b.stores.removeAll { $0.id == st.id }
        }
        for var m in book.staff where m.extraStoreIDs.contains(st.id) {
            m.extraStoreIDs.removeAll { $0 == st.id }
            try save(m)
        }
    }

    /// 何店舗かをまとめて外す（見本のデータを消すとき。部門・スタッフは先に消しておく）
    func removeStores(_ ids: Set<String>) throws {
        guard !ids.isEmpty else { return }
        try updateSettings { b in
            b.stores.removeAll { ids.contains($0.id) }
            if b.stores.isEmpty { b.stores = [Store.makeDefault()] }
        }
    }

    func reorderStores(_ ordered: [Store]) throws {
        try updateSettings { b in
            b.stores = ordered.enumerated().map { i, s in var x = s; x.sortOrder = i; return x }
        }
    }

    func newStore() -> Store {
        Store(id: UUID().uuidString, name: "", colorIndex: book.allStores.count % Palette.colors.count,
              sortOrder: (book.allStores.map(\.sortOrder).max() ?? -1) + 1)
    }

    /// 会社の色（nil で標準の色に戻す）
    func setBrandColor(_ hex: UInt32?) throws { try updateSettings { $0.brandColor = hex } }

    func setLaborRules(_ rules: LaborRules) throws { try updateSettings { $0.labor = rules } }

    func setPayRules(_ rules: PayRules) throws { try updateSettings { $0.pay = rules } }

    func setCompany(_ c: CompanyInfo) throws { try updateSettings { $0.company = c } }

    /// その月をスタッフに公開した（今の内容を「公開した内容」として残す。新しい3か月分だけ持つ）
    func markPublished(_ month: MonthKey) throws {
        let snap = PublishedMonth.snapshot(of: book, month: month)
        let n = book.allStores.count
        try updateSettings { b in
            b.published.removeAll { $0.month == snap.month }
            b.published.append(snap)
            // 店舗ごとに新しい3か月分
            b.published = Array(b.published.sorted { $0.month < $1.month }.suffix(3 * n))
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
        /// 掛け持ち先の店舗。前の版の記録には無い
        var extraStoreIDs: [String]? = nil
        /// 雇用形態・顔写真。前の版の記録には無い
        var employment: String? = nil
        var photo: Data? = nil
        /// 給与の決まり。1.1 までの記録にだけある（1.2 からは PayRecord に入れ、ここには書かない。共有されないように）
        var wages: [WageEntry]? = nil
        /// 希望休の申請。前の版の記録には無い
        var leaveRequests: [LeaveRequest]? = nil

        init(_ s: StaffMember) {
            timeBlocks = s.timeBlocks
            patterns = s.patterns
            activePatternID = s.activePatternID
            periodPatterns = s.periodPatterns
            offRequests = s.offRequests
            extraStoreIDs = s.extraStoreIDs
            employment = s.employment.isEmpty ? nil : s.employment
            photo = s.photo
            wages = nil
            leaveRequests = s.leaveRequests.isEmpty ? nil : s.leaveRequests
        }
    }

    /// 表示するチーム（端末ごとに覚えたもの。nil は自分のシフト表）。ShiftDatabase が入れる
    nonisolated(unsafe) static var activeTeamID: UUID?

    static func load(_ ctx: NSManagedObjectContext) throws -> ShiftBook {
        var book = ShiftBook()

        if try ownTeams(ctx).count > 1 { try mergeTeams(ctx) }
        let team = try currentTeam(ctx)
        let theirs = ShiftDatabase.isShared(team.objectID.persistentStore)
        if let data = team.value(forKey: "settings") as? Data,
           let settings = try? JSONDecoder().decode(TeamSettings.self, from: data) {
            book.breakRules = settings.breakRules
            book.staffing = settings.staffing ?? StaffingPlan()
            book.labor = settings.labor ?? LaborRules()
            book.pay = settings.pay ?? PayRules()
            book.company = settings.company ?? CompanyInfo()
            book.published = settings.published ?? []
            book.stores = settings.stores ?? []
            book.brandColor = settings.brandColor
        }

        book.departments = try newestByKey(fetch(ShiftModel.Entity.department, ctx, team: team), key: "key", ctx: ctx).map { r in
            Department(id: r.str("key"), name: r.str("name"), colorIndex: Palette.index(r.int("colorIndex")),
                       sortOrder: r.int("sortOrder"), storeID: r.str("storeKey"))
        }.sorted { $0.sortOrder < $1.sortOrder }

        book.templates = try newestByKey(fetch(ShiftModel.Entity.template, ctx, team: team), key: "key", ctx: ctx)
            .sorted { $0.int("sortOrder") < $1.int("sortOrder") }
            .map { r in
                let i = r.int("inMinutes"), o = r.int("outMinutes")
                let br = (r.value(forKey: "breakMinutes") as? NSNumber)?.intValue ?? -1
                return TimeBlock(id: r.str("key"), label: r.str("label"), short: r.str("short"),
                                 inMinutes: i < 0 ? nil : i, outMinutes: o < 0 ? nil : o,
                                 colorIndex: Palette.index(r.int("colorIndex")), breakMinutes: br < 0 ? nil : br)
            }

        let decoder = JSONDecoder()
        // 給与は自分だけの入れ物から（無ければ、前の版でスタッフの記録に入れた給与。共有されたシフト表のものは使わない）
        var pays = Dictionary(newestByKey(try ctx.fetch(NSFetchRequest<NSManagedObject>(entityName: ShiftModel.Entity.pay)), key: "key", ctx: ctx)
            .map { ($0.str("key"), $0) }, uniquingKeysWith: { a, _ in a })
        book.staff = try newestByKey(fetch(ShiftModel.Entity.staff, ctx, team: team), key: "key", ctx: ctx).map { r -> StaffMember in
            let detail = (r.value(forKey: "detail") as? Data).flatMap { try? decoder.decode(StaffDetail.self, from: $0) }
            let key = r.str("key")
            let oldWages = theirs ? [] : (detail?.wages ?? [])
            if !oldWages.isEmpty, var d = detail {
                // 前の版の給与を、自分だけの入れ物へ移す（入れ物にもう入っていれば、そちらを使う）
                if pays[key] == nil { pays[key] = try upsertPay(key, oldWages, in: ctx) }
                d.wages = nil
                r.setValue(try JSONEncoder().encode(d), forKey: "detail")
            }
            let staffWages = pays[key].map { Self.wages(of: $0) } ?? oldWages
            return StaffMember(id: r.str("key"), number: r.int("number"), name: r.str("name"),
                               departmentID: r.str("departmentKey"), active: r.value(forKey: "active") as? Bool ?? true,
                               joinDate: r.str("joinDate"), leaveDate: r.str("leaveDate"),
                               timeBlocks: detail?.timeBlocks ?? [], patterns: detail?.patterns ?? [],
                               activePatternID: detail?.activePatternID, periodPatterns: detail?.periodPatterns ?? [],
                               offRequests: detail?.offRequests ?? [], extraStoreIDs: detail?.extraStoreIDs ?? [],
                               employment: detail?.employment ?? "", photo: detail?.photo, wages: staffWages,
                               leaveRequests: detail?.leaveRequests ?? [])
        }

        for r in try newestByKey(fetch(ShiftModel.Entity.cell, ctx, team: team), keyOf: { "\($0.str("staffKey"))|\($0.str("day"))" }, ctx: ctx) {
            guard let day = DayKey(r.str("day")) else { continue }
            let block = r.str("blockKey")
            let st = r.str("storeKey")
            let note = r.str("note")
            book.cells[CellKey(staffID: r.str("staffKey"), day: day)] = CellEntry(
                inTime: r.str("inTime"), outTime: r.str("outTime"),
                blockID: block.isEmpty ? nil : block, isOff: r.value(forKey: "isOff") as? Bool ?? false,
                storeID: st.isEmpty ? nil : st, note: note.isEmpty ? nil : note)
        }
        // 重複を片付けた分・給与を移した分。「見るだけ」で共有されたシフト表は保存できないので、そのときは取り消す
        if ctx.hasChanges {
            do { try ctx.save() } catch { ctx.rollback() }
        }
        return book
    }

    /// 給与の記録を書く（無ければ作る。自分のデータの入れ物に入る）
    @discardableResult
    static func upsertPay(_ staffID: String, _ wages: [WageEntry], in ctx: NSManagedObjectContext) throws -> NSManagedObject? {
        let req = NSFetchRequest<NSManagedObject>(entityName: ShiftModel.Entity.pay)
        req.predicate = NSPredicate(format: "key == %@", staffID)
        let rows = try ctx.fetch(req)
        if rows.isEmpty && wages.isEmpty { return nil }
        let r = rows.first ?? NSEntityDescription.insertNewObject(forEntityName: ShiftModel.Entity.pay, into: ctx)
        rows.dropFirst().forEach(ctx.delete)
        r.setValue(staffID, forKey: "key")
        r.setValue(try JSONEncoder().encode(wages), forKey: "wages")
        r.setValue(Date(), forKey: "updatedAt")
        return r
    }

    static func wages(of r: NSManagedObject) -> [WageEntry] {
        (r.value(forKey: "wages") as? Data).flatMap { try? JSONDecoder().decode([WageEntry].self, from: $0) } ?? []
    }

    /// 共有を作る前に：自分のシフト表のスタッフの記録に残っている給与（前の版の書き方）を、自分だけの入れ物へ移して消す
    static func stripWagesFromStaff(in ctx: NSManagedObjectContext) throws {
        let team = try currentTeam(ctx)
        guard !ShiftDatabase.isShared(team.objectID.persistentStore) else { return }
        let decoder = JSONDecoder()
        for r in try fetch(ShiftModel.Entity.staff, ctx, team: team) {
            guard let data = r.value(forKey: "detail") as? Data, var d = try? decoder.decode(StaffDetail.self, from: data),
                  let old = d.wages, !old.isEmpty else { continue }
            let req = NSFetchRequest<NSManagedObject>(entityName: ShiftModel.Entity.pay)
            req.predicate = NSPredicate(format: "key == %@", r.str("key"))
            if try ctx.fetch(req).isEmpty { try upsertPay(r.str("key"), old, in: ctx) }
            d.wages = nil
            r.setValue(try JSONEncoder().encode(d), forKey: "detail")
        }
    }

    static func replaceAll(with book: ShiftBook, in ctx: NSManagedObjectContext) throws {
        let team = try currentTeam(ctx)
        try saveSettings(book, team: team)
        for name in [ShiftModel.Entity.department, ShiftModel.Entity.template, ShiftModel.Entity.staff, ShiftModel.Entity.cell] {
            for r in try fetch(name, ctx, team: team) { ctx.delete(r) }
        }
        let now = Date()

        for d in book.departments {
            let r = insert(ShiftModel.Entity.department, ctx, team: team, now: now)
            r.setValue(d.id, forKey: "key")
            r.setValue(d.name, forKey: "name")
            r.setValue(Int16(d.colorIndex), forKey: "colorIndex")
            r.setValue(Int32(clamping: d.sortOrder), forKey: "sortOrder")
            r.setValue(d.storeID, forKey: "storeKey")
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
            r.setValue(try encoder.encode(StaffDetail(s)), forKey: "detail")
            try upsertPay(s.id, s.wages, in: ctx)
        }
        for (k, c) in book.cells {
            let r = insert(ShiftModel.Entity.cell, ctx, team: team, now: now)
            r.setValue(k.staffID, forKey: "staffKey")
            r.setValue(k.day.description, forKey: "day")
            r.setValue(c.inTime, forKey: "inTime")
            r.setValue(c.outTime, forKey: "outTime")
            r.setValue(c.blockID ?? "", forKey: "blockKey")
            r.setValue(c.isOff, forKey: "isOff")
            r.setValue(c.storeID ?? "", forKey: "storeKey")
            r.setValue(c.note ?? "", forKey: "note")
        }
    }

    /// 1人×1日の記録を書き換える（nil なら消す）。同じ人・同じ日の記録が複数あれば1つにまとめる
    static func upsertCell(_ key: CellKey, _ entry: CellEntry?, in ctx: NSManagedObjectContext) throws {
        let team = try currentTeam(ctx)
        let req = request(ShiftModel.Entity.cell, NSPredicate(format: "staffKey == %@ AND day == %@", key.staffID, key.day.description),
                          team: team, ctx: ctx)
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
            r = insert(ShiftModel.Entity.cell, ctx, team: team, now: Date())
            r.setValue(key.staffID, forKey: "staffKey")
            r.setValue(key.day.description, forKey: "day")
        }
        r.setValue(entry.inTime, forKey: "inTime")
        r.setValue(entry.outTime, forKey: "outTime")
        r.setValue(entry.blockID ?? "", forKey: "blockKey")
        r.setValue(entry.isOff, forKey: "isOff")
        r.setValue(entry.storeID ?? "", forKey: "storeKey")
        r.setValue(entry.note ?? "", forKey: "note")
        r.setValue(Date(), forKey: "updatedAt")
    }

    /// 何マスかをまとめて書き換える（関係する日の記録を1回の読み込みで集め、同じ人・同じ日の重複も片付ける）
    static func upsertCells(_ items: [(CellKey, CellEntry?)], in ctx: NSManagedObjectContext) throws {
        guard !items.isEmpty else { return }
        if items.count == 1 { return try upsertCell(items[0].0, items[0].1, in: ctx) }
        let days = Array(Set(items.map { $0.0.day.description }))
        let team = try currentTeam(ctx)
        let req = request(ShiftModel.Entity.cell, NSPredicate(format: "day IN %@", days), team: team, ctx: ctx)
        var existing: [String: [NSManagedObject]] = [:]
        for r in try ctx.fetch(req) { existing["\(r.str("staffKey"))|\(r.str("day"))", default: []].append(r) }
        let now = Date()
        for (key, entry) in items {
            let rows = existing[key.description] ?? []
            guard let entry else {
                rows.forEach(ctx.delete)
                existing[key.description] = []
                continue
            }
            let r: NSManagedObject
            if let first = rows.first {
                r = first
                rows.dropFirst().forEach(ctx.delete)
            } else {
                r = insert(ShiftModel.Entity.cell, ctx, team: team, now: now)
                r.setValue(key.staffID, forKey: "staffKey")
                r.setValue(key.day.description, forKey: "day")
            }
            existing[key.description] = [r]
            r.setValue(entry.inTime, forKey: "inTime")
            r.setValue(entry.outTime, forKey: "outTime")
            r.setValue(entry.blockID ?? "", forKey: "blockKey")
            r.setValue(entry.isOff, forKey: "isOff")
            r.setValue(entry.storeID ?? "", forKey: "storeKey")
            r.setValue(entry.note ?? "", forKey: "note")
            r.setValue(now, forKey: "updatedAt")
        }
    }

    /// チーム全体の設定を保存
    static func saveSettings(_ book: ShiftBook, team: NSManagedObject) throws {
        team.setValue(try JSONEncoder().encode(TeamSettings(breakRules: book.breakRules, staffing: book.staffing,
                                                                    labor: book.labor, pay: book.pay, published: book.published,
                                                                    stores: book.stores, brandColor: book.brandColor,
                                                                    company: book.company)), forKey: "settings")
    }

    static func allTeams(_ ctx: NSManagedObjectContext) throws -> [NSManagedObject] {
        let req = NSFetchRequest<NSManagedObject>(entityName: ShiftModel.Entity.team)
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        let teams = try ctx.fetch(req)
        return teams.isEmpty ? [try currentTeam(ctx)] : teams
    }

    /// 自分のチーム（自分のデータの入れ物にあるもの。ほかの人から共有されたものは入れない）。古い順
    static func ownTeams(_ ctx: NSManagedObjectContext) throws -> [NSManagedObject] {
        let req = NSFetchRequest<NSManagedObject>(entityName: ShiftModel.Entity.team)
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return try ctx.fetch(req).filter { !ShiftDatabase.isShared($0.objectID.persistentStore) }
    }

    /// 設定を書くチーム：自分のシフト表なら自分のチームすべて（2台で同期を始めたときの重複にも書く）、共有されたものならそのチームだけ
    static func settingsTeams(_ ctx: NSManagedObjectContext) throws -> [NSManagedObject] {
        let team = try currentTeam(ctx)
        if ShiftDatabase.isShared(team.objectID.persistentStore) { return [team] }
        let own = try ownTeams(ctx)
        return own.isEmpty ? [team] : own
    }

    /// 2台で同期を始めると、それぞれが作った「チーム」が2つになることがある。
    /// いちばん古いチームに記録を寄せ、設定の無いほうを片付ける（記録を先に移すので、チームを消しても記録は消えない）。
    /// まとめるのは自分のチームどうしだけ（ほかの人から共有されたシフト表は混ぜない）
    static func mergeTeams(_ ctx: NSManagedObjectContext) throws {
        let teams = try ownTeams(ctx)
        guard teams.count > 1, let keep = teams.first else { return }
        for extra in teams.dropFirst() {
            if keep.value(forKey: "settings") == nil, let s = extra.value(forKey: "settings") { keep.setValue(s, forKey: "settings") }
            for rel in ["departments", "templates", "staff", "cells"] {
                for child in (extra.value(forKey: rel) as? Set<NSManagedObject>) ?? [] { child.setValue(keep, forKey: "team") }
            }
            ctx.delete(extra)
        }
    }

    /// 表示しているチーム（選んだチーム → 自分のチームのいちばん古いもの）。無ければ nil（作らない）
    static func existingCurrentTeam(_ ctx: NSManagedObjectContext) throws -> NSManagedObject? {
        let req = NSFetchRequest<NSManagedObject>(entityName: ShiftModel.Entity.team)
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        let teams = try ctx.fetch(req)
        if let id = activeTeamID, let t = teams.first(where: { $0.value(forKey: "id") as? UUID == id }) { return t }
        return teams.first { !ShiftDatabase.isShared($0.objectID.persistentStore) }
    }

    /// 表示しているチーム（無ければ自分のチームを作る）
    static func currentTeam(_ ctx: NSManagedObjectContext) throws -> NSManagedObject {
        if let t = try existingCurrentTeam(ctx) { return t }
        let t = NSEntityDescription.insertNewObject(forEntityName: ShiftModel.Entity.team, into: ctx)
        t.setValue(UUID(), forKey: "id")
        t.setValue("シフト表", forKey: "name")
        t.setValue(Date(), forKey: "createdAt")
        return t
    }

    // MARK: 部品

    /// そのチームの記録（自分のチームなら、チームにつながっていない古い記録も含める）
    static func fetch(_ name: String, _ ctx: NSManagedObjectContext, team: NSManagedObject) throws -> [NSManagedObject] {
        try ctx.fetch(request(name, team: team, ctx: ctx))
    }

    /// 表示しているチームの記録を探す条件。自分のチームなら自分のデータの入れ物だけ、共有されたものなら共有の入れ物だけを見る
    /// （共有の記録が届く途中でチームのつながりがまだ無いときに、自分のシフト表へ紛れ込まないように）
    static func request(_ entity: String, _ p: NSPredicate? = nil, team: NSManagedObject, ctx: NSManagedObjectContext) -> NSFetchRequest<NSManagedObject> {
        let req = NSFetchRequest<NSManagedObject>(entityName: entity)
        req.predicate = p.map { scoped($0, to: team) } ?? inTeam(team)
        let shared = ShiftDatabase.isShared(team.objectID.persistentStore)
        let stores = ctx.persistentStoreCoordinator?.persistentStores.filter { ShiftDatabase.isShared($0) == shared } ?? []
        if !stores.isEmpty { req.affectedStores = stores }
        return req
    }

    static func inTeam(_ team: NSManagedObject) -> NSPredicate {
        ShiftDatabase.isShared(team.objectID.persistentStore)
            ? NSPredicate(format: "team == %@", team)
            : NSPredicate(format: "team == %@ OR team == nil", team)
    }

    /// 条件に「表示しているチームの記録」を足す
    static func scoped(_ p: NSPredicate, to team: NSManagedObject) -> NSPredicate {
        NSCompoundPredicate(andPredicateWithSubpredicates: [p, inTeam(team)])
    }

    static func insert(_ name: String, _ ctx: NSManagedObjectContext, team: NSManagedObject, now: Date) -> NSManagedObject {
        let r = NSEntityDescription.insertNewObject(forEntityName: name, into: ctx)
        // 共有されたシフト表の記録は、共有の入れ物に入れる（チームと同じ入れ物でないと保存できない）
        if !team.objectID.isTemporaryID, let store = team.objectID.persistentStore { ctx.assign(r, to: store) }
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
    var pay: PayRules? = nil
    var published: [PublishedMonth]?
    var stores: [Store]? = nil
    var brandColor: UInt32? = nil
    var company: CompanyInfo? = nil
}

enum StoreError: LocalizedError {
    case storeInUse
    case lastStore

    var errorDescription: String? {
        switch self {
        case .storeInUse: "この店舗には部門があるため消せません。先に部門をほかの店舗へ移すか消してください。"
        case .lastStore: "店舗は1つ以上必要です。"
        }
    }
}
