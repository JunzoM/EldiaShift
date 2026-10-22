import SwiftUI
import UniformTypeIdentifiers

/// マスを押したときの詳細（この段階では見るだけ。編集は次の段階）
struct CellDetailSheet: View {
    let member: StaffMember
    let day: DayKey

    @Environment(ShiftStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let book = store.book
        let r = Schedule.resolve(member, on: day, in: book)
        let block = book.block(r?.blockID, for: member)
        NavigationStack {
            List {
                Section {
                    if member.hasLeft(on: day) {
                        Text("退職日より後の日です").foregroundStyle(.secondary)
                    } else if let r {
                        if r.isOff {
                            LabeledContent("内容", value: block?.label ?? "休み")
                        } else {
                            LabeledContent("出勤", value: r.inTime.isEmpty ? "—" : r.inTime)
                            LabeledContent("退勤", value: r.outTime.isEmpty ? "—" : r.outTime)
                            if let h = r.hours {
                                LabeledContent("拘束時間", value: String(format: "%.1f 時間", h))
                                let b = r.breakMinutes(book.breakRules) ?? 0
                                LabeledContent("実働（休憩 \(b == 0 ? "なし" : "\(b)分")）",
                                               value: String(format: "%.1f 時間", r.netHours(book.breakRules) ?? h))
                            }
                            if let block { LabeledContent("ひな形", value: block.label) }
                        }
                        LabeledContent("決まり方", value: source(r))
                    } else {
                        Text("まだ決まっていません").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("\(day.month)月\(day.day)日（\(["日", "月", "火", "水", "木", "金", "土"][day.weekday])）\(member.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } }
            }
        }
    }

    private func source(_ r: ResolvedShift) -> String {
        if !r.isAuto { return "手で入力" }
        if r.isPeriod { return "期間の予定" }
        return "週のくり返し" + (r.patternLabel.map { "（\($0)）" } ?? "")
    }
}

// MARK: - バックアップの取り込み

extension View {
    /// バックアップ（.json）を選んで取り込む。中身を確認してから置き換える
    func backupImporter(isPresented: Binding<Bool>) -> some View {
        modifier(BackupImporter(isPresented: isPresented))
    }
}

private struct BackupImporter: ViewModifier {
    @Binding var isPresented: Bool
    @Environment(ShiftStore.self) private var store
    @State private var pending: (ShiftBook, BackupFile.Summary)?
    @State private var message: String?

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $isPresented, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url): read(url)
                case .failure(let error): message = error.localizedDescription
                }
            }
            .confirmationDialog("取り込みますか？", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                                titleVisibility: .visible) {
                Button("今の内容を置き換えて取り込む", role: .destructive) { apply() }
                Button("やめる", role: .cancel) { pending = nil }
            } message: {
                if let s = pending?.1 { Text(summaryText(s)) }
            }
            .alert("お知らせ", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: {
                Text(message ?? "")
            }
    }

    private func read(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            pending = try BackupFile.read(data)
        } catch {
            message = error.localizedDescription
        }
    }

    private func apply() {
        guard let p = pending else { return }
        let (book, summary) = p
        pending = nil
        do {
            try store.autoBackup(reason: "読込前")
            try store.replaceAll(with: book)
            message = "取り込みました（スタッフ \(summary.staff)人・シフト \(summary.cells)件）。"
        } catch {
            message = "取り込めませんでした（\(error.localizedDescription)）"
        }
    }

    private func summaryText(_ s: BackupFile.Summary) -> String {
        var lines = ["スタッフ \(s.staff)人", "時間のひな形 \(s.templates)件", "手で入れたシフト \(s.cells)件"]
        if let a = s.firstDay, let b = s.lastDay { lines.append("期間 \(a) 〜 \(b)") }
        if s.skipped > 0 { lines.append("読めなかった項目 \(s.skipped)件（取り込みません）") }
        lines.append("この端末のシフト表は、この内容に置き換わります。")
        return lines.joined(separator: "\n")
    }
}

// MARK: - 設定

struct SettingsView: View {
    @Environment(ShiftDatabase.self) private var db
    @Environment(ShiftStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var exportFile: ExportFile?
    @State private var exportError: String?
    @State private var confirmReset = false
    @State private var tipsReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("iCloud で同期する", isOn: Binding(get: { db.iCloudEnabled }, set: { db.setICloud($0) }))
                } footer: {
                    Text("同じ Apple ID の iPad・iPhone で同じシフト表を使えます。ほかの管理者との共同編集は、次の更新で使えるようになります。")
                }

                Section {
                    NavigationLink { ManualView() } label: { Label("操作マニュアル", systemImage: "questionmark.circle") }
                    Button {
                        CoachCenter.shared.resetAll()
                        tipsReset = true
                    } label: { Label("操作のヒントをもう一度見る", systemImage: "lightbulb") }
                } footer: {
                    if tipsReset {
                        Text("ボタンを初めて押したときの説明が、もう一度出るようになりました。")
                    }
                }

                Section("シフト表の中身") {
                    NavigationLink("スタッフ") { StaffListView() }
                    NavigationLink("部門") { DepartmentListView() }
                    NavigationLink("時間のひな形") { TemplateListView() }
                    NavigationLink { BreakRulesView() } label: {
                        LabeledContent("休憩の決まり", value: store.book.breakRules.summary)
                    }
                }

                Section {
                    Button("バックアップを取り込む") { importing = true }
                    Button("バックアップを書き出す") { export() }
                        .disabled(store.book.isEmpty)
                } header: {
                    Text("バックアップ")
                } footer: {
                    Text("PC版シフト表の「バックアップを保存」で作ったファイルを取り込めます。書き出したファイルは PC版でも読み込めます。")
                }

                Section {
                    Button("すべて消去して一から作り直す", role: .destructive) { confirmReset = true }
                } footer: {
                    Text("スタッフ・共通の時間・入力したシフトをすべて消します（部署と休みの種類は残ります）。消す前と、バックアップを読み込む前には、自動でバックアップを残します（「ファイル」アプリ →「このiPad内」→「シフト表」→「自動バックアップ」）。")
                }

                Section("内容") {
                    LabeledContent("スタッフ", value: "\(store.book.staff.count)人")
                    LabeledContent("部門", value: "\(store.book.departments.count)")
                    LabeledContent("時間のひな形", value: "\(store.book.templates.count)")
                    LabeledContent("手で入れたシフト", value: "\(store.book.cells.count)件")
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } }
            }
            .backupImporter(isPresented: $importing)
            .confirmationDialog("すべて消去しますか？", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("すべて消去する", role: .destructive) {
                    do { try store.resetAll(); dismiss() } catch { exportError = error.localizedDescription }
                }
            } message: {
                Text("消す前に自動でバックアップを残します。")
            }
            .sheet(item: $exportFile) { f in ShareSheet(items: [f.url]) }
            .alert("書き出せませんでした", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button("OK") { exportError = nil }
            } message: {
                Text(exportError ?? "")
            }
        }
    }

    private func export() {
        do {
            let data = try store.exportData()
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyyMMdd-HHmm"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("shift-\(f.string(from: Date())).json")
            try data.write(to: url, options: .atomic)
            exportFile = ExportFile(url: url)
        } catch {
            exportError = error.localizedDescription
        }
    }
}

struct ExportFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// iOS の共有シート
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
