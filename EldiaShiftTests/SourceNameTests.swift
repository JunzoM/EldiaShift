import CoreData
import Foundation
import Testing
@testable import EldiaShift

/// 共有されたシフト表の「共有元」：会社名、無ければ最初の店舗名
@Suite("共有元の名前")
@MainActor
struct SourceNameTests {
    private func team(_ settings: TeamSettings?) throws -> NSManagedObject {
        let c = NSPersistentContainer(name: "EldiaShift", managedObjectModel: ShiftModel.model)
        let d = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
        d.type = NSSQLiteStoreType
        c.persistentStoreDescriptions = [d]
        var failure: Error?
        c.loadPersistentStores { _, e in failure = e }
        if let failure { throw failure }
        let t = NSEntityDescription.insertNewObject(forEntityName: ShiftModel.Entity.team, into: c.viewContext)
        if let settings { t.setValue(try JSONEncoder().encode(settings), forKey: "settings") }
        return t
    }

    @Test("会社名があれば会社名")
    func company() throws {
        var s = TeamSettings(breakRules: .laborStandard)
        var info = CompanyInfo()
        info.name = "見本ホテルグループ"
        s.company = info
        s.stores = [Store(id: "main", name: "見本ホテル 本館", address: "", hours: "", colorIndex: 0, sortOrder: 0)]
        #expect(ShiftDatabase.sourceName(of: try team(s)) == "見本ホテルグループ")
    }

    @Test("会社名が空なら最初の店舗名")
    func store() throws {
        var s = TeamSettings(breakRules: .laborStandard)
        s.company = CompanyInfo()
        s.stores = [Store(id: "main", name: "見本ホテル 本館", address: "", hours: "", colorIndex: 0, sortOrder: 0)]
        #expect(ShiftDatabase.sourceName(of: try team(s)) == "見本ホテル 本館")
    }

    @Test("設定が無ければ無し（「ほかの人のシフト表」と出る）")
    func none() throws {
        #expect(ShiftDatabase.sourceName(of: try team(nil)) == nil)
    }
}
