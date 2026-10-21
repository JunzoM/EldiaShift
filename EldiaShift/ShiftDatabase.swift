import CoreData
import Observation

/// 端末内のデータベース（Core Data）。サーバーは使わない。
/// ・iCloud 同期オフ：この端末の中だけで完結
/// ・iCloud 同期オン：同じ Apple ID の iPad / iPhone と iCloud（CloudKit）経由で同期
/// 複数の管理者での共同編集（iCloud 共有）は次の段階で足す。そのため、すべての記録は「チーム」に属する形にしてある
/// （共有はチーム単位で行い、チームにつながる記録が一緒に共有されるため）。
@MainActor
@Observable
final class ShiftDatabase {
    /// iCloud（CloudKit）のコンテナ名。Xcode の Signing & Capabilities で同じ名前を登録すること
    nonisolated static let cloudContainerID = "iCloud.com.bestdelight.eldiashift"

    private(set) var container: NSPersistentCloudKitContainer
    private(set) var iCloudEnabled: Bool
    private(set) var loadError: String?
    /// iCloud から変更が届いた・設定を切り替えたなどで、表示を読み直してほしいときに増える
    private(set) var changeToken = 0

    @ObservationIgnored private let inMemory: Bool
    @ObservationIgnored private var remoteObserver: NSObjectProtocol?
    @ObservationIgnored private var pendingReload: Task<Void, Never>?

    var viewContext: NSManagedObjectContext { container.viewContext }

    /// inMemory はテスト・画面確認用（ファイルに保存しない・同期しない）
    init(inMemory: Bool = false) {
        self.inMemory = inMemory
        let enabled = !inMemory && SyncSettings.iCloudEnabled
        iCloudEnabled = enabled
        container = Self.makeContainer(iCloud: enabled, inMemory: inMemory)
        loadError = Self.load(container)
        observeRemoteChanges()
    }

    /// iCloud 同期のオン・オフ（保存場所はそのまま、開き直すだけ）
    func setICloud(_ enabled: Bool) {
        guard enabled != iCloudEnabled, !inMemory else { return }
        SyncSettings.iCloudEnabled = enabled
        if let store = container.persistentStoreCoordinator.persistentStores.first {
            try? container.persistentStoreCoordinator.remove(store)
        }
        container = Self.makeContainer(iCloud: enabled, inMemory: false)
        loadError = Self.load(container)
        iCloudEnabled = enabled
        observeRemoteChanges()
        changeToken += 1
    }

    func save() throws {
        if viewContext.hasChanges { try viewContext.save() }
    }

    private static func makeContainer(iCloud: Bool, inMemory: Bool) -> NSPersistentCloudKitContainer {
        let c = NSPersistentCloudKitContainer(name: "EldiaShift", managedObjectModel: ShiftModel.model)
        let desc = NSPersistentStoreDescription(url: inMemory ? URL(fileURLWithPath: "/dev/null") : storeURL)
        desc.type = NSSQLiteStoreType
        desc.shouldMigrateStoreAutomatically = true
        desc.shouldInferMappingModelAutomatically = true
        // あとから iCloud 同期をオンにしても、それまでの内容が送られるよう、変更の履歴は常に残す
        desc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        desc.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        desc.cloudKitContainerOptions = iCloud ? NSPersistentCloudKitContainerOptions(containerIdentifier: cloudContainerID) : nil
        c.persistentStoreDescriptions = [desc]
        return c
    }

    private static func load(_ c: NSPersistentCloudKitContainer) -> String? {
        var failure: String?
        c.loadPersistentStores { _, error in
            if let error { failure = "データを読み込めませんでした（\(error.localizedDescription)）" }
        }
        c.viewContext.automaticallyMergesChangesFromParent = true
        c.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        return failure
    }

    nonisolated private static var storeURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("EldiaShift.sqlite")
    }

    private func observeRemoteChanges() {
        if let remoteObserver { NotificationCenter.default.removeObserver(remoteObserver) }
        remoteObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleReload() }
        }
    }

    /// 続けて届いた変更は、少し待ってまとめて1回だけ読み直す
    private func scheduleReload() {
        pendingReload?.cancel()
        pendingReload = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            self?.changeToken += 1
        }
    }
}

enum SyncSettings {
    private static let key = "iCloudSyncEnabled"

    /// iCloud 同期を使うか（初期値：使わない）
    static var iCloudEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

// MARK: - データの形（Core Data のモデルをコードで定義）
// iCloud（CloudKit）で同期するため、すべての項目は省略可能か初期値ありにし、重複禁止の制約は付けない。
// 重複（2台で同時に同じ人・同じ日を入力したなど）は、読み込むときに新しい方を残して片付ける。

enum ShiftModel {
    enum Entity {
        static let team = "TeamRecord"
        static let department = "DepartmentRecord"
        static let template = "TemplateRecord"
        static let staff = "StaffRecord"
        static let cell = "CellRecord"
    }

    nonisolated(unsafe) static let model: NSManagedObjectModel = {
        let team = entity(Entity.team, [
            attr("id", .UUIDAttributeType),
            attr("name", .stringAttributeType),
            attr("createdAt", .dateAttributeType),
            // チーム全体の設定（休憩の決まりなど。JSON）
            attr("settings", .binaryDataAttributeType)
        ])
        let department = entity(Entity.department, [
            attr("key", .stringAttributeType),
            attr("name", .stringAttributeType),
            attr("colorIndex", .integer16AttributeType, default: 0),
            attr("sortOrder", .integer32AttributeType, default: 0),
            attr("updatedAt", .dateAttributeType)
        ])
        let template = entity(Entity.template, [
            attr("key", .stringAttributeType),
            attr("label", .stringAttributeType),
            attr("short", .stringAttributeType),
            attr("inMinutes", .integer32AttributeType, default: -1),
            attr("outMinutes", .integer32AttributeType, default: -1),
            attr("colorIndex", .integer16AttributeType, default: 0),
            attr("sortOrder", .integer32AttributeType, default: 0),
            // このひな形の休憩（分）。-1 は休憩の決まりに従う
            attr("breakMinutes", .integer32AttributeType, default: -1),
            attr("updatedAt", .dateAttributeType)
        ])
        let staff = entity(Entity.staff, [
            attr("key", .stringAttributeType),
            attr("number", .integer32AttributeType, default: 0),
            attr("name", .stringAttributeType),
            attr("departmentKey", .stringAttributeType),
            attr("active", .booleanAttributeType, default: true),
            attr("joinDate", .stringAttributeType),
            attr("leaveDate", .stringAttributeType),
            // 個人のひな形・週のくり返し・期間の予定（JSON）
            attr("detail", .binaryDataAttributeType),
            attr("updatedAt", .dateAttributeType)
        ])
        let cell = entity(Entity.cell, [
            attr("staffKey", .stringAttributeType),
            attr("day", .stringAttributeType),
            attr("inTime", .stringAttributeType),
            attr("outTime", .stringAttributeType),
            attr("blockKey", .stringAttributeType),
            attr("isOff", .booleanAttributeType, default: false),
            attr("updatedAt", .dateAttributeType),
            attr("updatedBy", .stringAttributeType)
        ])
        cell.indexes = [NSFetchIndexDescription(name: "byDay", elements: [
            NSFetchIndexElementDescription(property: cell.propertiesByName["day"]!, collationType: .binary)
        ])]

        // チーム ⇔ 各記録（共有の単位）
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
    }()

    private static func entity(_ name: String, _ props: [NSAttributeDescription]) -> NSEntityDescription {
        let e = NSEntityDescription()
        e.name = name
        e.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        e.properties = props
        return e
    }

    private static func attr(_ name: String, _ type: NSAttributeType, default value: Any? = nil) -> NSAttributeDescription {
        let a = NSAttributeDescription()
        a.name = name
        a.attributeType = type
        a.isOptional = true
        a.defaultValue = value
        return a
    }
}
