import SwiftUI

// MARK: - 希望休の申請：受け取る・承認する・返事する

/// 1件の申請と、その人
struct LeaveRequestRow: Identifiable, Hashable {
    let member: StaffMember
    let request: LeaveRequest
    var id: String { request.id }
    var day: DayKey? { DayKey(request.day) }
}

/// 承認・却下したあと、スタッフに返事を送るための内容
struct LeaveReply: Identifiable {
    let member: StaffMember
    let decided: [LeaveRequest]
    var id: String { member.id + decided.map(\.id).joined() }
}

/// 希望休の一覧の上に出す「承認待ち」と「申請の結果」
struct LeaveRequestSections: View {
    let month: MonthKey
    @Environment(ShiftStore.self) private var store
    @AppStorage("requestAlsoOff") private var alsoOff = true
    /// 返事・エラーの画面は一覧（親）に出す
    @Binding var reply: LeaveReply?
    @Binding var error: String?

    var body: some View {
        let book = store.book
        let deptColor = Dictionary(book.departments.map { ($0.id, $0.colorIndex) }, uniquingKeysWith: { a, _ in a })
        let visible = book.staffByDepartment(visibleIn: month).flatMap(\.members)
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
                }
                if pending.count > 1 {
                    Button { decide(pending, .approved) } label: {
                        Label("\(pending.count)件をまとめて承認", systemImage: "checkmark.circle")
                    }
                }
            } header: {
                Text("承認待ちの申請（\(pending.count)件）")
            } footer: {
                Text("右へスワイプで却下、左へスワイプで承認。承認すると希望休に入り\(alsoOff ? "、シフトも休みになります" : "ます")（「希望休を入れる」の「シフトも休みにする」に従います）。")
            }
        }

        if !decided.isEmpty {
            Section {
                ForEach(decided) { r in
                    HStack(spacing: 10) {
                        Text(r.member.name).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(r.day.map { HomeView.dayLabel($0) } ?? r.request.day).font(.subheadline).monospacedDigit()
                        StatusPill(text: r.request.status.label, color: r.request.status == .approved ? .green : .gray)
                    }
                    .swipeActions {
                        Button { decide([r], .pending, sendReply: false) } label: { Label("承認待ちに戻す", systemImage: "arrow.uturn.backward") }
                            .tint(.orange)
                    }
                }
            } header: {
                Text("\(month.month)月の申請の結果")
            }
        }
    }

    private func pendingRow(_ r: LeaveRequestRow, color: Int, book: ShiftBook) -> some View {
        let shift = r.day.flatMap { Schedule.resolve(r.member, on: $0, in: book) }
        return HStack(spacing: 12) {
            InitialAvatar(name: r.member.name, colorIndex: color, size: 34, photo: r.member.photo)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(r.member.name).font(.body.weight(.semibold))
                    Text(r.day.map { HomeView.dayLabel($0) } ?? r.request.day).font(.subheadline.weight(.semibold)).monospacedDigit()
                }
                if !r.request.note.isEmpty {
                    Text(r.request.note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
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

    /// 決めたら、その人ごとに返事を作れるようにする（複数の人をまとめて決めたときは、最初の人の返事）
    private func decide(_ rows: [LeaveRequestRow], _ status: LeaveRequest.Status, sendReply: Bool = true) {
        let offBlock = alsoOff ? defaultOffBlockID() : nil
        do {
            for (staffID, list) in Dictionary(grouping: rows, by: { $0.member.id }) {
                try store.decideLeaveRequests(Set(list.map(\.id)), as: status, for: staffID, offBlockID: offBlock)
            }
            guard sendReply, let first = rows.first,
                  let fresh = store.book.staff.first(where: { $0.id == first.member.id }) else { return }
            let ids = Set(rows.filter { $0.member.id == fresh.id }.map(\.id))
            reply = LeaveReply(member: fresh, decided: fresh.leaveRequests.filter { ids.contains($0.id) })
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

/// スタッフへの返事（LINE などで送る）
struct LeaveReplySheet: View {
    let reply: LeaveReply
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("返事", text: $text, axis: .vertical).lineLimit(4...12)
                } header: {
                    Text("\(reply.member.name)さんへの返事")
                } footer: {
                    Text("直してから送れます。「送る」で LINE・メッセージ・AirDrop などを選べます。")
                }
                Section {
                    ShareLink(item: text) { Label("送る", systemImage: "square.and.arrow.up") }
                    Button { UIPasteboard.general.string = text } label: { Label("コピー", systemImage: "doc.on.doc") }
                }
            }
            .navigationTitle("返事を送る")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
            .onAppear { if text.isEmpty { text = LeaveRequestInbox.reply(to: reply.member, reply.decided) } }
        }
    }
}

/// LINE・AirDrop などで届いた申請の文章を貼り付けて、承認待ちにする
struct LeaveRequestImportSheet: View {
    @State var month: MonthKey
    @Environment(ShiftStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var staffID = ""
    /// 名前を手で選んだら、文章から決め直さない
    @State private var staffPicked = false
    @State private var excluded: Set<DayKey> = []
    @State private var error: String?
    @State private var result: String?

    var body: some View {
        let book = store.book
        let members = book.staffByDepartment(visibleIn: month).flatMap(\.members)
        let parsed = OffRequestParser.parse(text, month: month)
        let chosen = parsed.filter { !excluded.contains($0) }
        let member = members.first { $0.id == staffID }

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
                    Picker("スタッフ", selection: Binding(get: { staffID }, set: { staffID = $0; staffPicked = true })) {
                        Text("選んでください").tag("")
                        ForEach(members) { Text($0.name).tag($0.id) }
                    }
                    if !text.isEmpty, staffID.isEmpty {
                        Text("文章から名前が見つかりませんでした。スタッフを選んでください。").font(.footnote).foregroundStyle(.orange)
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
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                            ForEach(parsed, id: \.self) { d in
                                let on = !excluded.contains(d)
                                Button {
                                    if on { excluded.insert(d) } else { excluded.remove(d) }
                                } label: {
                                    Text(HomeView.dayLabel(d)).font(.subheadline.weight(.semibold)).monospacedDigit()
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
                        .disabled(member == nil || chosen.isEmpty)
                }
            }
            .onChange(of: text) {
                excluded = []
                if !staffPicked, let m = LeaveRequestInbox.detectStaff(in: text, among: members) { staffID = m.id }
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
        let note = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
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
