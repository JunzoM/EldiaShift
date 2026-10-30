import SwiftUI

// MARK: - 希望休の申請：受け取る・承認する・返事する

/// 1件の申請と、その人
struct LeaveRequestRow: Identifiable, Hashable {
    let member: StaffMember
    let request: LeaveRequest
    var id: String { request.id }
    var day: DayKey? { DayKey(request.day) }
}

/// 承認・却下したあと、スタッフに返事を送るための内容（複数の人をまとめて決めたときは、宛名ごと）
struct LeaveReply: Identifiable {
    struct Recipient: Identifiable {
        let member: StaffMember
        let decided: [LeaveRequest]
        var id: String { member.id }
    }
    let recipients: [Recipient]
    var id: String { recipients.map { $0.id + $0.decided.map(\.id).joined() }.joined(separator: "|") }
}

/// 希望休の一覧の上に出す「承認待ち」と「申請の結果」
struct LeaveRequestSections: View {
    let month: MonthKey
    /// 部門で絞り込むとき（nil はすべての部門）
    var departmentID: String? = nil
    @Environment(\.shiftStore) private var store
    @AppStorage("requestAlsoOff") private var alsoOff = true
    /// 返事・エラーの画面は一覧（親）に出す
    @Binding var reply: LeaveReply?
    @Binding var error: String?
    /// まとめて承認・却下する前の確認
    @State private var bulk: LeaveRequest.Status?
    /// 消す前の確認（申請の id）
    @State private var deleting: String?

    var body: some View {
        let book = store.book
        let deptColor = Dictionary(book.departments.map { ($0.id, $0.colorIndex) }, uniquingKeysWith: { a, _ in a })
        let visible = book.staffByDepartment(visibleIn: month)
            .filter { departmentID == nil || $0.department.id == departmentID }
            .flatMap(\.members)
        let all = visible.flatMap { m in m.leaveRequests.map { LeaveRequestRow(member: m, request: $0) } }
        let pending = all.filter { $0.request.status == .pending }.sorted { ($0.request.day, $0.member.name) < ($1.request.day, $1.member.name) }
        let decided = all.filter { $0.request.status != .pending && $0.day.map { MonthKey($0) == month } == true }
            .sorted { ($0.request.day, $0.member.name) < ($1.request.day, $1.member.name) }

        if !pending.isEmpty {
            Section {
                ForEach(pending) { r in
                    pendingRow(r, color: deptColor[r.member.departmentID] ?? 8, book: book)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button { decide([r], .approved) } label: { Label("承認", systemImage: "checkmark") }.tint(.green)
                        }
                        .swipeActions(edge: .leading) {
                            Button { decide([r], .rejected) } label: { Label("却下", systemImage: "xmark") }.tint(.red)
                        }
                        .contextMenu {
                            Button { decide([r], .approved) } label: { Label("承認", systemImage: "checkmark") }
                            Button { decide([r], .rejected) } label: { Label("却下", systemImage: "xmark") }
                            Button(role: .destructive) { deleting = r.id } label: { Label("申請を削除", systemImage: "trash") }
                        }
                        .modifier(deleteConfirm(r))
                }
                if pending.count > 1 {
                    HStack(spacing: 12) {
                        Button { bulk = .approved } label: {
                            Label("\(pending.count)件をまとめて承認", systemImage: "checkmark.circle")
                        }
                        Spacer(minLength: 8)
                        Button(role: .destructive) { bulk = .rejected } label: {
                            Label("まとめて却下", systemImage: "xmark.circle")
                        }
                    }
                    .buttonStyle(.borderless)
                    .confirmationDialog(bulkTitle(pending.count),
                                        isPresented: Binding(get: { bulk != nil }, set: { if !$0 { bulk = nil } }),
                                        titleVisibility: .visible, presenting: bulk) { status in
                        Button(bulkButton(status), role: status == .rejected ? .destructive : nil) {
                            decide(pending, status)
                        }
                    } message: { status in
                        Text(bulkMessage(pending, status))
                    }
                }
            } header: {
                Text("承認待ちの申請（\(pending.count)件）")
            } footer: {
                Text("右へスワイプで却下、左へスワイプで承認。長押しで申請を削除できます。承認すると希望休に入り\(alsoOff ? "、シフトも休みになります" : "ます")（「希望休を入れる」の「シフトも休みにする」に従います）。")
            }
        }

        if !decided.isEmpty {
            Section {
                ForEach(decided) { r in
                    HStack(spacing: 10) {
                        Text(r.member.name).appFont(.subheadline.weight(.semibold))
                        Spacer()
                        Text(r.day.map { HomeView.dayLabel($0) } ?? r.request.day).appFont(.subheadline).monospacedDigit()
                        StatusPill(text: r.request.status.label, color: r.request.status == .approved ? .green : .gray)
                    }
                    .swipeActions {
                        Button { decide([r], .pending, sendReply: false) } label: { Label("承認待ちに戻す", systemImage: "arrow.uturn.backward") }
                            .tint(.orange)
                        Button { deleting = r.id } label: { Label("削除", systemImage: "trash") }
                            .tint(.red)
                    }
                    .contextMenu {
                        Button { reply = LeaveReply(recipients: [.init(member: r.member, decided: [r.request])]) } label: {
                            Label("返事を作る", systemImage: "text.bubble")
                        }
                        Button { decide([r], .pending, sendReply: false) } label: { Label("承認待ちに戻す", systemImage: "arrow.uturn.backward") }
                        Button(role: .destructive) { deleting = r.id } label: { Label("申請を削除", systemImage: "trash") }
                    }
                    .modifier(deleteConfirm(r))
                }
            } header: {
                Text("\(month.month)月の申請の結果")
            } footer: {
                Text("左へスワイプで「承認待ちに戻す」「削除」。長押しで返事を作れます。")
            }
        }
    }

    private func pendingRow(_ r: LeaveRequestRow, color: Int, book: ShiftBook) -> some View {
        let shift = r.day.flatMap { Schedule.resolve(r.member, on: $0, in: book) }
        return HStack(spacing: 12) {
            InitialAvatar(name: r.member.name, colorIndex: color, size: 34, photo: r.member.photo)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(r.member.name).appFont(.body.weight(.semibold))
                    Text(r.day.map { HomeView.dayLabel($0) } ?? r.request.day).appFont(.subheadline.weight(.semibold)).monospacedDigit()
                }
                if !r.request.note.isEmpty {
                    Text(r.request.note).appFont(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            if let shift, !shift.isOff { StatusPill(text: "勤務あり", color: .red) }
            HStack(spacing: 6) {
                Button { decide([r], .rejected) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.bordered).tint(.red)
                    .accessibilityLabel("\(r.member.name)さんの申請を却下")
                Button { decide([r], .approved) } label: { Image(systemName: "checkmark") }
                    .buttonStyle(.borderedProminent).tint(.green)
                    .accessibilityLabel("\(r.member.name)さんの申請を承認")
            }
        }
        .padding(.vertical, 2)
    }

    /// 行ごとの「削除しますか？」
    private func deleteConfirm(_ r: LeaveRequestRow) -> LeaveDeleteConfirm {
        LeaveDeleteConfirm(row: r, isPresented: Binding(get: { deleting == r.id }, set: { if !$0 { deleting = nil } })) {
            do {
                try store.deleteLeaveRequests([r.id], for: r.member.id)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func bulkTitle(_ count: Int) -> String {
        bulk == .rejected ? "\(count)件をまとめて却下しますか？" : "\(count)件をまとめて承認しますか？"
    }

    private func bulkButton(_ status: LeaveRequest.Status) -> String {
        status == .rejected ? "まとめて却下" : "まとめて承認"
    }

    private func bulkMessage(_ rows: [LeaveRequestRow], _ status: LeaveRequest.Status) -> String {
        var lines = rows.prefix(6).map { "\($0.member.name)　\($0.day.map { HomeView.dayLabel($0) } ?? $0.request.day)" }
        if rows.count > 6 { lines.append("ほか\(rows.count - 6)件") }
        if status == .approved {
            lines.append(alsoOff ? "承認した日は希望休に入り、シフトも休みになります。" : "承認した日は希望休に入ります。")
        } else {
            lines.append("却下した日は希望休に入りません。このあと、宛名ごとの返事を作れます。")
        }
        return lines.joined(separator: "\n")
    }

    /// 決めたら返事を作れるようにする（複数の人をまとめて決めたときは、宛名ごとに分ける）
    private func decide(_ rows: [LeaveRequestRow], _ status: LeaveRequest.Status, sendReply: Bool = true) {
        let offBlock = alsoOff ? defaultOffBlockID() : nil
        do {
            for (staffID, list) in Dictionary(grouping: rows, by: { $0.member.id }) {
                try store.decideLeaveRequests(Set(list.map(\.id)), as: status, for: staffID, offBlockID: offBlock)
            }
            guard sendReply else { return }
            let groups = LeaveRequestInbox.replyGroups(Set(rows.map(\.id)), staff: store.book.staff)
            guard !groups.isEmpty else { return }
            reply = LeaveReply(recipients: groups.map { LeaveReply.Recipient(member: $0.member, decided: $0.decided) })
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// 「希望休を入れる」で選んでいる休みの種類（無ければ最初の休み）
    private func defaultOffBlockID() -> String? {
        let offs = store.book.templates.filter(\.isOff)
        return offs.first { $0.id == "off1" }?.id ?? offs.first?.id
    }
}

/// 申請を消す前の確認（承認済みなら、希望休・シフトは残ることを伝える）
private struct LeaveDeleteConfirm: ViewModifier {
    let row: LeaveRequestRow
    @Binding var isPresented: Bool
    let delete: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog("\(row.member.name)さんの \(row.day.map { HomeView.dayLabel($0) } ?? row.request.day) の申請を削除しますか？",
                                   isPresented: $isPresented, titleVisibility: .visible) {
            Button("削除", role: .destructive) { delete() }
        } message: {
            Text(row.request.status == .approved
                 ? "申請だけを消します。承認で入れた希望休とシフトはそのまま残ります。取り消せません。"
                 : "申請を消します。取り消せません。")
        }
    }
}

/// スタッフへの返事（LINE などで送る）。複数の人のときは宛名ごとに分けて、一人ずつ送る
struct LeaveReplySheet: View {
    let reply: LeaveReply
    @Environment(\.dismiss) private var dismiss
    @State private var texts: [String: String] = [:]

    var body: some View {
        NavigationStack {
            Form {
                if reply.recipients.count > 1 {
                    Section {
                        Text("\(reply.recipients.count)人に、宛名ごとの返事を作りました。一人ずつ直して送れます。")
                            .appFont(.footnote).foregroundStyle(.secondary)
                    }
                }
                ForEach(reply.recipients) { r in
                    let text = texts[r.id] ?? ""
                    Section {
                        TextField("返事", text: Binding(get: { texts[r.id] ?? "" }, set: { texts[r.id] = $0 }), axis: .vertical)
                            .lineLimit(4...12)
                        ShareLink(item: text) { Label("送る", systemImage: "square.and.arrow.up") }
                        Button { UIPasteboard.general.string = text } label: { Label("コピー", systemImage: "doc.on.doc") }
                    } header: {
                        Text("\(r.member.name)さんへの返事")
                    } footer: {
                        if r.id == reply.recipients.last?.id {
                            Text("直してから送れます。「送る」で LINE・メッセージ・AirDrop などを選べます。")
                        }
                    }
                }
            }
            .navigationTitle("返事を送る")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
            .onAppear {
                guard texts.isEmpty else { return }
                texts = Dictionary(reply.recipients.map { ($0.id, LeaveRequestInbox.reply(to: $0.member, $0.decided)) },
                                   uniquingKeysWith: { a, _ in a })
            }
        }
    }
}

/// LINE・AirDrop などで届いた申請の文章を貼り付けて、承認待ちにする
struct LeaveRequestImportSheet: View {
    @State var month: MonthKey
    /// 取り込み用リンクから開いたときの文章
    var initialText: String = ""
    @Environment(\.shiftStore) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var staffID = ""
    /// 名前を手で選んだら、文章から決め直さない
    @State private var staffPicked = false
    @State private var excluded: Set<DayKey> = []
    /// 申請の店舗とスタッフの店舗が違うのを確かめた
    @State private var storeConfirmed = false
    @State private var error: String?
    @State private var result: String?

    var body: some View {
        let book = store.book
        // どの店舗の人の申請でも受け取れるよう、いま見ている店舗に限らず全員から選ぶ（店舗名・名前の順）
        let order = Dictionary(book.allStores.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        let members = book.staff.filter { $0.isVisible(in: month) }
            .sorted { (order[book.homeStoreID(of: $0)] ?? 0, $0.name) < (order[book.homeStoreID(of: $1)] ?? 0, $1.name) }
        // 申請フォームの文章なら「休みたい日」の行だけから日付を読む（理由の数字を日付と間違えない）
        let form = LeaveRequestInbox.formFields(text)
        let parsed = OffRequestParser.parse(form?.dates ?? text, month: month)
        let chosen = parsed.filter { !excluded.contains($0) }
        let member = members.first { $0.id == staffID }
        let requestStore = form?.store ?? ""
        let storeWarning = member.flatMap { LeaveRequestInbox.storeWarning(requestStore: requestStore, member: $0, in: book) }

        NavigationStack {
            Form {
                Section {
                    TextField("例：山田です。11/3、10日〜12日 お休み希望です（通院）", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                    PasteButton(payloadType: String.self) { items in
                        Task { @MainActor in text = items.first ?? "" }
                    }
                } header: {
                    Text("届いた文章")
                } footer: {
                    Text("LINE・メッセージ・AirDrop で届いた文章をそのまま貼ります。名前と日付を読み取ります。")
                }

                Section("スタッフ") {
                    if !requestStore.isEmpty, book.allStores.count > 1 {
                        LabeledContent("申請の店舗", value: requestStore)
                    }
                    Picker("スタッフ", selection: Binding(get: { staffID }, set: { staffID = $0; staffPicked = true; storeConfirmed = false })) {
                        Text("選んでください").tag("")
                        ForEach(members) { Text($0.name).tag($0.id) }
                    }
                    if !text.isEmpty, staffID.isEmpty {
                        Text("文章から名前が見つかりませんでした。スタッフを選んでください。").appFont(.footnote).foregroundStyle(.orange)
                    }
                    if let storeWarning {
                        Label(storeWarning, systemImage: "exclamationmark.triangle").appFont(.footnote).foregroundStyle(.orange)
                        Toggle("このスタッフの申請として受け取る", isOn: $storeConfirmed)
                    }
                }

                Section {
                    Picker("「12日」などを読む月", selection: $month) {
                        ForEach(-1...3, id: \.self) { n in
                            let m = MonthKey.current.adding(months: n)
                            Text("\(m.year)年\(m.month)月").tag(m)
                        }
                    }
                    if parsed.isEmpty {
                        Text(text.isEmpty ? "文章を貼ると、ここに日付が出ます。" : "日付が見つかりませんでした。")
                            .appFont(.footnote).foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                            ForEach(parsed, id: \.self) { d in
                                let on = !excluded.contains(d)
                                Button {
                                    if on { excluded.insert(d) } else { excluded.remove(d) }
                                } label: {
                                    Text(HomeView.dayLabel(d)).appFont(.subheadline.weight(.semibold)).monospacedDigit()
                                        .frame(maxWidth: .infinity, minHeight: 34)
                                        .foregroundStyle(on ? Color.white : Color.secondary)
                                        .background(on ? Color.purple : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(d.month)月\(d.day)日\(on ? "、申請に入れる" : "、外す")")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("休みたい日（押して外す・戻す）")
                }
            }
            .navigationTitle("申請を受け取る")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("やめる") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("承認待ちにする") { save(member, chosen) }.bold()
                        .disabled(member == nil || chosen.isEmpty || (storeWarning != nil && !storeConfirmed))
                }
            }
            .onAppear { if text.isEmpty, !initialText.isEmpty { text = initialText } }
            .onChange(of: text) {
                excluded = []
                storeConfirmed = false
                let source = LeaveRequestInbox.formFields(text)?.name ?? text
                if !staffPicked, let m = LeaveRequestInbox.detectStaff(in: source, among: members) { staffID = m.id }
            }
            .alert("受け取りました", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil; dismiss() } })) {
                Button("OK") { result = nil; dismiss() }
            } message: {
                Text(result ?? "")
            }
            .errorAlert($error)
        }
    }

    private func save(_ member: StaffMember?, _ days: [DayKey]) {
        guard let member else { return }
        let form = LeaveRequestInbox.formFields(text)
        let note = form.map { $0.reason } ?? String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        do {
            let added = try store.receiveLeaveRequests(days, note: note, for: member.id)
            let skipped = days.count - added
            result = "\(member.name)さんの \(added)日を承認待ちにしました。"
                + (skipped > 0 ? "\n\(skipped)日は、すでに申請済みか希望休に入っています。" : "")
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// 希望休の画面のいちばん上に出す「申請の受け取り方」（たためる。iCloud 同期がオフなら注意）
struct LeaveRequestGuide: View {
    @Environment(\.shiftDatabase) private var db
    @AppStorage("leaveGuideOpen") private var open = true
    var showQR: () -> Void
    var receive: () -> Void

    private var isPad: Bool {
        #if targetEnvironment(macCatalyst)
        return true   // Mac も iPad と同じ案内（LINE のある iPhone で受け取って iCloud で届ける）
        #else
        return UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $open) {
                VStack(alignment: .leading, spacing: 10) {
                    step(1, "スタッフが、壁の QR コードから休みたい日を入れて LINE で送ります。")
                    step(2, "LINE に届いた「取り込み用リンク」を押すと SHIFT が開きます。「承認待ちにする」を押します。")
                    step(3, "この画面の「承認待ちの申請」で、承認・却下します。")
                }
                .padding(.vertical, 4)

                Label {
                    Text(isPad
                         ? "この iPad に LINE が無いときは、LINE が入っている iPhone にも SHIFT を入れて、iPhone でリンクを押してください。同じ Apple ID で iCloud 同期をオンにすると、iPhone で受け取った申請がこの iPad にも出ます。"
                         : "iPad で承認するときは、iPad とこの iPhone を同じ Apple ID にして iCloud 同期をオンにしてください。この iPhone で受け取った申請が iPad にも出ます。")
                        .appFont(.footnote)
                } icon: {
                    Image(systemName: isPad ? "iphone" : "ipad").foregroundStyle(.secondary)
                }

                if db.iCloudEnabled {
                    Label("iCloud 同期：オン（ほかの端末で受け取った申請もここに出ます）", systemImage: "checkmark.icloud")
                        .appFont(.footnote).foregroundStyle(.green)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("iCloud 同期がオフです。ほかの端末で受け取った申請は、この端末に出ません。", systemImage: "exclamationmark.icloud")
                            .appFont(.footnote).foregroundStyle(.orange)
                        Toggle("iCloud で同期する", isOn: Binding(get: { db.iCloudEnabled }, set: { db.setICloud($0) }))
                            .appFont(.subheadline)
                    }
                }

                HStack(spacing: 10) {
                    Button(action: showQR) { Label("申請用QRコード", systemImage: "qrcode") }
                    Button(action: receive) { Label("貼り付けで受け取る", systemImage: "doc.on.clipboard") }
                }
                .buttonStyle(.bordered)
                .appFont(.subheadline)
            } label: {
                Label("申請の受け取り方", systemImage: "questionmark.circle").appFont(.subheadline.weight(.semibold))
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)").appFont(.caption.weight(.bold)).foregroundStyle(.white)
                .frame(width: 20, height: 20).background(Color.accentColor, in: Circle())
            Text(text).appFont(.subheadline)
        }
    }
}

/// 電話・口頭で聞いた申請を、管理者が代わりに登録する（承認待ちになる）
struct LeaveRequestProxySheet: View {
    @State var month: MonthKey
    @Environment(\.shiftStore) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var staffID = ""
    @State private var picked: Set<DayKey> = []
    @State private var reason = ""
    @State private var error: String?
    @State private var result: String?

    var body: some View {
        let book = store.book
        let members = book.staffByDepartment(visibleIn: month).flatMap(\.members)
        // 月を動かしても選んだ人は外さない
        let member = book.staff.first { $0.id == staffID }
        let taken = Set((member?.leaveRequests.filter { $0.status != .rejected }.map(\.day) ?? []) + (member?.offRequests ?? []))

        NavigationStack {
            Form {
                Section("スタッフ") {
                    Picker("スタッフ", selection: $staffID) {
                        Text("選んでください").tag("")
                        if let member, !members.contains(where: { $0.id == member.id }) { Text(member.name).tag(member.id) }
                        ForEach(members) { Text($0.name).tag($0.id) }
                    }
                }

                Section {
                    HStack {
                        Button { month = month.adding(months: -1) } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel("前の月")
                        Spacer()
                        Text(month.description).appFont(.headline).monospacedDigit()
                        Spacer()
                        Button { month = month.adding(months: 1) } label: { Image(systemName: "chevron.right") }
                            .accessibilityLabel("次の月")
                    }
                    .buttonStyle(.borderless)
                    LeaveDayCalendar(month: month, picked: $picked, taken: taken, enabled: member != nil)
                } header: {
                    Text("休みたい日（押して選ぶ・外す）")
                } footer: {
                    if member == nil {
                        Text("先にスタッフを選んでください。")
                    } else {
                        Text("選んだ日：\(picked.count)日。薄い日は、申請済みか希望休に入っています。月をまたいで選べます。")
                    }
                }

                Section {
                    TextField("例：通院（電話で連絡あり）", text: $reason)
                } header: {
                    Text("理由（なくても可）")
                } footer: {
                    Text("「承認待ち」として登録します。承認・却下は希望休の画面の「承認待ちの申請」で決めます。")
                }
            }
            .navigationTitle("代わりに申請を登録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("やめる") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("承認待ちにする") { save(member) }.bold()
                        .disabled(member == nil || picked.isEmpty)
                }
            }
            .onChange(of: staffID) { picked = [] }
            .alert("登録しました", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil; dismiss() } })) {
                Button("OK") { result = nil; dismiss() }
            } message: {
                Text(result ?? "")
            }
            .errorAlert($error)
        }
    }

    private func save(_ member: StaffMember?) {
        guard let member else { return }
        let days = picked.sorted()
        let why = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = why.isEmpty ? "代理登録" : "代理登録：\(why)"
        do {
            let added = try store.receiveLeaveRequests(days, note: String(note.prefix(200)), for: member.id)
            let skipped = days.count - added
            result = "\(member.name)さんの \(added)日を承認待ちにしました。"
                + (skipped > 0 ? "\n\(skipped)日は、すでに申請済みか希望休に入っています。" : "")
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// 月のカレンダーで日を選ぶ（いくつでも）。taken の日（YYYY-MM-DD）は選べない
struct LeaveDayCalendar: View {
    let month: MonthKey
    @Binding var picked: Set<DayKey>
    var taken: Set<String> = []
    var enabled = true

    var body: some View {
        let days = month.days
        let lead = days[0].weekday
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(["日", "月", "火", "水", "木", "金", "土"], id: \.self) { Text($0).appFont(.caption2).foregroundStyle(.secondary) }
            ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 36) }
            ForEach(days, id: \.self) { d in
                dayButton(d)
            }
        }
        .padding(.vertical, 4)
    }

    private func dayButton(_ d: DayKey) -> some View {
        let on = picked.contains(d)
        let isTaken = taken.contains(d.description)
        let red = d.weekday == 0 || JapaneseHolidays.isHoliday(d)
        let ink: Color = on ? .white : red ? .red : d.weekday == 6 ? .blue : .primary
        return Button {
            if on { picked.remove(d) } else { picked.insert(d) }
        } label: {
            Text("\(d.day)").appFont(.subheadline.weight(on ? .bold : .regular)).monospacedDigit()
                .frame(maxWidth: .infinity, minHeight: 36)
                .foregroundStyle(ink)
                .background(on ? Color.purple : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                .opacity(isTaken ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .disabled(!enabled || isTaken)
        .accessibilityLabel("\(d.month)月\(d.day)日\(isTaken ? "、申請済み" : on ? "、選択中" : "")")
    }
}
