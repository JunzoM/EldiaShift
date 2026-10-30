import CloudKit
import CoreData
import Observation

/// 端末内のデータベース（Core Data）。サーバーは使わない。
/// ・iCloud 同期オフ：この端末の中だけで完結
/// ・iCloud 同期オン：同じ Apple ID の iPad / iPhone と iCloud（CloudKit）経由で同期
/// ・iCloud 共有：チーム（シフト表まるごと）をほかの Apple ID の人と共同編集する。チームにつながる記録が一緒に共有される。
///   給与（PayRecord）はチームにつながないので共有されない（自分の端末どうしでだけ同期する）。
/// 共有されたシフト表は、別のファイル（共有の入れ物）に入る。どのチームを表示するかは端末ごとに覚える。
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
    /// 表示しているチームが「見るだけ」で共有されている（保存しない）
    private(set) var readOnly = false
    /// 表示しているチームが、ほかの人から共有されたもの
    private(set) var viewingSharedTeam = false

    /// 共有の招待を受け取るときに使う（シーンのデリゲートから呼ぶ）
    nonisolated(unsafe) static weak var current: ShiftDatabase?
    /// 招待を受け取った直後：共有されたシフト表が届いたら、それに切り替える
    @ObservationIgnored private var switchToSharedOnArrival = false

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
        ShiftRecords.activeTeamID = inMemory ? nil : TeamChoice.saved
        observeRemoteChanges()
        refreshAccess()
        if !inMemory { Self.current = self }
    }

    /// iCloud 同期のオン・オフ（保存場所はそのまま、開き直すだけ）
    func setICloud(_ enabled: Bool) {
        guard enabled != iCloudEnabled, !inMemory else { return }
        SyncSettings.iCloudEnabled = enabled
        for store in container.persistentStoreCoordinator.persistentStores {
            try? container.persistentStoreCoordinator.remove(store)
        }
        container = Self.makeContainer(iCloud: enabled, inMemory: false)
        loadError = Self.load(container)
        iCloudEnabled = enabled
        observeRemoteChanges()
        refreshAccess()
        changeToken += 1
    }

    /// 保存する。「見るだけ」で共有されたシフト表を表示しているときは、変更を取り消して知らせる
    func save() throws {
        guard viewContext.hasChanges else { return }
        if readOnly {
            viewContext.rollback()
            throw ShareError.readOnly
        }
        try viewContext.save()
    }

    // MARK: 共有

    /// 共有されたシフト表の入れ物のファイル名（自分のデータとは別のファイル）
    nonisolated static let sharedFileName = "EldiaShift-shared.sqlite"

    /// 共有されたシフト表の入れ物か
    nonisolated static func isShared(_ store: NSPersistentStore?) -> Bool {
        store?.url?.lastPathComponent == sharedFileName
    }

    var privateStore: NSPersistentStore? { container.persistentStoreCoordinator.persistentStores.first { !Self.isShared($0) } }
    var sharedStore: NSPersistentStore? { container.persistentStoreCoordinator.persistentStores.first { Self.isShared($0) } }

    /// チーム（シフト表）の一覧に出すもの
    struct TeamInfo: Identifiable, Equatable {
        let id: UUID
        /// ほかの人から共有された
        let sharedWithMe: Bool
        /// 共有した人（共有されたシフト表のとき）
        let ownerName: String?
        /// 自分のシフト表を共有している人数（自分を除く）
        let participants: Int
        let canEdit: Bool
        let isActive: Bool

        var title: String {
            sharedWithMe ? "\(ownerName.map { "\($0)さん" } ?? "ほかの人")のシフト表（共有）" : "自分のシフト表"
        }
    }

    /// 自分のシフト表と、共有されたシフト表
    func teams() -> [TeamInfo] {
        let req = NSFetchRequest<NSManagedObject>(entityName: ShiftModel.Entity.team)
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        let rows = (try? viewContext.fetch(req)) ?? []
        let active = (try? ShiftRecords.existingCurrentTeam(viewContext))?.objectID
        let shares = (try? container.fetchShares(matching: rows.map(\.objectID))) ?? [:]
        return rows.compactMap { r -> TeamInfo? in
            guard let id = r.value(forKey: "id") as? UUID else { return nil }
            let theirs = Self.isShared(r.objectID.persistentStore)
            let share = shares[r.objectID]
            return TeamInfo(id: id, sharedWithMe: theirs, ownerName: share.flatMap { Self.name(of: $0.owner) },
                            participants: theirs ? 0 : max(0, (share?.participants.count ?? 1) - 1),
                            canEdit: !theirs || container.canUpdateRecord(forManagedObjectWith: r.objectID),
                            isActive: r.objectID == active)
        }
    }

    /// 表示するチームを変える（端末ごとに覚える）
    func setActiveTeam(_ id: UUID?) {
        TeamChoice.saved = id
        ShiftRecords.activeTeamID = id
        refreshAccess()
        changeToken += 1
    }

    /// 表示しているチームの共有（まだ共有していなければ nil）
    func shareForActiveTeam() -> CKShare? {
        guard let team = try? ShiftRecords.existingCurrentTeam(viewContext), !team.objectID.isTemporaryID else { return nil }
        return (try? container.fetchShares(matching: [team.objectID]))?[team.objectID]
    }

    /// 自分のシフト表を共有する（共有の入れ物を作る）。すでに共有していれば、その共有
    func makeShare() async throws -> (CKShare, CKContainer) {
        guard iCloudEnabled else { throw ShareError.iCloudOff }
        let team = try ShiftRecords.currentTeam(viewContext)
        guard !Self.isShared(team.objectID.persistentStore) else { throw ShareError.notOwner }
        if viewContext.hasChanges { try viewContext.save() }
        let ck = CKContainer(identifier: Self.cloudContainerID)
        if let existing = try container.fetchShares(matching: [team.objectID])[team.objectID] { return (existing, ck) }
        // 共有を作る前に、スタッフの記録に残っている給与（前の版で書いたもの）を消しておく
        try ShiftRecords.stripWagesFromStaff(in: viewContext)
        if viewContext.hasChanges { try viewContext.save() }
        let (_, share, shareContainer) = try await container.share([team], to: nil)
        share[CKShare.SystemFieldKey.title] = "シフト表" as CKRecordValue
        return (share, shareContainer)
    }

    /// 共有の画面で参加者・権限を変えたあと
    func persistUpdatedShare(_ share: CKShare) async {
        guard let store = privateStore else { return }
        _ = try? await container.persistUpdatedShare(share, in: store)
        refreshAccess()
        changeToken += 1
    }

    /// 招待を受け取る（iCloud 同期がオフならオンにしてから）。届いたら、そのシフト表に切り替える
    func accept(_ metadata: CKShare.Metadata) async throws {
        if !iCloudEnabled { setICloud(true) }
        guard let store = sharedStore else { throw ShareError.iCloudOff }
        switchToSharedOnArrival = true
        _ = try await container.acceptShareInvitations(from: [metadata], into: store)
        switchIfSharedArrived()
    }

    /// 共有されたシフト表が届いていれば、それを表示する（招待を受け取った直後だけ）
    private func switchIfSharedArrived() {
        guard switchToSharedOnArrival else { return }
        let req = NSFetchRequest<NSManagedObject>(entityName: ShiftModel.Entity.team)
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        guard let team = ((try? viewContext.fetch(req)) ?? []).first(where: { Self.isShared($0.objectID.persistentStore) }),
              let id = team.value(forKey: "id") as? UUID else { return }
        switchToSharedOnArrival = false
        setActiveTeam(id)
    }

    /// 表示しているチームが共有されたものか・編集できるかを調べ直す
    private func refreshAccess() {
        guard let team = try? ShiftRecords.existingCurrentTeam(viewContext), !team.objectID.isTemporaryID else {
            readOnly = false
            viewingSharedTeam = false
            return
        }
        let theirs = Self.isShared(team.objectID.persistentStore)
        viewingSharedTeam = theirs
        readOnly = theirs && !container.canUpdateRecord(forManagedObjectWith: team.objectID)
    }

    nonisolated static func name(of p: CKShare.Participant) -> String? {
        guard let c = p.userIdentity.nameComponents else { return nil }
        let s = PersonNameComponentsFormatter.localizedString(from: c, style: .default)
        return s.isEmpty ? nil : s
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
        var descriptions = [desc]
        // 共有されたシフト表の入れ物（iCloud 同期がオンのときだけ。自分のデータとは別のファイル）
        if iCloud && !inMemory {
            let shared = NSPersistentStoreDescription(url: storeURL.deletingLastPathComponent().appendingPathComponent(sharedFileName))
            shared.type = NSSQLiteStoreType
            shared.shouldMigrateStoreAutomatically = true
            shared.shouldInferMappingModelAutomatically = true
            shared.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            shared.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            let options = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudContainerID)
            options.databaseScope = .shared
            shared.cloudKitContainerOptions = options
            descriptions.append(shared)
        }
        c.persistentStoreDescriptions = descriptions
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
            Task { @MainActor in
                self?.switchIfSharedArrived()
                self?.refreshAccess()
                self?.scheduleReload()
            }
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

/// 表示するチーム（端末ごと。nil は自分のシフト表）
enum TeamChoice {
    private static let key = "activeTeamID"

    static var saved: UUID? {
        get { UserDefaults.standard.string(forKey: key).flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: key) }
    }
}

enum ShareError: LocalizedError {
    case readOnly, iCloudOff, notOwner

    var errorDescription: String? {
        switch self {
        case .readOnly: "このシフト表は「見るだけ」で共有されています。変更できません（共有した人に「編集できる」にしてもらってください）。"
        case .iCloudOff: "共有するには、設定の「iCloud で同期する」をオンにしてください。"
        case .notOwner: "共有されたシフト表は、さらにほかの人へ共有できません。参加者を増やすときは、共有した人に頼んでください。"
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
        /// 給与（時給・月給）。チームにつながないので共有されない（自分の端末どうしでだけ同期）
        static let pay = "PayRecord"
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
            // 属する店舗（空は最初の店舗）
            attr("storeKey", .stringAttributeType),
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
            // 掛け持ちでほかの店舗に入る日の店舗（空はその人の店舗）
            attr("storeKey", .stringAttributeType),
            // メモ（引き継ぎ・注意点）。1.2 で足した項目（追加のみ。前の版の記録は空）
            attr("note", .stringAttributeType),
            attr("updatedAt", .dateAttributeType),
            attr("updatedBy", .stringAttributeType)
        ])
        // 1.2 で足した入れ物（追加のみ）。key はスタッフの ID、wages は [WageEntry] の JSON
        let pay = entity(Entity.pay, [
            attr("key", .stringAttributeType),
            attr("wages", .binaryDataAttributeType),
            attr("updatedAt", .dateAttributeType)
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
        m.entities = [team, department, template, staff, cell, pay]
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
