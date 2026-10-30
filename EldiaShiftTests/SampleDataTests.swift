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
        let today = DayKey(2026, 10, 30)
        let p = SampleData.make(offBlockID: "off1", storeOrder: 1, departmentOrder: 3, today: today)
        #expect(p.stores.count == 4 && p.departments.count == 8 && p.templates.count == 3 && p.staff.count == 100)
        let ids = p.stores.map(\.id) + p.departments.map(\.id) + p.templates.map(\.id) + p.staff.map(\.id)
        #expect(ids.allSatisfy(SampleData.isSample))
        #expect(Set(ids).count == ids.count)
        #expect(p.departments.allSatisfy { d in p.stores.contains { $0.id == d.storeID } })
        #expect(p.departments.map(\.sortOrder) == Array(3...10))
        // 1店舗25人
        for st in p.stores {
            let depts = Set(p.departments.filter { $0.storeID == st.id }.map(\.id))
            #expect(p.staff.filter { depts.contains($0.departmentID) }.count == SampleData.staffPerStore)
        }
        let allowed = Set(p.templates.map(\.id) + ["off1"])
        #expect(p.staff.allSatisfy { m in m.patterns.allSatisfy { $0.days.allSatisfy { $0.map(allowed.contains) ?? true } } })
        #expect(p.staff.allSatisfy { m in m.periodPatterns.allSatisfy { $0.days.values.allSatisfy(allowed.contains) } })
        #expect(p.staff.allSatisfy { m in p.departments.contains { $0.id == m.departmentID } })
    }

    @Test("シフトは去年の1月1日から来年の12月31日まで、毎日入っている")
    func threeYears() throws {
        let today = DayKey(2026, 10, 30)
        let p = SampleData.make(offBlockID: "off1", storeOrder: 1, departmentOrder: 0, today: today)
        let period = try #require(p.staff.first?.periodPatterns.first)
        #expect(period.startDate == "2025-01-01" && period.endDate == "2027-12-31")
        #expect(period.days.count == 365 + 365 + 365)
        // 週に2日は休み（毎週同じ形にはしない）
        let m = try #require(p.staff.first)
        let firstWeek = (0..<7).map { period.days[DayKey(2025, 1, 5).adding(days: $0).description] }
        let nextWeek = (0..<7).map { period.days[DayKey(2025, 1, 12).adding(days: $0).description] }
        #expect(firstWeek.filter { $0 == "off1" }.count == 2)
        #expect(firstWeek != nextWeek)
        #expect(m.wages.count == 1)
    }

    @Test("希望休の申請は1店舗30件。承認した日は希望休に入り、その日は休み")
    func requests() {
        let today = DayKey(2026, 10, 30)
        let p = SampleData.make(offBlockID: "off1", storeOrder: 1, departmentOrder: 0, today: today)
        for st in p.stores {
            let depts = Set(p.departments.filter { $0.storeID == st.id }.map(\.id))
            let reqs = p.staff.filter { depts.contains($0.departmentID) }.flatMap(\.leaveRequests)
            #expect(reqs.count == SampleData.requestsPerStore)
            #expect(reqs.allSatisfy { SampleData.isSample($0.id) })
            #expect(Set(reqs.map(\.status)) == Set(LeaveRequest.Status.allCases))
        }
        for m in p.staff {
            for r in m.leaveRequests where r.status == .approved {
                #expect(m.offRequests.contains(r.day))
                #expect(m.periodPatterns.first?.days[r.day] == "off1")
            }
        }
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
        #expect(store.book.allStores.filter { SampleData.isSample($0.id) }.count == 4)
        #expect(store.book.staff.filter { SampleData.isSample($0.id) }.count == 100)
        #expect(store.book.departments.count == realDepts.count + 8)
        #expect(store.book.company.name == SampleData.companyName)
        // 二度押しても増えない
        try store.addSampleData()
        #expect(store.book.staff.count == 101)
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
        #expect(store.book.company.name.isEmpty)
        // 端末内の保存にも残っていない
        let loaded = try ShiftRecords.load(store.db.viewContext)
        #expect(!loaded.staff.contains { SampleData.isSample($0.id) })
        #expect(!(loaded.stores).contains { SampleData.isSample($0.id) })
    }
}
