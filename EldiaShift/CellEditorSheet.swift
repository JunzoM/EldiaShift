import SwiftUI

/// 1人×1日を変える画面（ひな形を押すとすぐ決まる。時刻を指定することもできる）
struct CellEditorSheet: View {
    let member: StaffMember
    let day: DayKey

    @Environment(\.shiftStore) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var inM = 9 * 60
    @State private var outM = 18 * 60
    @State private var error: String?
    @State private var search = ""
    /// 勤務する店舗（掛け持ちの人だけ選べる）
    @State private var workStore: String?
    /// 時刻の刻み（タイムラインと同じ設定）
    @AppStorage("timelineStep") private var stepMinutes = 30
    /// メモ（開いたときの内容を入れる）
    @State private var noteText = ""
    @State private var noteLoaded = false
    /// 希望休の日に勤務を入れるときの確認
    @State private var pendingEntry: CellEntry?

    private var key: CellKey { CellKey(staffID: member.id, day: day) }

    var body: some View {
        let book = store.book
        let current = Schedule.resolve(member, on: day, in: book)
        let q = search.trimmingCharacters(in: .whitespaces)
        let match: (TimeBlock) -> Bool = { b in q.isEmpty || b.label.contains(q) || b.short.contains(q) }
        let personal = member.timeBlocks.filter(match)
        let common = book.templates.filter { !$0.isOff && match($0) }
        let off = book.templates.filter(\.isOff)
        let selectedID = current?.isAuto == false ? current?.blockID : nil
        let firstID = personal.first?.id ?? common.first?.id ?? off.first?.id

        let issues = LaborCheck.issues(book, members: [member], days: [day])[key] ?? []
        let fresh = book.staff.first { $0.id == member.id } ?? member

        let storeIDs = book.storeIDs(of: fresh)
        let chosenStore = workStore ?? (current?.isOff == false ? current?.storeID : nil) ?? store.currentStoreID

        NavigationStack {
            Form {
                if storeIDs.count > 1 && q.isEmpty {
                    Section {
                        Picker("勤務する店舗", selection: Binding(get: { chosenStore }, set: { id in
                            workStore = id
                            // 手で入れた勤務なら、そのまま店舗だけ変える
                            if let c = book.cells[key], !c.isOff {
                                var e = c
                                e.storeID = id
                                save(e)
                            }
                        })) {
                            ForEach(storeIDs, id: \.self) { id in Text(book.store(id)?.name ?? id).tag(id) }
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text("勤務する店舗")
                    } footer: {
                        if let c = current, !c.isOff, c.storeID != store.currentStoreID {
                            Text("この日は\(book.store(c.storeID)?.name ?? "ほかの店舗")で勤務です。1日に入れる店舗は1か所です。")
                        } else {
                            Text("ここで選んだ店舗で、下の時間を入れます。")
                        }
                    }
                }
                if !issues.isEmpty {
                    Section {
                        ForEach(issues, id: \.self) { i in
                            Label(i.text, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(i == .requestedOff ? Color.purple : Color.orange)
                        }
                    }
                }
                if q.isEmpty {
                    Section {
                        TextField("引き継ぎ・注意点など", text: $noteText, axis: .vertical).lineLimit(1...4)
                        if noteText != (current?.note ?? "") {
                            Button("メモを保存") { saveNote(current) }
                                .disabled(current == nil)
                        }
                    } header: {
                        Label("メモ", systemImage: "note.text")
                    } footer: {
                        if current == nil {
                            Text("勤務か休みを入れた日にメモを付けられます。")
                        } else if current?.isAuto == true {
                            Text("パターンで自動で入った日にメモを付けると、この日は手入力の扱いになります（内容は同じです）。")
                        }
                    }
                    Section {
                        Toggle(isOn: Binding(get: { fresh.requestsOff(day) }, set: { on in
                            var set = Set(fresh.offRequests.compactMap { DayKey($0) })
                            if on { set.insert(day) } else { set.remove(day) }
                            do { try store.setOffRequests(set, for: member.id) } catch { self.error = error.localizedDescription }
                        })) {
                            Label("希望休", systemImage: "calendar.badge.minus")
                        }
                        .tint(.purple)
                    }
                }
                if !personal.isEmpty {
                    Section("\(member.name)の個人の時間") { blockGrid(personal, selectedID, firstID: firstID) }
                }
                if !common.isEmpty {
                    Section("共通の時間") { blockGrid(common, selectedID, firstID: firstID) }
                }
                if q.isEmpty {
                    Section("休日") { blockGrid(off, selectedID, firstID: firstID) }
                } else if personal.isEmpty && common.isEmpty {
                    Text("「\(q)」に合う時間がありません").foregroundStyle(.secondary)
                }

                if q.isEmpty {
                Section {
                    Picker("出勤", selection: $inM) {
                        ForEach(Array(stride(from: 0, to: 1440, by: stepMinutes)), id: \.self) { m in
                            Text(ClockTime.format(m)).tag(m)
                        }
                    }
                    Picker("退勤", selection: $outM) {
                        ForEach(Array(stride(from: 0, through: 1440, by: stepMinutes)), id: \.self) { m in
                            Text(ClockTime.format(m) + (m <= inM ? "（翌日）" : "")).tag(m)
                        }
                    }
                    LabeledContent("勤務時間", value: String(format: "%.1f 時間", ClockTime.hours(from: inM, to: outM)))
                    Button("この時刻にする") {
                        apply(CellEntry(inTime: ClockTime.format(inM), outTime: ClockTime.format(outM % 1440), blockID: nil, isOff: false))
                    }
                } header: {
                    Text("この日だけ時刻を直接入力")
                }

                }

                Section {
                    Button("クリア（パターンの自動入力に戻す）", role: .destructive) { apply(nil) }
                        .disabled(current?.isAuto != false)
                } footer: {
                    Text("この日だけ入れた内容を消して、週間パターン・期間限定パターンで決まる内容に戻します。")
                }
            }
            .coachOverlay(.sheet)
            .onAppear { CoachCenter.shared.show(.cellPicker("cellFirst"), after: 0.6) }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "時間を検索")
            .navigationTitle("\(day.month)月\(day.day)日（\(["日", "月", "火", "水", "木", "金", "土"][day.weekday])）\(member.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
            }
            .onAppear {
                if !noteLoaded { noteText = current?.note ?? ""; noteLoaded = true }
                if let span = TimelineMath.span(of: current) {
                    inM = span.inM
                    outM = span.outM % 1440 == 0 && span.outM > 0 ? 1440 : span.outM % 1440
                }
            }
            .confirmationDialog("希望休の日です", isPresented: Binding(get: { pendingEntry != nil }, set: { if !$0 { pendingEntry = nil } }),
                                titleVisibility: .visible) {
                Button("勤務を入れる") {
                    if let e = pendingEntry { apply(e, confirmed: true) }
                }
                Button("やめる", role: .cancel) {}
            } message: {
                Text("\(member.name)さんはこの日に希望休を出しています。勤務を入れますか？")
            }
            .alert("保存できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    /// firstID：説明（コーチマーク）で明るく残す、いちばん上のひな形
    private func blockGrid(_ blocks: [TimeBlock], _ selectedID: String?, firstID: String?) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
            ForEach(blocks) { b in
                blockButton(b, selected: selectedID == b.id)
                    .modifier(OptionalCoachTarget(id: b.id == firstID ? "cellFirst" : nil))
            }
        }
        .padding(.vertical, 4)
    }

    private func blockButton(_ b: TimeBlock, selected: Bool) -> some View {
        Button {
            apply(b.isOff
                  ? CellEntry(inTime: "", outTime: "", blockID: b.id, isOff: true)
                  : CellEntry(inTime: b.inTime, outTime: b.outTime, blockID: b.id, isOff: false))
        } label: {
            VStack(spacing: 2) {
                Text(b.short.isEmpty ? b.label : b.short).appFont(.headline)
                Text(b.isOff ? b.label : "\(b.inTime)〜\(b.outTime)")
                    .appFont(.caption2).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(PaletteColor.fg(b.colorIndex))
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(PaletteColor.bg(b.colorIndex), in: RoundedRectangle(cornerRadius: DS.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: DS.controlRadius).strokeBorder(PaletteColor.fg(b.colorIndex), lineWidth: selected ? 2.5 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(b.isOff ? b.label : "\(b.label)、\(b.inTime)から\(b.outTime)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func apply(_ entry: CellEntry?, confirmed: Bool = false) {
        // 希望休の日に勤務を入れるときは確かめる
        if !confirmed, let w = entry, !w.isOff,
           (store.book.staff.first { $0.id == member.id } ?? member).requestsOff(day) {
            pendingEntry = w
            return
        }
        var e = entry
        if e?.isOff == false, let ws = workStore ?? currentWorkStore { e?.storeID = ws }
        if save(e) { dismiss() }
    }

    /// 開いたときの勤務の店舗（ほかの店舗で勤務する日なら、その店舗のまま時間を変える）
    private var currentWorkStore: String? {
        guard let r = Schedule.resolve(member, on: day, in: store.book), !r.isOff else { return nil }
        return r.storeID
    }

    /// メモだけを保存する（パターンで決まった日は、その内容のまま手入力にしてメモを付ける）
    private func saveNote(_ current: ResolvedShift?) {
        let text = String(noteText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        if var cell = store.book.cells[key] {
            cell.note = text   // 空ならメモを消す
            save(cell)
        } else if let r = current, !text.isEmpty {
            save(CellEntry(inTime: r.inTime, outTime: r.outTime, blockID: r.blockID, isOff: r.isOff,
                           storeID: r.isOff ? nil : r.storeID, note: text))
        }
        noteText = text
    }

    @discardableResult
    private func save(_ entry: CellEntry?) -> Bool {
        do {
            try store.setCell(key, to: entry)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}
