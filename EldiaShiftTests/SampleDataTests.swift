import Foundation
import Testing
@testable import EldiaShift

@Suite("店舗：客室数・フロア数、見本のデータ")
@MainActor
struct SampleDataTests {
    @Test("客室数・フロア数は前の版の記録でも読め、バックアップにも残る")
    func facility() throws {
        let old = #"{"id":"a","name":"本館"}"#
        let st = try JSONDecoder().decode(Store.self, from: Data(old.utf8))
        #expect(st.roomCount == nil && st.floorCount == nil && st.facilitySummary.isEmpty)

        var b = ShiftBook()
        var hotel = Store(id: "a", name: "本館")
        hotel.roomCount = 120
        hotel.floorCount = 8
        b.stores = [hotel, Store(id: "b", name: "別館", sortOrder: 1)]
        #expect(hotel.facilitySummary == "客室 120・8階")
        let (again, _) = try BackupFile.read(try BackupFile.write(b))
        #expect(again.stores.first { $0.id == "a" }?.roomCount == 120)
        #expect(again.stores.first { $0.id == "a" }?.floorCount == 8)
        #expect(again.stores.first { $0.id == "b" }?.roomCount == nil)
    }

    @Test("見本のデータは、すべて sample- の ID で、見本の店舗の部門・見本のひな形を使う")
    func parts() {
        let p = SampleData.make(offBlockID: "off1", storeOrder: 1, departmentOrder: 3)
        #expect(p.stores.count == 2 && p.departments.count == 4 && p.templates.count == 3 && p.staff.count == 24)
        let ids = p.stores.map(\.id) + p.departments.map(\.id) + p.templates.map(\.id) + p.staff.map(\.id)
        #expect(ids.allSatisfy(SampleData.isSample))
        #expect(Set(ids).count == ids.count)
        #expect(p.departments.allSatisfy { d in p.stores.contains { $0.id == d.storeID } })
        #expect(p.departments.map(\.sortOrder) == [3, 4, 5, 6])
        let allowed = Set(p.templates.map(\.id) + ["off1"])
        #expect(p.staff.allSatisfy { m in m.patterns.allSatisfy { $0.days.allSatisfy { $0.map(allowed.contains) ?? true } } })
        #expect(p.staff.allSatisfy { m in p.departments.contains { $0.id == m.departmentID } })
    }

    @Test("見本を足しても今のデータはそのまま。消すと見本だけが消え、掛け持ち先からも外れる")
    func addAndRemove() throws {
        let store = ShiftStore(db: ShiftDatabase(inMemory: true))
        try store.startNew()
        let realDepts = store.book.departments
        var real = store.newStaff(in: realDepts[0].id)
        real.name = "本物 一郎"
        try store.save(real)
        #expect(!store.hasSampleData)

        try store.addSampleData()
        #expect(store.hasSampleData)
        #expect(store.book.allStores.filter { SampleData.isSample($0.id) }.count == 2)
        #expect(store.book.staff.filter { SampleData.isSample($0.id) }.count == 24)
        #expect(store.book.departments.count == realDepts.count + 4)
        // 二度押しても増えない
        try store.addSampleData()
        #expect(store.book.staff.count == 25)
        // 見本の人は勤務が入っている
        let sample = try #require(store.book.staff.first { SampleData.isSample($0.id) })
        let week = (0..<7).map { DayKey.today.adding(days: $0) }
        #expect(week.contains { Schedule.resolve(sample, on: $0, in: store.book)?.isOff == false })

        // 本物の人が見本の店舗に掛け持ちしていても、消すと外れる
        real = try #require(store.book.staff.first { $0.id == real.id })
        real.extraStoreIDs = [SampleData.prefix + "store-b"]
        try store.save(real)
        store.currentStoreID = SampleData.prefix + "store-a"

        try store.removeSampleData()
        #expect(!store.hasSampleData)
        #expect(store.book.staff.map(\.id) == [real.id])
        #expect(store.book.staff.first?.extraStoreIDs.isEmpty == true)
        #expect(store.book.departments.map(\.id) == realDepts.map(\.id))
        #expect(!store.book.templates.contains { SampleData.isSample($0.id) })
        #expect(!store.book.allStores.contains { SampleData.isSample($0.id) })
        #expect(!SampleData.isSample(store.currentStoreID))
        // 端末内の保存にも残っていない
        let loaded = try ShiftRecords.load(store.db.viewContext)
        #expect(!loaded.staff.contains { SampleData.isSample($0.id) })
        #expect(!(loaded.stores).contains { SampleData.isSample($0.id) })
    }
}
