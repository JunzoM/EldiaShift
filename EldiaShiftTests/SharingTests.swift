import CoreData
import Foundation
import Testing
@testable import EldiaShift

/// iCloud 共有の土台（給与を共有しない・チームを混ぜない）。共有そのものは実機で確かめる（docs/sharing-test.md）
@Suite("iCloud 共有：給与は共有しない・チームを区別する", .serialized)
@MainActor
struct SharingTests {
    private func member(_ id: String, wage: Int?) -> StaffMember {
        var m = StaffMember(id: id, number: 1, name: "スタッフ\(id)", departmentID: "d", active: true, joinDate: "", leaveDate: "",
                            timeBlocks: [], patterns: [], activePatternID: nil, periodPatterns: [])
        if let wage { m.wages = [WageEntry(id: "w\(id)", from: "2026-04-01", kind: .hourly, amount: wage)] }
        return m
    }

    private func detail(of id: String, _ ctx: NSManagedObjectContext) throws -> ShiftRecords.StaffDetail? {
        let req = NSFetchRequest<NSManagedObject>(entityName: ShiftModel.Entity.staff)
        req.predicate = NSPredicate(format: "key == %@", id)
        guard let data = try ctx.fetch(req).first?.value(forKey: "detail") as? Data else { return nil }
        return try JSONDecoder().decode(ShiftRecords.StaffDetail.self, from: data)
    }

    private func pays(_ ctx: NSManagedObjectContext) throws -> [NSManagedObject] {
        try ctx.fetch(NSFetchRequest<NSManagedObject>(entityName: ShiftModel.Entity.pay))
    }

    @Test("給与はスタッフの記録（共有されるもの）に書かず、給与だけの入れ物に入れる")
    func wagesStayPrivate() throws {
        let store = ShiftStore(db: ShiftDatabase(inMemory: true))
        try store.save(member("1", wage: 1200))
        let ctx = store.db.viewContext
        #expect(try detail(of: "1", ctx)?.wages == nil)
        let pay = try #require(try pays(ctx).first)
        #expect(pay.value(forKey: "key") as? String == "1")
        // 給与だけの入れ物はチームにつながない（共有されない）
        #expect(ShiftModel.model.entitiesByName[ShiftModel.Entity.pay]?.relationshipsByName.isEmpty == true)
        #expect(try ShiftRecords.load(ctx).staff.first?.wages.first?.amount == 1200)
        // バックアップには入る
        let (again, _) = try BackupFile.read(try store.exportData())
        #expect(again.staff.first?.wages.first?.amount == 1200)
    }

    @Test("前の版でスタッフの記録に入れた給与は、読み込むと給与だけの入れ物へ移る")
    func migrateOldWages() throws {
        let db = ShiftDatabase(inMemory: true)
        let ctx = db.viewContext
        let team = try ShiftRecords.currentTeam(ctx)
        let r = NSEntityDescription.insertNewObject(forEntityName: ShiftModel.Entity.staff, into: ctx)
        r.setValue(team, forKey: "team")
        r.setValue("1", forKey: "key")
        r.setValue("前の版", forKey: "name")
        r.setValue(Date(), forKey: "updatedAt")
        let old = #"{"timeBlocks":[],"patterns":[],"periodPatterns":[],"wages":[{"id":"w","from":"2026-01-01","kind":"hourly","amount":1100}]}"#
        r.setValue(Data(old.utf8), forKey: "detail")
        try db.save()

        let book = try ShiftRecords.load(ctx)
        #expect(book.staff.first?.wages.first?.amount == 1100)
        #expect(try detail(of: "1", ctx)?.wages == nil)
        #expect(try pays(ctx).count == 1)
        // 読み直しても同じ
        #expect(try ShiftRecords.load(ctx).staff.first?.wages.first?.amount == 1100)
    }

    @Test("共有を作る前に、スタッフの記録に残った給与を消す")
    func stripBeforeSharing() throws {
        let db = ShiftDatabase(inMemory: true)
        let ctx = db.viewContext
        let team = try ShiftRecords.currentTeam(ctx)
        let r = NSEntityDescription.insertNewObject(forEntityName: ShiftModel.Entity.staff, into: ctx)
        r.setValue(team, forKey: "team")
        r.setValue("1", forKey: "key")
        r.setValue(Date(), forKey: "updatedAt")
        r.setValue(Data(#"{"timeBlocks":[],"patterns":[],"periodPatterns":[],"wages":[{"id":"w","from":"2026-01-01","kind":"monthly","amount":250000}]}"#.utf8),
                   forKey: "detail")
        // 共有を作るときと同じく、保存してから消す
        try db.save()
        try ShiftRecords.stripWagesFromStaff(in: ctx)
        try db.save()
        #expect(try detail(of: "1", ctx)?.wages == nil)
        #expect(try ShiftRecords.load(ctx).staff.first?.wages.first?.amount == 250_000)
    }

    /// 自分のデータの入れ物と、共有の入れ物の2つを持つデータベース（ファイルは一時フォルダ）
    private func twoStores() throws -> NSPersistentContainer {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sharing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let c = NSPersistentContainer(name: "SharingTest", managedObjectModel: ShiftModel.model)
        c.persistentStoreDescriptions = [dir.appendingPathComponent("own.sqlite"), dir.appendingPathComponent(ShiftDatabase.sharedFileName)].map {
            let d = NSPersistentStoreDescription(url: $0)
            d.type = NSSQLiteStoreType
            return d
        }
        var failure: Error?
        c.loadPersistentStores { _, e in if let e { failure = e } }
        if let failure { throw failure }
        return c
    }

    @Test("共有されたシフト表は自分のシフト表と混ぜず、選んだときだけ表示し、書く記録は共有の入れ物に入る")
    func teamsStaySeparate() throws {
        defer { ShiftRecords.activeTeamID = nil }
        ShiftRecords.activeTeamID = nil
        let c = try twoStores()
        let ctx = c.viewContext
        let sharedStore = try #require(c.persistentStoreCoordinator.persistentStores.first { ShiftDatabase.isShared($0) })
        #expect(c.persistentStoreCoordinator.persistentStores.filter { ShiftDatabase.isShared($0) }.count == 1)

        // 自分のチーム（あとから作った）
        let own = try ShiftRecords.currentTeam(ctx)
        own.setValue(Date(), forKey: "createdAt")
        try ShiftRecords.upsert(Department(id: "mine", name: "自分の部門", colorIndex: 0, sortOrder: 0), in: ctx)
        // ほかの人から共有されたチーム（自分のより古い）
        let theirs = NSEntityDescription.insertNewObject(forEntityName: ShiftModel.Entity.team, into: ctx)
        ctx.assign(theirs, to: sharedStore)
        let theirID = UUID()
        theirs.setValue(theirID, forKey: "id")
        theirs.setValue(Date(timeIntervalSince1970: 0), forKey: "createdAt")
        theirs.setValue(try JSONEncoder().encode(TeamSettings(breakRules: .laborStandard)), forKey: "settings")
        func insertShared(_ entity: String, team: NSManagedObject?, _ values: [String: Any]) {
            let r = NSEntityDescription.insertNewObject(forEntityName: entity, into: ctx)
            ctx.assign(r, to: sharedStore)
            r.setValue(team, forKey: "team")
            r.setValue(Date(), forKey: "updatedAt")
            for (k, v) in values { r.setValue(v, forKey: k) }
        }
        insertShared(ShiftModel.Entity.department, team: theirs, ["key": "their", "name": "共有の部門"])
        // 共有した人が前の版で給与を入れていても、受け取った側には出さない
        insertShared(ShiftModel.Entity.staff, team: theirs, ["key": "t1", "name": "共有の人",
            "detail": Data(#"{"timeBlocks":[],"patterns":[],"periodPatterns":[],"wages":[{"id":"w","from":"2026-01-01","kind":"hourly","amount":1500}]}"#.utf8)])
        // 届く途中でチームのつながりがまだ無い共有の記録は、自分のシフト表に紛れ込まない
        insertShared(ShiftModel.Entity.department, team: nil, ["key": "orphan", "name": "届く途中"])
        try ctx.save()

        // 何も選んでいなければ自分のシフト表（共有されたチームは古くてもまとめない）
        let mine = try ShiftRecords.load(ctx)
        #expect(mine.departments.map(\.id) == ["mine"])
        #expect(try ctx.fetch(NSFetchRequest<NSManagedObject>(entityName: ShiftModel.Entity.team)).count == 2)
        #expect(try ShiftRecords.ownTeams(ctx).count == 1)

        // 共有されたシフト表を選ぶ
        ShiftRecords.activeTeamID = theirID
        let shared = try ShiftRecords.load(ctx)
        #expect(shared.departments.map(\.id) == ["their"])
        #expect(shared.breakRules == .laborStandard)
        #expect(shared.staff.first?.wages.isEmpty == true)

        // 書く記録は共有の入れ物へ。給与は自分の入れ物へ
        try ShiftRecords.upsert(Department(id: "added", name: "足した部門", colorIndex: 0, sortOrder: 1), in: ctx)
        var t1 = try #require(shared.staff.first)
        t1.wages = [WageEntry(id: "mine", from: "2026-04-01", kind: .hourly, amount: 1300)]
        try ShiftRecords.upsert(t1, in: ctx)
        try ctx.save()
        let req = NSFetchRequest<NSManagedObject>(entityName: ShiftModel.Entity.department)
        req.predicate = NSPredicate(format: "key == %@", "added")
        #expect(ShiftDatabase.isShared(try #require(try ctx.fetch(req).first).objectID.persistentStore))
        #expect(try pays(ctx).allSatisfy { !ShiftDatabase.isShared($0.objectID.persistentStore) })
        #expect(try ShiftRecords.load(ctx).staff.first?.wages.first?.amount == 1300)

        // 設定は共有されたチームにだけ書く
        #expect(try ShiftRecords.settingsTeams(ctx).map(\.objectID) == [theirs.objectID])

        // 自分のシフト表に戻すと、共有の部門は出ない
        ShiftRecords.activeTeamID = nil
        #expect(try ShiftRecords.load(ctx).departments.map(\.id) == ["mine"])
    }
}
