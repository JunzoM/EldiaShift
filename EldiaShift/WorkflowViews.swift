import SwiftUI

// MARK: - 元に戻す・やり直す（表の上と、タイムラインの上に置く）

struct UndoRedoButtons: View {
    @Environment(ShiftStore.self) private var store
    @State private var error: String?

    var body: some View {
        HStack(spacing: 2) {
            Button {
                do { try store.undo() } catch { self.error = error.localizedDescription }
            } label: { Image(systemName: "arrow.uturn.backward").frame(minWidth: 36, minHeight: 32) }
                .disabled(!store.canUndo)
                .keyboardShortcut("z", modifiers: .command)
                .accessibilityLabel("元に戻す")
                .accessibilityHint(store.undoStack.last?.title ?? "")
            Button {
                do { try store.redo() } catch { self.error = error.localizedDescription }
            } label: { Image(systemName: "arrow.uturn.forward").frame(minWidth: 36, minHeight: 32) }
                .disabled(!store.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .accessibilityLabel("やり直す")
                .accessibilityHint(store.redoStack.last?.title ?? "")
        }
        .errorAlert($error)
    }
}

// MARK: - 足りない時間に入れられる人

struct ShortageTarget: Identifiable {
    let department: Department
    let day: DayKey
    var id: String { "\(department.id)-\(day)" }
}

struct CandidatesSheet: View {
    let target: ShortageTarget
    @Environment(ShiftStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var includeOthers = false
    @State private var error: String?

    var body: some View {
        let book = store.book
        let d = target.day
        let dept = target.department
        let members = book.staffByDepartment(visibleIn: MonthKey(d)).flatMap(\.members).filter { $0.departmentID == dept.id }
        let short = ShortageFinder.shortHours(book, department: dept.id, members: members, on: d)
        let list = ShortageFinder.candidates(book, department: dept.id, on: d, includeOthers: includeOthers)

        NavigationStack {
            List {
                Section {
                    if short.isEmpty {
                        Label("必要な人数がそろいました", systemImage: "checkmark.circle.fill").foregroundStyle(StaffingStyle.ok)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(short, id: \.self) { h in
                                    let n = Headcount.working(members, on: d, hour: h, in: book)
                                    let need = book.staffing.need(dept.id, on: d, hour: h) ?? 0
                                    VStack(spacing: 1) {
                                        Text("\(h)時").font(.caption2)
                                        Text("\(n)/\(need)").font(.caption.weight(.heavy)).monospacedDigit()
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(StaffingStyle.short, in: RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                    }
                } header: {
                    Text("足りない時間（実際/必要）")
                }

                if !short.isEmpty {
                    Section {
                        Toggle("ほかの部門の人も出す", isOn: $includeOthers)
                        if list.isEmpty {
                            Text("この日に入れられる人がいません（全員が勤務・有休・希望休・退職後のいずれかです）")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        ForEach(list) { c in row(c) }
                    } header: {
                        Text("入れられる人")
                    } footer: {
                        Text("この日に勤務が無い人を、注意（連勤・勤務の間隔など）が出ない人 → 足りない時間をたくさん埋める人 → 今月の時間が少ない人 の順に並べています。")
                    }
                }
            }
            .navigationTitle("\(d.month)/\(d.day) \(dept.name)の不足")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
            .errorAlert($error)
        }
    }

    private func row(_ c: ShortageCandidate) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(c.member.name).font(.headline)
                    if c.otherDepartment, let d = store.book.departments.first(where: { $0.id == c.member.departmentID }) {
                        Text(d.name).font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(PaletteColor.bg(d.colorIndex), in: Capsule())
                            .foregroundStyle(PaletteColor.fg(d.colorIndex))
                    }
                }
                HStack(spacing: 6) {
                    Text("\(c.block.label) \(c.block.inTime)〜\(c.block.outTime)")
                        .font(.caption.weight(.bold)).foregroundStyle(PaletteColor.fg(c.block.colorIndex))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(PaletteColor.bg(c.block.colorIndex), in: RoundedRectangle(cornerRadius: 4))
                    Text("不足を \(c.covers)時間 埋める").font(.caption).foregroundStyle(.secondary)
                }
                Text(String(format: "今月 %.1f時間", c.monthHours)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                if !c.issues.isEmpty {
                    Label(c.issues.map(\.text).joined(separator: "・"), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
            Button("入れる") { assign(c) }
                .buttonStyle(.borderedProminent)
                .tint(c.issues.isEmpty ? .accentColor : .orange)
        }
        .padding(.vertical, 2)
    }

    private func assign(_ c: ShortageCandidate) {
        do {
            let key = CellKey(staffID: c.member.id, day: target.day)
            try store.setCells([(key, c.entry)], title: "\(c.member.name) \(target.day.month)/\(target.day.day) に\(c.block.label)を入れました")
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - 希望休

/// 希望休を入れる：スタッフを選び、LINE などの文章を貼ると日付を読み取る
struct OffRequestSheet: View {
    let month: MonthKey
    @Environment(ShiftStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var staffID = ""
    @State private var text = ""
    @State private var picked: Set<DayKey> = []
    @AppStorage("requestAlsoOff") private var alsoOff = true
    @State private var offBlockID = "off1"
    @State private var error: String?

    var body: some View {
        let book = store.book
        let members = book.staffByDepartment(visibleIn: month).flatMap(\.members)
        let member = members.first { $0.id == staffID }
        let parsed = OffRequestParser.parse(text, month: month)
        let existing = Set((member?.offRequests ?? []).compactMap { DayKey($0) }.filter { MonthKey($0) == month })
        let offBlocks = book.templates.filter(\.isOff)

        NavigationStack {
            Form {
                Section("スタッフ") {
                    Picker("スタッフ", selection: $staffID) {
                        Text("選んでください").tag("")
                        ForEach(members) { Text($0.name).tag($0.id) }
                    }
                }
                Section {
                    TextField("例：10/5、12日、20〜22日 休み希望", text: $text, axis: .vertical)
                        .lineLimit(2...6)
                    if !parsed.isEmpty {
                        Text("読み取った日：" + parsed.map { "\($0.month)/\($0.day)" }.joined(separator: "、"))
                            .font(.caption).foregroundStyle(.secondary)
                        Button("この日を選ぶ") { picked.formUnion(parsed) }
                    }
                } header: {
                    Text("文章から読み取る（LINE などをそのまま貼れます）")
                }
                Section {
                    calendar(existing: existing)
                } header: {
                    Text("\(month.month)月の希望休（押して選ぶ・外す）")
                } footer: {
                    Text("紫の日が希望休です。希望休の日に勤務を入れると、マスに注意が出ます。")
                }
                Section {
                    Toggle("シフトも休みにする", isOn: $alsoOff)
                    if alsoOff {
                        Picker("休みの種類", selection: $offBlockID) {
                            ForEach(offBlocks) { Text($0.label).tag($0.id) }
                        }
                    }
                } footer: {
                    Text("新しく希望休にした日のシフトを、選んだ休みにします（元に戻すで戻せます）。")
                }
            }
            .navigationTitle("希望休")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("やめる") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save(member: member, existing: existing) }.bold().disabled(member == nil)
                }
            }
            .onChange(of: staffID) { picked = requests(for: staffID) }
            .onAppear {
                if offBlockID == "off1", !offBlocks.contains(where: { $0.id == "off1" }) { offBlockID = offBlocks.first?.id ?? "" }
            }
            .errorAlert($error)
        }
    }

    private func requests(for id: String) -> Set<DayKey> {
        let m = store.book.staff.first { $0.id == id }
        return Set((m?.offRequests ?? []).compactMap { DayKey($0) }.filter { MonthKey($0) == month })
    }

    private func calendar(existing: Set<DayKey>) -> some View {
        let days = month.days
        let lead = days[0].weekday
        let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return LazyVGrid(columns: cols, spacing: 4) {
            ForEach(["日", "月", "火", "水", "木", "金", "土"], id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary) }
            ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 36) }
            ForEach(days, id: \.self) { d in
                let on = picked.contains(d)
                Button {
                    if on { picked.remove(d) } else { picked.insert(d) }
                } label: {
                    Text("\(d.day)").font(.subheadline.weight(on ? .bold : .regular)).monospacedDigit()
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .foregroundStyle(on ? Color.white : (d.weekday == 0 || JapaneseHolidays.isHoliday(d) ? Color.red : d.weekday == 6 ? Color.blue : Color.primary))
                        .background(on ? Color.purple : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(staffID.isEmpty)
                .accessibilityLabel("\(d.month)月\(d.day)日\(on ? "、希望休" : "")")
            }
        }
        .padding(.vertical, 4)
    }

    private func save(member: StaffMember?, existing: Set<DayKey>) {
        guard let member else { return }
        do {
            // ほかの月の希望休は残す
            let others = Set(member.offRequests.compactMap { DayKey($0) }.filter { MonthKey($0) != month })
            try store.setOffRequests(others.union(picked), for: member.id)
            let added = picked.subtracting(existing).sorted()
            if alsoOff, !added.isEmpty, !offBlockID.isEmpty {
                try store.setCells(added.map { (CellKey(staffID: member.id, day: $0),
                                                CellEntry(inTime: "", outTime: "", blockID: offBlockID, isOff: true)) },
                                   title: "\(member.name) の希望休 \(added.count)日を休みにしました")
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - 労務の注意（集計の「注意」）

struct LaborIssuesView: View {
    let month: MonthKey
    @Environment(ShiftStore.self) private var store

    private struct LeaveRow: Identifiable {
        let member: StaffMember
        let o: LaborCheck.LeaveObligation
        var id: String { member.id }
    }

    private struct DayIssues: Identifiable {
        let day: DayKey
        let items: [LaborIssue]
        var id: DayKey { day }
    }

    private struct MemberIssues: Identifiable {
        let member: StaffMember
        let days: [DayIssues]
        var id: String { member.id }
    }

    var body: some View {
        let book = store.book
        let members = book.staffByDepartment(visibleIn: month).flatMap(\.members)
        let issues = LaborCheck.issues(book, members: members, days: month.days)
        let today = store.today
        let leave = members.compactMap { m in LaborCheck.leaveObligation(of: m, in: book, today: today).map { LeaveRow(member: m, o: $0) } }
            .filter { $0.o.needed > 0 }
            .sorted { $0.o.deadline < $1.o.deadline }
        let byMember = members.compactMap { m -> MemberIssues? in
            let list = issues.filter { $0.key.staffID == m.id }.map { DayIssues(day: $0.key.day, items: $0.value) }.sorted { $0.day < $1.day }
            return list.isEmpty ? nil : MemberIssues(member: m, days: list)
        }

        if leave.isEmpty && byMember.isEmpty {
            ContentUnavailableView {
                Label("注意はありません", systemImage: "checkmark.seal")
            } description: {
                Text("連勤・勤務の間隔・週の時間・希望休・有休の年5日を確かめています。")
            } actions: {
                NavigationLink("注意の決まりを変える") { LaborRulesView() }
            }
        } else {
            List {
                if !leave.isEmpty {
                    Section {
                        ForEach(leave) { item in
                            let m = item.member, o = item.o
                            let left = o.daysLeft(from: today)
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.name).font(.headline)
                                    Text("期限 \(o.deadline.year)/\(o.deadline.month)/\(o.deadline.day)（あと\(left)日）")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("取得 \(o.taken)/5日").font(.subheadline.weight(.bold)).monospacedDigit()
                                    .foregroundStyle(left < 90 ? Color.red : Color.orange)
                            }
                        }
                    } header: {
                        Text("有休を年5日取らせる義務")
                    } footer: {
                        Text("年10日以上の有休が付与された人は、付与日から1年以内に5日取らせる必要があります（労働基準法39条7項）。予定として入れた「有休」も数えています。")
                    }
                }
                ForEach(byMember) { group in
                    Section(group.member.name) {
                        ForEach(group.days) { entry in
                            let d = entry.day, items = entry.items
                            HStack(alignment: .firstTextBaseline) {
                                Text("\(d.month)/\(d.day)（\(["日", "月", "火", "水", "木", "金", "土"][d.weekday])）")
                                    .monospacedDigit().frame(width: 80, alignment: .leading)
                                Text(items.map(\.text).joined(separator: "・"))
                                    .font(.subheadline)
                                    .foregroundStyle(items.contains(.requestedOff) ? Color.purple : Color.orange)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct LaborRulesView: View {
    @Environment(ShiftStore.self) private var store
    @State private var rules = LaborRules()
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Toggle("連勤", isOn: $rules.consecutiveEnabled)
                if rules.consecutiveEnabled {
                    Stepper("\(rules.consecutiveDays)日以上続いたら", value: $rules.consecutiveDays, in: 2...14)
                }
            } footer: {
                Text("法律では週1日（または4週4日）の休日が必要です。")
            }
            Section {
                Toggle("勤務と勤務の間隔", isOn: $rules.intervalEnabled)
                if rules.intervalEnabled {
                    Stepper("\(rules.intervalHours)時間より短いと", value: $rules.intervalHours, in: 6...16)
                }
            } footer: {
                Text("勤務間インターバル（努力義務）。夜勤明けの次の日の早番などに注意が出ます。")
            }
            Section {
                Toggle("週の実働", isOn: $rules.weeklyEnabled)
                if rules.weeklyEnabled {
                    Stepper("\(rules.weeklyHours)時間を超えたら", value: $rules.weeklyHours, in: 20...60)
                }
                Toggle("1日の実働", isOn: $rules.dailyEnabled)
                if rules.dailyEnabled {
                    Stepper("\(rules.dailyHours)時間を超えたら", value: $rules.dailyHours, in: 4...16)
                }
            } footer: {
                Text("週は月曜はじまり。変形労働時間制の場合は、会社の決まりに合わせて切り替えてください。")
            }
            Section {
                Toggle("有休を年5日取らせる義務", isOn: $rules.leaveObligationEnabled)
            }
        }
        .navigationTitle("労務の注意")
        .onAppear {
            if !loaded { rules = store.book.labor; loaded = true }
        }
        .onChange(of: rules) {
            guard loaded, rules != store.book.labor else { return }
            do { try store.setLaborRules(rules) } catch { self.error = error.localizedDescription }
        }
        .errorAlert($error)
    }
}

// MARK: - 一人ずつのシフト画像（LINE で本人に送る用）

struct PersonalScheduleImage: View {
    let member: StaffMember
    let month: MonthKey
    let book: ShiftBook
    let title: String

    static let width: CGFloat = 390

    var body: some View {
        let days = month.days
        let s = MonthSummary.of(member, month: month, in: book)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                if !title.isEmpty { Text(title).font(.system(size: 12)).foregroundStyle(.secondary) }
                Text("\(member.name)さん　\(month.year)年\(month.month)月のシフト").font(.system(size: 18, weight: .bold))
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 10)
            ForEach(days, id: \.self) { d in
                let r = Schedule.resolve(member, on: d, in: book)
                let block = book.block(r?.blockID, for: member)
                let wd = ["日", "月", "火", "水", "木", "金", "土"][d.weekday]
                let holiday = d.weekday == 0 || JapaneseHolidays.isHoliday(d)
                HStack(spacing: 10) {
                    Text("\(d.day)（\(wd)）").font(.system(size: 14, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(holiday ? Color.red : d.weekday == 6 ? Color.blue : Color.black)
                        .frame(width: 64, alignment: .leading)
                    if let r {
                        if r.isOff {
                            Text(block?.label ?? "休み").font(.system(size: 14, weight: .bold))
                                .foregroundStyle(PaletteColor.fg(block?.colorIndex ?? 8))
                        } else {
                            Text("\(r.inTime)〜\(r.outTime)").font(.system(size: 15, weight: .bold)).monospacedDigit()
                                .foregroundStyle(Color.black)
                            if let block {
                                Text(block.label).font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(PaletteColor.fg(block.colorIndex))
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(PaletteColor.bg(block.colorIndex), in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                    } else {
                        Text("—").foregroundStyle(Color.gray)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .frame(height: 28)
                .background(r?.isOff == true ? PaletteColor.bg(block?.colorIndex ?? 8).opacity(0.6)
                            : d.weekday == 0 || d.weekday == 6 ? Color(white: 0.96) : Color.white)
                .overlay(alignment: .bottom) { Rectangle().fill(Color(white: 0.88)).frame(height: 0.5) }
            }
            HStack {
                Text("出勤 \(s.workDays)日")
                Spacer()
                Text(String(format: "実働 %.1f時間", s.hours))
            }
            .font(.system(size: 14, weight: .bold)).monospacedDigit()
            .foregroundStyle(Color.black)
            .padding(16)
        }
        .frame(width: Self.width)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    /// 選んだ人たちの画像を書き出す（1人1枚の PNG）
    @MainActor
    static func files(for members: [StaffMember], month: MonthKey, book: ShiftBook, title: String,
                      progress: (Int) -> Void = { _ in }) async throws -> [URL] {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("personal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var urls: [URL] = []
        for (i, m) in members.enumerated() {
            progress(i + 1)
            await Task.yield()
            let r = ImageRenderer(content: PersonalScheduleImage(member: m, month: month, book: book, title: title))
            r.scale = 3
            guard let data = r.uiImage?.pngData() else { continue }
            let safe = m.name.replacingOccurrences(of: "/", with: "／")
            let url = dir.appendingPathComponent("\(month.month)月_\(safe).png")
            try data.write(to: url, options: .atomic)
            urls.append(url)
        }
        return urls
    }
}
