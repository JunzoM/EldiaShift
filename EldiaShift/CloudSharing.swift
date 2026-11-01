import CloudKit
import Observation
import SwiftUI
import UIKit

// MARK: - iCloud 共有（シフト表をほかの管理者と共同編集する）
// 共有は Apple の共有の画面（UICloudSharingController）で招待を送る。招待のリンクを押すと、
// シーンのデリゲートに届くので、データベースに受け取らせる。給与は共有されない（ShiftDatabase を参照）。

/// 招待を受け取った結果を画面に出す
@MainActor
@Observable
final class ShareInbox {
    static let shared = ShareInbox()
    var message: String?

    func accept(_ metadata: CKShare.Metadata) {
        // 自分（同じ Apple アカウント）で作った共有の招待は受け取れない。同じ Apple アカウントの端末どうしは iCloud 同期で足りる
        if metadata.participantRole == .owner {
            message = "この招待は、この端末と同じ Apple アカウントで作った共有です。自分の共有は受け取れません。\n同じ Apple アカウントの iPad・iPhone どうしは、設定の「iCloud で同期する」をオンにすれば同じシフト表になります。共有は、ほかの人の Apple アカウントの端末で開いてください。"
            return
        }
        Task { @MainActor in
            guard let db = ShiftDatabase.current else { return }
            do {
                try await db.accept(metadata)
                self.message = "共有されたシフト表を受け取りました。届くまで少しかかることがあります。届いたら自動で切り替わります（設定の「シフト表の共有」でも切り替えられます）。"
            } catch {
                self.message = ShareErrorText.message(error, fallback: "共有を受け取れませんでした")
            }
        }
    }
}

/// 招待のリンクを押したときに呼ばれる（アプリが開いているとき・閉じていたとき）
final class ShareSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        #if targetEnvironment(macCatalyst)
        // Mac：ウインドウを小さくしすぎて表が崩れないように
        (scene as? UIWindowScene)?.sizeRestrictions?.minimumSize = CGSize(width: 960, height: 640)
        #endif
        if let metadata = connectionOptions.cloudKitShareMetadata {
            Task { @MainActor in ShareInbox.shared.accept(metadata) }
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { @MainActor in ShareInbox.shared.accept(cloudKitShareMetadata) }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = ShareSceneDelegate.self
        return config
    }
}

/// Apple の共有の画面を、いちばん上の画面から出す（参加者の招待・権限・共有をやめる）
@MainActor
enum CloudSharingPresenter {
    private static var delegate: Delegate?

    static func present(_ share: CKShare, container: CKContainer, onChange: @escaping (CKShare?) -> Void) {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowPrivate, .allowReadWrite, .allowReadOnly]
        let d = Delegate(onChange: onChange)
        delegate = d
        controller.delegate = d
        guard let top = topViewController() else { return }
        if let pop = controller.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        top.present(controller, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }

    private final class Delegate: NSObject, UICloudSharingControllerDelegate {
        let onChange: (CKShare?) -> Void
        init(onChange: @escaping (CKShare?) -> Void) { self.onChange = onChange }

        func itemTitle(for csc: UICloudSharingController) -> String? { "シフト表" }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            Task { @MainActor in ShareInbox.shared.message = ShareErrorText.message(error, fallback: "共有を保存できませんでした") }
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            let share = csc.share
            let done = onChange
            Task { @MainActor in done(share) }
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            let done = onChange
            Task { @MainActor in done(nil) }
        }
    }
}

/// 設定 → シフト表の共有
struct ShareSettingsView: View {
    @Environment(\.shiftDatabase) private var db
    @Environment(\.shiftStore) private var store
    @State private var teams: [ShiftDatabase.TeamInfo] = []
    @State private var working = false
    @State private var error: String?

    var body: some View {
        let active = teams.first(where: \.isActive)
        Form {
            if !db.iCloudEnabled {
                Section {
                    Toggle("iCloud で同期する", isOn: Binding(get: { db.iCloudEnabled }, set: { db.setICloud($0) }))
                } footer: {
                    Text("共有には iCloud 同期が要ります。オンにすると、この端末のシフト表が iCloud に保存されます。")
                }
            }

            if teams.count > 1 {
                Section {
                    ForEach(teams) { t in
                        Button {
                            db.setActiveTeam(t.sharedWithMe ? t.id : nil)
                            store.reload()
                            refresh()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.title).foregroundStyle(.primary)
                                    if t.sharedWithMe {
                                        Text(t.canEdit ? "編集できる" : "見るだけ").appFont(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if t.isActive { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                            }
                        }
                    }
                } header: {
                    Text("表示するシフト表")
                } footer: {
                    Text("自分のシフト表と、ほかの人から共有されたシフト表を切り替えます（端末ごとに覚えます）。")
                }
            }

            Section {
                if let active, active.sharedWithMe {
                    LabeledContent("共有した人", value: active.ownerName.map { "\($0)さん" } ?? "—")
                    LabeledContent("この端末でできること", value: active.canEdit ? "編集できる" : "見るだけ")
                    Button { manage() } label: { Label("参加者を見る・共有から抜ける", systemImage: "person.2") }
                        .disabled(working)
                } else {
                    LabeledContent("いまの状態", value: (active?.participants ?? 0) > 0 ? "\(active?.participants ?? 0)人と共有中" : "共有していません")
                    Button { manage() } label: {
                        Label((active?.participants ?? 0) > 0 ? "参加者を管理する" : "シフト表を共有する", systemImage: "person.badge.plus")
                    }
                    .disabled(working || !db.iCloudEnabled)
                }
                if working { ProgressView() }
            } header: {
                Text("共有")
            } footer: {
                Text("招待は、メッセージ・メール、または「リンクをコピー」してから LINE などで送ってください（AirDrop で送ったリンクは開けないことがあります）。相手ごとに「編集できる」か「見るだけ」かを選べます。招待された人は、自分の端末でリンクを1回押すと同じシフト表を使えます（相手の端末にも SHIFT が要ります）。")
            }

            Section("共有されるもの・されないもの") {
                Label("店舗・部門・時間のひな形・スタッフ・シフト・マスのメモ・希望休の申請・会社の情報・人件費の予算と割増の決まり", systemImage: "checkmark.circle")
                    .appFont(.subheadline)
                Label("時給・月給（給与）は共有されません。この端末と、同じ Apple ID の端末にだけ残ります。", systemImage: "lock")
                    .appFont(.subheadline)
                Label("共有を始める前に、同じ Apple ID のほかの端末の SHIFT も最新の版にしてください（前の版は給与をスタッフの記録に書くため）。", systemImage: "exclamationmark.triangle")
                    .appFont(.footnote).foregroundStyle(.orange)
            }
        }
        .navigationTitle("シフト表の共有")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refresh)
        .onChange(of: db.changeToken) { refresh() }
        .errorAlert($error)
    }

    private func refresh() { teams = db.teams() }

    /// 共有を作って（まだなら）、Apple の共有の画面を出す
    private func manage() {
        working = true
        Task { @MainActor in
            defer { working = false }
            do {
                let pair: (CKShare, CKContainer)
                if let existing = db.shareForActiveTeam() {
                    pair = (existing, CKContainer(identifier: ShiftDatabase.cloudContainerID))
                } else {
                    pair = try await db.makeShare()
                }
                CloudSharingPresenter.present(pair.0, container: pair.1) { updated in
                    Task { @MainActor in
                        if let updated { await db.persistUpdatedShare(updated) }
                        store.reload()
                        refresh()
                    }
                }
                refresh()
            } catch {
                self.error = ShareErrorText.message(error)
            }
        }
    }
}

/// 共有の失敗を、英語の技術的な文ではなく、やることがわかる文にする
enum ShareErrorText {
    static func message(_ error: Error, fallback: String = "共有を始められませんでした") -> String {
        if error is ShareError { return error.localizedDescription }
        let detail = String(describing: error)
        // 権限ファイルに iCloud 共有の項目（com.apple.developer.icloud-extended-share-access）が無い版
        if detail.contains("icloud-extended-share-access") || detail.contains("OneTimeLinks") {
            return "このアプリの版では iCloud 共有を始められません。App Store（または TestFlight）で SHIFT を最新の版にしてから、もう一度お試しください。"
        }
        // 「招待した人だけ」の共有で、招待先（メール・電話番号）とこの端末の Apple アカウントが結びつかないとき。
        // CloudKit は internalError（1）で「couldn't decrypt the share as an invited user」と返す
        if detail.contains("decrypt the share as an invited user") {
            return "\(fallback)。この共有は「招待した人だけ」が開ける設定で、この端末の Apple アカウントが招待先として見つかりませんでした。\n共有した人に、次のどちらかをしてもらってください。\n・共有の画面で、この端末の Apple アカウントのメールアドレス（または電話番号）を招待先に入れて、招待し直す\n・共有のオプションを「リンクを知っている人は誰でも」にして、リンクを送り直す"
        }
        if let ck = cloudKitError(error) {
            switch ck.code {
            case .unknownItem, .zoneNotFound, .userDeletedZone, .badContainer, .changeTokenExpired:
                return "\(fallback)。共有がやめられたか、招待を作った端末と受け取る端末でアプリの種類が違う可能性があります（Xcode から入れた開発版と、TestFlight・App Store の版のあいだでは共有できません）。同じ種類の版どうしで、新しい招待を送り直してください。\n（\(ck.code.rawValue)：\(ck.localizedDescription)）"
            case .participantMayNeedVerification:
                return "\(fallback)。招待されたメールアドレス・電話番号と、この端末の Apple アカウントが違います。共有した人に、この端末の Apple アカウントで招待し直してもらってください。"
            case .alreadyShared:
                return "\(fallback)。このシフト表は、すでにこの端末に届いています。設定の「シフト表の共有」で切り替えてください。"
            case .notAuthenticated:
                return "iCloud にサインインしていません。「設定」アプリの一番上（Apple アカウント）でサインインし、iCloud Drive をオンにしてください。"
            case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
                return "iCloud につながりませんでした。インターネットの接続を確かめて、少し待ってからもう一度お試しください。"
            case .quotaExceeded:
                return "iCloud の空き容量が足りません。「設定」アプリの iCloud で空きを作ってから、もう一度お試しください。"
            case .permissionFailure:
                return "この Apple アカウントでは共有できません（ファミリー共有の制限などを確かめてください）。"
            default:
                break
            }
        }
        // 外側は「Failed to accept some shares」のような要約だけなので、中の原因も添える
        let inner = nestedErrors(error).dropFirst().map { "\($0.domain) \($0.code)：\($0.localizedDescription)" }
        let reason = inner.isEmpty ? error.localizedDescription : "\(error.localizedDescription) / " + inner.prefix(3).joined(separator: " / ")
        return "\(fallback)（\(reason)）"
    }

    /// NSPersistentCloudKitContainer はエラーを包んで返すので、中の CKError を探す。
    /// 一部だけ失敗（partialFailure）のときは、記録ごとの失敗の中から探す
    private static func cloudKitError(_ error: Error) -> CKError? {
        let all = nestedErrors(error).filter { $0.domain == CKErrorDomain }
        let specific = all.first { $0.code != CKError.Code.partialFailure.rawValue }
        return (specific ?? all.first).map { CKError(_nsError: $0) }
    }

    /// エラーとその中に入っているエラーを、外側から順に並べる（深さ・数に上限あり）
    private static func nestedErrors(_ error: Error) -> [NSError] {
        var result: [NSError] = []
        var queue: [NSError] = [error as NSError]
        while let e = queue.first, result.count < 20 {
            queue.removeFirst()
            result.append(e)
            if let u = e.userInfo[NSUnderlyingErrorKey] as? NSError { queue.append(u) }
            if let list = e.userInfo[NSMultipleUnderlyingErrorsKey] as? [NSError] { queue.append(contentsOf: list) }
            if let list = e.userInfo["NSDetailedErrors"] as? [NSError] { queue.append(contentsOf: list) }
            if let partial = e.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Any] {
                queue.append(contentsOf: partial.values.compactMap { $0 as? NSError })
            }
        }
        return result
    }
}
