import SwiftUI
import Charts

// MARK: - 色（表・タイムライン・分析で共通）

enum StaffingStyle {
    static let short = Color.red
    static let ok = Color.green
    static let over = Color.orange

    /// 実際の人数と必要人数から色（必要人数が無ければ nil）
    static func color(_ n: Int, need: Int?) -> Color? {
        guard let need else { return nil }
        return n < need ? short : n > need ? over : ok
    }
}

// MARK: - 設定：部門ごとの時間帯と必要人数

struct StaffingSettingsView: View {
    @Environment(\.shiftStore) private var store
    @State private var editing: StaffingBand?
    @State private var isNew = false
    @State private var error: String?
    @State private var suggestFor: Department?

    var body: some View {
        let plan = store.book.staffing
        let depts = store.book.scopedDepartments
        List {
            Section {
                Text("部門ごとに「この時間帯は何人いてほしいか」を、平日・土曜・日祝で決めます。表の「時間帯別在籍人数」とタイムラインで、足りない時間が赤、多すぎる時間がオレンジになります。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(depts) { d in
                Section {
                    ForEach(plan.bands(for: d.id)) { b in
                        Button { isNew = false; editing = b } label: { bandRow(b) }
                            .foregroundStyle(.primary)
                    }
                    .onDelete { idx in
                        let list = plan.bands(for: d.id)
                        var p = plan
                        let ids = Set(idx.map { list[$0].id })
                        p.bands.removeAll { ids.contains($0.id) }
                        save(p)
                    }
                    Button {
                        isNew = true
                        let last = plan.bands(for: d.id).last
                        let start = last?.endHour ?? 9
                        editing = StaffingBand(departmentID: d.id, startHour: start, endHour: (start + 3) % 24,
                                               weekday: last?.weekday ?? 1, saturday: last?.saturday ?? 1, holiday: last?.holiday ?? 1)
                    } label: { Label("時間帯を追加", systemImage: "plus") }
                    Button { suggestFor = d } label: { Label("これまでのシフトから提案", systemImage: "wand.and.stars") }
                } header: {
                    HStack {
                        Circle().fill(PaletteColor.fg(d.colorIndex)).frame(width: 10, height: 10)
                        Text(d.name)
                    }
                }
            }
        }
        .navigationTitle("適正人員")
        .shiftSheet(item: $editing) { b in
            NavigationStack {
                StaffingBandEditView(band: b, isNew: isNew) { saved in
                    var p = store.book.staffing
                    if let i = p.bands.firstIndex(where: { $0.id == saved.id }) { p.bands[i] = saved } else { p.bands.append(saved) }
                    save(p)
                } onDelete: {
                    var p = store.book.staffing
                    p.bands.removeAll { $0.id == b.id }
                    save(p)
                }
            }
            .presentationDetents([.large])
        }
        .confirmationDialog("これまでのシフトから提案しますか？", isPresented: Binding(get: { suggestFor != nil }, set: { if !$0 { suggestFor = nil } }),
                            titleVisibility: .visible) {
            Button("提案で置き換える") { if let d = suggestFor { suggest(d) } }
            Button("やめる", role: .cancel) { suggestFor = nil }
        } message: {
            Text("今日までの8週間に、平日・土曜・日祝それぞれ平均で何人いたかを時間ごとに数え、時間帯を作ります。この部門の今の時間帯は置き換わります。あとから直せます。")
        }
        .errorAlert($error)
    }

    private func bandRow(_ b: StaffingBand) -> some View {
        HStack {
            Text(b.timeText).font(.body.weight(.semibold)).monospacedDigit()
            Spacer()
            HStack(spacing: 10) {
                ForEach([DayType.weekday, .saturday, .holiday], id: \.self) { t in
                    VStack(spacing: 0) {
                        Text(t.title).font(.caption2).foregroundStyle(.secondary)
                        Text("\(b.need(t))人").font(.subheadline.weight(.bold)).monospacedDigit()
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func save(_ p: StaffingPlan) {
        do { try store.setStaffing(p) } catch { self.error = "保存できませんでした（\(error.localizedDescription)）" }
    }

    private func suggest(_ d: Department) {
        suggestFor = nil
        let book = store.book
        let today = store.today
        let days = (1...56).map { today.adding(days: -$0) }
        let members = book.staff.filter { $0.departmentID == d.id }
        let table = ScheduleTable(book: book, members: members, days: days)
        let avg = StaffingCheck.averages(department: members, days: days, plan: book.staffing) { table.working($0, on: $1, hour: $2) }
        let bands = StaffingCheck.suggestBands(department: d.id, averages: avg)
        if bands.isEmpty { error = "この8週間に \(d.name) のシフトが無いため、提案できませんでした。"; return }
        var p = book.staffing
        p.bands.removeAll { $0.departmentID == d.id }
        p.bands += bands
        save(p)
    }
}

struct StaffingBandEditView: View {
    @State var band: StaffingBand
    let isNew: Bool
    let onSave: (StaffingBand) -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("時間帯") {
                Picker("はじめ", selection: $band.startHour) {
                    ForEach(0..<24, id: \.self) { Text("\($0):00").tag($0) }
                }
                Picker("おわり", selection: $band.endHour) {
                    ForEach(0..<24, id: \.self) { h in Text((h <= band.startHour ? "翌" : "") + "\(h):00").tag(h) }
                }
                if band.startHour == band.endHour {
                    Text("はじめとおわりが同じときは24時間になります").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                stepper("平日", value: $band.weekday)
                stepper("土曜", value: $band.saturday)
                stepper("日曜・祝日", value: $band.holiday)
            } header: {
                Text("必要な人数")
            } footer: {
                Text("夜中〜朝（0時〜8時台）は、表と同じく「その日の夜から翌朝」の人数とくらべます。")
            }
            Section {
                optionalStepper("繁忙日", value: $band.busy, auto: band.need(.busy), autoText: "いちばん多い日 +1")
                optionalStepper("閑散日", value: $band.quiet, auto: band.need(.quiet), autoText: "平日 −1")
            } footer: {
                Text("繁忙日・閑散日は、分析の画面で日ごとに切り替えます（例：連休前・団体の日を繁忙に）。")
            }
            if !isNew {
                Section {
                    Button("この時間帯を消す", role: .destructive) { onDelete(); dismiss() }
                }
            }
        }
        .navigationTitle(isNew ? "時間帯を追加" : "時間帯")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("やめる") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("保存") { onSave(band); dismiss() }.bold() }
        }
    }

    private func stepper(_ title: String, value: Binding<Int>) -> some View {
        Stepper(value: value, in: 0...50) {
            LabeledContent(title, value: "\(value.wrappedValue)人").monospacedDigit()
        }
    }

    @ViewBuilder
    private func optionalStepper(_ title: String, value: Binding<Int?>, auto: Int, autoText: String) -> some View {
        Toggle(isOn: Binding(get: { value.wrappedValue != nil }, set: { value.wrappedValue = $0 ? auto : nil })) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(title)の人数を決める")
                if value.wrappedValue == nil {
                    Text("決めないときは \(autoText)（今は\(auto)人）").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        if value.wrappedValue != nil {
            stepper(title, value: Binding(get: { value.wrappedValue ?? auto }, set: { value.wrappedValue = $0 }))
        }
    }
}

// MARK: - 分析：月の不足・過剰

struct StaffingAnalysisView: View {
    let month: MonthKey
    @Environment(\.shiftStore) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var departmentID: String = ""
    @State private var error: String?

    /// 表の並び（9時〜翌8時）
    private let hours = [9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 0, 1, 2, 3, 4, 5, 6, 7, 8]

    private struct Cell: Identifiable {
        let day: DayKey
        let hour: Int
        let n: Int
        let need: Int
        var id: String { "\(day)-\(hour)" }
        var diff: Int { n - need }
    }

    private struct DayRow: Identifiable {
        let day: DayKey
        let gap: StaffingGap
        var id: DayKey { day }
    }

    var body: some View {
        let book = store.book
        let plan = book.staffing
        let groups = book.staffByDepartment(visibleIn: month).filter { plan.hasPlan(for: $0.department.id) }
        if plan.isEmpty || groups.isEmpty {
            ContentUnavailableView {
                Label("適正人員がまだ決まっていません", systemImage: "person.3")
            } description: {
                Text("部門ごとに、時間帯と必要な人数を決めると、足りない日・時間がここに出ます。")
            } actions: {
                NavigationLink("適正人員を決める") { StaffingSettingsView() }.buttonStyle(.borderedProminent)
            }
        } else {
            let g = groups.first { $0.department.id == departmentID } ?? groups[0]
            let days = month.days
            let table = ScheduleTable(book: book, members: g.members, days: days)
            let cells = days.flatMap { d in
                hours.compactMap { h -> Cell? in
                    guard let need = plan.need(g.department.id, on: d, hour: h) else { return nil }
                    return Cell(day: d, hour: h, n: table.working(g.members, on: d, hour: h), need: need)
                }
            }
            let rows = days.map { d in
                DayRow(day: d, gap: StaffingCheck.gap(plan, department: g.department.id, members: g.members, on: d) {
                    table.working($0, on: $1, hour: $2)
                })
            }
            let total = rows.reduce(StaffingGap()) { $0 + $1.gap }
            let shortDays = rows.filter { $0.gap.short > 0 }.count

            List {
                if groups.count > 1 {
                    Picker("部門", selection: Binding(get: { g.department.id }, set: { departmentID = $0 })) {
                        ForEach(groups) { Text($0.department.name).tag($0.department.id) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }
                Section {
                    HStack(spacing: 0) {
                        stat("足りない日", "\(shortDays)日", shortDays > 0 ? StaffingStyle.short : .secondary)
                        Divider()
                        stat("足りない人×時間", "\(total.short)", total.short > 0 ? StaffingStyle.short : .secondary)
                        Divider()
                        stat("多い人×時間", "\(total.over)", total.over > 0 ? StaffingStyle.over : .secondary)
                    }
                    .frame(height: 64)
                }
                Section {
                    heatmap(cells, days: days)
                        .padding(.vertical, 6)
                } header: {
                    Text("日×時間（実際 − 必要）")
                } footer: {
                    legend
                }
                Section("日ごとの不足・過剰（人×時間）") {
                    dailyChart(rows).frame(height: 180).padding(.vertical, 6)
                }
                Section {
                    ForEach(rows) { r in dayRow(r, plan: plan) }
                } header: {
                    Text("日ごと")
                } footer: {
                    Text("日の型を押すと、繁忙・閑散に切り替えられます。必要人数が型ごとに変わります。")
                }
            }
            .errorAlert($error)
        }
    }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.weight(.bold)).monospacedDigit().foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func label(_ h: Int) -> String { (h <= 8 ? "明" : "") + "\(h)時" }

    private func cellColor(_ c: Cell) -> Color {
        if c.diff < 0 { return StaffingStyle.short.opacity(min(1, 0.35 + Double(-c.diff) * 0.25)) }
        if c.diff > 0 { return StaffingStyle.over.opacity(min(0.9, 0.25 + Double(c.diff) * 0.2)) }
        return StaffingStyle.ok.opacity(0.35)
    }

    /// 日×時間の色の表（グラフ部品だと細い線になってしまうため、四角を並べて描く）
    /// 必要人数を決めている時間だけ行にする
    private func heatmap(_ cells: [Cell], days: [DayKey]) -> some View {
        let byKey = Dictionary(cells.map { ("\($0.day)-\($0.hour)", $0) }, uniquingKeysWith: { a, _ in a })
        let rowHours = hours.filter { h in cells.contains { $0.hour == h } }
        let labelWidth: CGFloat = 40, rowHeight: CGFloat = 18
        return GeometryReader { geo in
            let w = max(4, (geo.size.width - labelWidth) / CGFloat(days.count))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rowHours, id: \.self) { h in
                    HStack(spacing: 0) {
                        Text(label(h)).font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                            .frame(width: labelWidth, alignment: .leading)
                        ForEach(days, id: \.self) { d in
                            let c = byKey["\(d)-\(h)"]
                            Rectangle()
                                .fill(c.map(cellColor) ?? Color(.secondarySystemBackground))
                                .overlay {
                                    if let c, c.diff != 0, w >= 22 {
                                        Text(c.diff > 0 ? "+\(c.diff)" : "\(c.diff)")
                                            .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                    }
                                }
                                .frame(width: w, height: rowHeight)
                                .overlay(alignment: .trailing) { Rectangle().fill(Color(.systemBackground)).frame(width: 1) }
                        }
                    }
                    .overlay(alignment: .bottom) { Rectangle().fill(Color(.systemBackground)).frame(height: 1) }
                }
                HStack(spacing: 0) {
                    Color.clear.frame(width: labelWidth, height: 16)
                    ForEach(days, id: \.self) { d in
                        Text(d.day == 1 || d.day % 5 == 0 ? "\(d.day)" : "")
                            .font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                            .fixedSize()
                            .frame(width: w, height: 16)
                    }
                }
            }
        }
        .frame(height: CGFloat(rowHours.count) * rowHeight + 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("日と時間ごとの不足と過剰")
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem(StaffingStyle.short, "足りない")
            legendItem(StaffingStyle.ok.opacity(0.35), "ちょうど")
            legendItem(StaffingStyle.over, "多い")
            Text("空白は必要人数を決めていない時間").foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private func legendItem(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 12, height: 12); Text(t) }
    }

    private func dailyChart(_ rows: [DayRow]) -> some View {
        Chart {
            ForEach(rows) { r in
                BarMark(x: .value("日", "\(r.day.day)"), y: .value("人×時間", -r.gap.short))
                    .foregroundStyle(StaffingStyle.short)
                BarMark(x: .value("日", "\(r.day.day)"), y: .value("人×時間", r.gap.over))
                    .foregroundStyle(StaffingStyle.over)
            }
            RuleMark(y: .value("0", 0)).foregroundStyle(.secondary)
        }
        .chartXScale(domain: rows.map { "\($0.day.day)" })
        .chartXAxis {
            AxisMarks(values: rows.map(\.day).filter { $0.day == 1 || $0.day % 5 == 0 }.map { "\($0.day)" }) { v in
                AxisGridLine()
                // 1日分の幅が狭い iPhone でも「…」にならないように
                AxisValueLabel(collisionResolution: .disabled) { Text(v.as(String.self) ?? "").fixedSize() }
            }
        }
        .chartYAxis {
            AxisMarks { v in
                AxisGridLine()
                AxisValueLabel { if let i = v.as(Int.self) { Text("\(abs(i))") } }
            }
        }
        .accessibilityLabel("日ごとの不足（下）と過剰（上）")
    }

    private func dayRow(_ r: DayRow, plan: StaffingPlan) -> some View {
        let d = r.day
        let t = plan.type(of: d)
        let wd = ["日", "月", "火", "水", "木", "金", "土"][d.weekday]
        return HStack(spacing: 10) {
            Text("\(d.month)/\(d.day)（\(wd)）").monospacedDigit()
                .foregroundStyle(d.weekday == 0 || JapaneseHolidays.isHoliday(d) ? .red : d.weekday == 6 ? .blue : .primary)
                .frame(width: 92, alignment: .leading)
            Menu {
                ForEach(DayType.allCases) { x in
                    Button {
                        var p = store.book.staffing
                        p.setType(x, for: d)
                        do { try store.setStaffing(p) } catch { self.error = error.localizedDescription }
                    } label: {
                        if x == t { Label(x.title + (x == DayType.calendar(d) ? "（カレンダーどおり）" : ""), systemImage: "checkmark") }
                        else { Text(x.title + (x == DayType.calendar(d) ? "（カレンダーどおり）" : "")) }
                    }
                }
            } label: {
                Text(t.title).font(.caption.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(typeColor(t).opacity(0.15), in: Capsule())
                    .foregroundStyle(typeColor(t))
            }
            Spacer()
            if r.gap.short > 0 {
                Text("不足 \(r.gap.shortHours)時間・\(r.gap.short)人時").font(.caption.weight(.bold)).foregroundStyle(StaffingStyle.short)
            } else {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(StaffingStyle.ok).accessibilityLabel("足りている")
            }
            if r.gap.over > 0 {
                Text("多い \(r.gap.over)").font(.caption).foregroundStyle(StaffingStyle.over)
            }
        }
        .monospacedDigit()
    }

    private func typeColor(_ t: DayType) -> Color {
        switch t {
        case .busy: .red
        case .quiet: .brown
        case .holiday: .pink
        case .saturday: .blue
        case .weekday: .gray
        }
    }
}
