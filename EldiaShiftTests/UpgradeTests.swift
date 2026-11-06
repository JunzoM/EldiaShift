import CoreData
import Foundation
import Testing
@testable import EldiaShift

/// App Store の 1.0 で保存したデータベースを、1.1 で開けること（上書きで更新したとき）。
/// 1.0 の端末が無くても確かめられるよう、1.0 のデータベースの形（cdaa578 の ShiftModel）をここに写して作る
@Suite("1.0 からの更新：データが残る", .serialized)
@MainActor
struct UpgradeTests {
    /// 1.0 のデータベースの形（cdaa578 の ShiftModel.model と同じ。1.1 で足したのは CellRecord.note と PayRecord）
    private static func model10() -> NSManagedObjectModel {
        func entity(_ name: String, _ props: [NSAttributeDescription]) -> NSEntityDescription {
            let e = NSEntityDescription()
            e.name = name
            e.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
            e.properties = props
            return e
        }
        func attr(_ name: String, _ type: NSAttributeType, default value: Any? = nil) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = type
            a.isOptional = true
            a.defaultValue = value
            return a
        }
        let team = entity("TeamRecord", [
            attr("id", .UUIDAttributeType), attr("name", .stringAttributeType),
            attr("createdAt", .dateAttributeType), attr("settings", .binaryDataAttributeType)
        ])
        let department = entity("DepartmentRecord", [
            attr("key", .stringAttributeType), attr("name", .stringAttributeType),
            attr("colorIndex", .integer16AttributeType, default: 0), attr("sortOrder", .integer32AttributeType, default: 0),
            attr("storeKey", .stringAttributeType), attr("updatedAt", .dateAttributeType)
        ])
        let template = entity("TemplateRecord", [
            attr("key", .stringAttributeType), attr("label", .stringAttributeType), attr("short", .stringAttributeType),
            attr("inMinutes", .integer32AttributeType, default: -1), attr("outMinutes", .integer32AttributeType, default: -1),
            attr("colorIndex", .integer16AttributeType, default: 0), attr("sortOrder", .integer32AttributeType, default: 0),
            attr("breakMinutes", .integer32AttributeType, default: -1), attr("updatedAt", .dateAttributeType)
        ])
        let staff = entity("StaffRecord", [
            attr("key", .stringAttributeType), attr("number", .integer32AttributeType, default: 0),
            attr("name", .stringAttributeType), attr("departmentKey", .stringAttributeType),
            attr("active", .booleanAttributeType, default: true), attr("joinDate", .stringAttributeType),
            attr("leaveDate", .stringAttributeType), attr("detail", .binaryDataAttributeType), attr("updatedAt", .dateAttributeType)
        ])
        let cell = entity("CellRecord", [
            attr("staffKey", .stringAttributeType), attr("day", .stringAttributeType),
            attr("inTime", .stringAttributeType), attr("outTime", .stringAttributeType),
            attr("blockKey", .stringAttributeType), attr("isOff", .booleanAttributeType, default: false),
            attr("storeKey", .stringAttributeType), attr("updatedAt", .dateAttributeType), attr("updatedBy", .stringAttributeType)
        ])
        cell.indexes = [NSFetchIndexDescription(name: "byDay", elements: [
            NSFetchIndexElementDescription(property: cell.propertiesByName["day"]!, collationType: .binary)
        ])]
        for (child, name) in [(department, "departments"), (template, "templates"), (staff, "staff"), (cell, "cells")] {
            let toTeam = NSRelationshipDescription()
            toTeam.name = "team"
            toTeam.destinationEntity = team
            toTeam.minCount = 0
            toTeam.maxCount = 1
            toTeam.isOptional = true
            toTeam.deleteRule = .nullifyDeleteRule
            let toChildren = NSRelationshipDescription()
            toChildren.name = name
            toChildren.destinationEntity = child
            toChildren.minCount = 0
            toChildren.maxCount = 0
            toChildren.isOptional = true
            toChildren.deleteRule = .cascadeDeleteRule
            toTeam.inverseRelationship = toChildren
            toChildren.inverseRelationship = toTeam
            child.properties.append(toTeam)
            team.properties.append(toChildren)
        }
        let m = NSManagedObjectModel()
        m.entities = [team, department, template, staff, cell]
        return m
    }

    /// アプリと同じ設定（自動で移す・変更の履歴を残す）でデータベースを開く
    private static func open(_ url: URL, model: NSManagedObjectModel) throws -> NSPersistentContainer {
        let c = NSPersistentContainer(name: "EldiaShift", managedObjectModel: model)
        let d = NSPersistentStoreDescription(url: url)
        d.type = NSSQLiteStoreType
        d.shouldMigrateStoreAutomatically = true
        d.shouldInferMappingModelAutomatically = true
        d.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        d.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        c.persistentStoreDescriptions = [d]
        var failure: Error?
        c.loadPersistentStores { _, e in if let e { failure = e } }
        if let failure { throw failure }
        return c
    }

    @Test("1.0 で保存した店舗・部門・ひな形・スタッフ・シフトが、1.1 で開いてもそのまま読め、給与とメモも書ける")
    func upgradeFrom10() throws {
        defer { ShiftRecords.activeTeamID = nil }
        ShiftRecords.activeTeamID = nil
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("upgrade-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("EldiaShift.sqlite")

        // 1.0 で保存する
        do {
            let old = try Self.open(url, model: Self.model10())
            let ctx = old.viewContext
            let now = Date()
            func insert(_ name: String, _ values: [String: Any]) -> NSManagedObject {
                let r = NSEntityDescription.insertNewObject(forEntityName: name, into: ctx)
                for (k, v) in values { r.setValue(v, forKey: k) }
                return r
            }
            let team = insert("TeamRecord", ["id": UUID(), "name": "シフト表", "createdAt": now,
                                             "settings": try JSONEncoder().encode(TeamSettings(breakRules: .laborStandard))])
            insert("DepartmentRecord", ["key": "front", "name": "フロント", "colorIndex": Int16(1), "sortOrder": Int32(0),
                                        "storeKey": "", "updatedAt": now]).setValue(team, forKey: "team")
            insert("TemplateRecord", ["key": "early", "label": "早番", "short": "早", "inMinutes": Int32(480),
                                      "outMinutes": Int32(1020), "colorIndex": Int16(2), "sortOrder": Int32(0),
                                      "breakMinutes": Int32(-1), "updatedAt": now]).setValue(team, forKey: "team")
            insert("StaffRecord", ["key": "s1", "number": Int32(1), "name": "佐藤花子", "departmentKey": "front",
                                   "active": true, "joinDate": "2026-04-01", "leaveDate": "",
                                   "detail": Data(#"{"timeBlocks":[],"patterns":[],"periodPatterns":[]}"#.utf8),
                                   "updatedAt": now]).setValue(team, forKey: "team")
            insert("CellRecord", ["staffKey": "s1", "day": "2026-11-10", "inTime": "", "outTime": "",
                                  "blockKey": "early", "isOff": false, "storeKey": "", "updatedAt": now,
                                  "updatedBy": ""]).setValue(team, forKey: "team")
            try ctx.save()
            for s in old.persistentStoreCoordinator.persistentStores { try old.persistentStoreCoordinator.remove(s) }
        }

        // 1.1 で開く（自動で新しい形へ移る）
        let new = try Self.open(url, model: ShiftModel.model)
        let ctx = new.viewContext
        let book = try ShiftRecords.load(ctx)
        #expect(book.departments.map(\.id) == ["front"])
        #expect(book.departments.first?.name == "フロント")
        #expect(book.templates.map(\.id) == ["early"])
        #expect(book.templates.first?.inMinutes == 480)
        #expect(book.staff.map(\.name) == ["佐藤花子"])
        #expect(book.staff.first?.joinDate == "2026-04-01")
        #expect(book.breakRules == .laborStandard)
        let cell = try #require(book.cells.first)
        #expect(cell.key.staffID == "s1")
        #expect(cell.key.day.description == "2026-11-10")
        #expect(cell.value.blockID == "early")
        #expect(cell.value.note == nil)

        // 1.1 で足した給与・メモも書ける
        var s1 = try #require(book.staff.first)
        s1.wages = [WageEntry(id: "w", from: "2026-04-01", kind: .hourly, amount: 1200)]
        try ShiftRecords.upsert(s1, in: ctx)
        let req = NSFetchRequest<NSManagedObject>(entityName: ShiftModel.Entity.cell)
        try #require(try ctx.fetch(req).first).setValue("引き継ぎ", forKey: "note")
        try ctx.save()
        let again = try ShiftRecords.load(ctx)
        #expect(again.staff.first?.wages.first?.amount == 1200)
        #expect(again.cells.first?.value.note == "引き継ぎ")
    }
}
