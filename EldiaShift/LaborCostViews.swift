import SwiftUI
import Charts
import LocalAuthentication

// MARK: - 人件費を隠す（端末ごと。見るときは Face ID / パスコード）

@MainActor
@Observable
final class LaborCostLock {
    static let shared = LaborCostLock()
    private static let key = "laborCostHidden"

    /// この端末で人件費・給与を隠すか
    private(set) var hidden: Bool
    /// 確認が済んで、いま見られる（アプリを離れると戻る）
    private(set) var unlocked = false

    var canView: Bool { !hidden || unlocked }

    private init() { hidden = UserDefaults.standard.bool(forKey: Self.key) }

    /// 端末にパスコードが設定されているか（無いと隠しても誰でも見られるので、隠す設定を使えない）
    var deviceCanAuthenticate: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// 本人の確認（Face ID・Touch ID・パスコード）
    func authenticate(reason: String) async -> Bool {
        let ctx = LAContext()
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return false }
        return await withCheckedContinuation { cont in
            ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in cont.resume(returning: ok) }
        }
    }

    func unlock() async {
        guard hidden, !unlocked else { return }
        if await authenticate(reason: "人件費・給与を表示します") { unlocked = true }
    }

    func lock() { unlocked = false }

    /// 隠す設定を変える（やめるときも本人の確認をする）
    func setHidden(_ on: Bool) async -> Bool {
        guard on != hidden else { return true }
        guard await authenticate(reason: on ? "人件費・給与を隠します" : "人件費・給与を隠すのをやめます") else { return false }
        hidden = on
        unlocked = false
        UserDefaults.standard.set(on, forKey: Self.key)
        return true
    }
}

/// 隠しているときの表示（押すと確認して表示）
struct LaborCostLockedView: View {
    var compact = false

    var body: some View {
        let lock = LaborCostLock.shared
        if compact {
            Button { Task { await lock.unlock() } } label: {
                Label("人件費・給与は隠しています（押して表示）", systemImage: "lock.fill")
            }
        } else {
            ContentUnavailableView {
                Label("人件費は隠しています", systemImage: "lock.fill")
            } description: {
                Text("この端末では人件費・給与を隠す設定になっています。")
            } actions: {
                Button("Face ID・パスコードで表示") { Task { await lock.unlock() } }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - 集計 → 人件費

struct LaborCostView: View {
    let month: MonthKey
    @Environment(\.shiftStore) private var store
    @Environment(\.shiftDatabase) private var db
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var csvFile: ExportFile?
    @State private var failure: String?
    @State private var editingBudget = false
    /// 年間の推移（月ごとの合計）。重いので、表示した後に出す
    @State private var yearTotals: [Int]?
    @State private var previousTotal: Int?

    var body: some View {
        if LaborCostLock.shared.canView { content } else { LaborCostLockedView() }
    }

    private struct YearID: Equatable { let month: MonthKey; let revision: Int }

    private var content: some View {
        let book = store.book
        let groups = book.staffByDepartment(visibleIn: month)
        let pays = Dictionary(groups.flatMap(\.members).map { ($0.id, Payroll.pay(of: $0, month: month, in: book, rules: book.pay)) },
                              uniquingKeysWith: { a, _ in a })
        let total = pays.values.reduce(StaffPay()) { $0 + $1 }
        let missing = groups.flatMap(\.members).filter { (pays[$0.id]?.missingWageDays ?? 0) > 0 }
        return List {
            if db.viewingSharedTeam {
                Section {
                    Label("共有されたシフト表です。給与は共有されないので、この端末で給与を入れた人の分だけを数えます。", systemImage: "lock")
                        .appFont(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(month.month)月の人件費（概算）").appFont(.subheadline).foregroundStyle(.secondary)
                    Text(Self.yen(total.total)).appFont(.number).monospacedDigit()
                    Text("時給分 \(Self.yen(total.hourlyBase))・月給分 \(Self.yen(total.monthlyBase))・時間外 \(Self.yen(total.overtimePay))・深夜 \(Self.yen(total.nightPay))")
                        .appFont(.caption).foregroundStyle(.secondary).monospacedDigit()
                    Text("実働 \(Self.hours(total.netMinutes))・時間外 \(Self.hours(total.overtimeMinutes))・深夜 \(Self.hours(total.nightMinutes))")
                        .appFont(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                .padding(.vertical, 4)
                if !missing.isEmpty {
                    Label("給与が未設定の人がいます：\(missing.map(\.name).joined(separator: "、"))。スタッフを開いて「給与」に入れると合計に入ります。",
                          systemImage: "exclamationmark.triangle.fill")
                        .appFont(.footnote).foregroundStyle(.orange)
                }
            }

            budgetSection(total.total, book: book)

            ForEach(groups) { g in
                Section {
                    ForEach(g.members) { m in row(m, pays[m.id] ?? StaffPay()) }
                } header: {
                    HStack {
                        let cost = g.members.reduce(StaffPay()) { $0 + (pays[$1.id] ?? StaffPay()) }.total
                        Text(g.department.name).foregroundStyle(PaletteColor.fg(g.department.colorIndex))
                        Spacer()
                        if total.total > 0 {
                            Text("\(Self.percent(Double(cost) / Double(total.total) * 100))").foregroundStyle(.secondary).monospacedDigit()
                        }
                        Text(Self.yen(cost)).monospacedDigit()
                    }
                }
            }

            yearSection

            Section {
                Text("シフトから出した目安です（給与計算ではありません）。時間外は1日\(book.pay.dailyEnabled ? "\(book.pay.dailyHours)時間" : "—")・週\(book.pay.weeklyEnabled ? "\(book.pay.weeklyHours)時間" : "—")を超えた分に\(book.pay.overtimeRate)%、深夜（22時〜5時）に\(book.pay.nightRate)%を足しています。月給は在籍した日数で日割りし、時間外は「月給÷\(book.pay.monthlyStandardHours)時間」の\(100 + book.pay.overtimeRate)%で数えます。法定休日・月60時間超の割増、手当・交通費・社会保険は入りません。")
                    .appFont(.footnote).foregroundStyle(.secondary)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { shareCSV(groups: groups, pays: pays) } label: { Label("人件費（1人ずつの合計）", systemImage: "person.2") }
                    Button { shareDetailCSV(groups: groups) } label: { Label("シフト明細（勤務1日ずつ）", systemImage: "list.bullet.rectangle") }
                } label: { Label("CSV", systemImage: "square.and.arrow.up") }
                    .accessibilityLabel("人件費をCSVで出力")
            }
        }
        .task(id: YearID(month: month, revision: store.revision)) {
            // 入力が続くあいだは待つ（0.3秒止まってから数える）
            try? await Task.sleep(for: .milliseconds(yearTotals == nil ? 0 : 300))
            guard !Task.isCancelled else { return }
            let book = store.book
            previousTotal = Payroll.total(month: month.adding(months: -1), in: book)
            await Task.yield()
            var totals: [Int] = []
            for m in 1...12 {
                guard !Task.isCancelled else { return }
                let key = MonthKey(month.year, m)
                totals.append(key == month ? total.total : Payroll.total(month: key, in: book))
                await Task.yield()
            }
            yearTotals = totals
        }
        .shiftSheet(isPresented: $editingBudget) { BudgetEditView(month: month) }
        .shiftSheet(item: $csvFile) { f in ShareSheet(items: [f.url]) }
        .errorAlert($failure)
    }

    @ViewBuilder
    private func row(_ m: StaffMember, _ p: StaffPay) -> some View {
        let detail = [p.hasMonthly ? "月給 \(Self.yen(p.monthlyBase))" : nil,
                      p.overtimeMinutes > 0 ? "時間外 \(Self.hours(p.overtimeMinutes))" : nil,
                      p.nightMinutes > 0 ? "深夜 \(Self.hours(p.nightMinutes))" : nil,
                      p.missingWageDays > 0 ? "給与未設定 \(p.missingWageDays)日" : nil].compactMap { $0 }
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(m.name).appFont(.body.weight(.semibold))
                    if !m.employment.isEmpty { Text(m.employment).appFont(.caption2).foregroundStyle(.secondary) }
                }
                Text("\(p.workDays)日・\(Self.hours(p.netMinutes))" + (detail.isEmpty ? "" : "・" + detail.joined(separator: "・")))
                    .appFont(.caption).foregroundStyle(p.missingWageDays > 0 ? Color.orange : Color.secondary).monospacedDigit()
                    .lineLimit(sizeClass == .compact ? 2 : 1)
            }
            Spacer()
            Text(Self.yen(p.total)).appFont(.body.weight(.bold)).monospacedDigit()
        }
    }

    @ViewBuilder
    private func budgetSection(_ cost: Int, book: ShiftBook) -> some View {
        let budget = LaborBudget.value(store: book.scopeStoreID, month: month, rules: book.pay)
        Section {
            if let budget {
                let usage = LaborBudget.usage(cost, budget: budget)
                let color: Color = (usage ?? 0) > 100 ? .red : (usage ?? 0) >= 90 ? .orange : .green
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("予算の使用率").appFont(.subheadline.weight(.semibold))
                        Spacer()
                        Text(usage.map(Self.percent) ?? "—").appFont(.title3.bold()).foregroundStyle(color).monospacedDigit()
                    }
                    ProgressView(value: min(1, Double(cost) / Double(max(1, budget))))
                        .tint(color)
                        .accessibilityLabel("予算の使用率 \(usage.map(Self.percent) ?? "—")")
                    HStack {
                        Text("予算 \(Self.yen(budget))" + (LaborBudget.isMonthOnly(store: book.scopeStoreID, month: month, rules: book.pay) ? "（この月）" : "（毎月）"))
                        Spacer()
                        Text(cost <= budget ? "残り \(Self.yen(budget - cost))" : "超過 \(Self.yen(cost - budget))")
                            .foregroundStyle(cost <= budget ? Color.secondary : Color.red)
                    }
                    .appFont(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                .padding(.vertical, 2)
            }
            if let prev = previousTotal {
                HStack {
                    Text("前の月（\(month.adding(months: -1).month)月）")
                    Spacer()
                    Text(Self.yen(prev)).monospacedDigit().foregroundStyle(.secondary)
                    Text(Self.change(cost, from: prev)).monospacedDigit().appFont(.subheadline.weight(.semibold))
                        .foregroundStyle(cost > prev ? Color.red : cost < prev ? Color.green : Color.secondary)
                }
                .appFont(.subheadline)
            }
            Button(budget == nil ? "月の予算を入れる" : "予算を変える") { editingBudget = true }
        } footer: {
            if budget == nil { Text("予算を入れると、使用率と残りを出します。店舗ごと・月ごとに決められます。") }
        }
    }

    @ViewBuilder
    private var yearSection: some View {
        Section {
            if let totals = yearTotals, totals.contains(where: { $0 > 0 }) {
                let budgetLine = LaborBudget.value(store: store.book.scopeStoreID, month: month, rules: store.book.pay)
                Chart {
                    ForEach(Array(totals.enumerated()), id: \.offset) { item in
                        BarMark(x: .value("月", "\(item.offset + 1)"), y: .value("人件費", item.element))
                            .foregroundStyle(item.offset + 1 == month.month ? Color.accentColor : Color.accentColor.opacity(0.35))
                    }
                    if let b = budgetLine, !LaborBudget.isMonthOnly(store: store.book.scopeStoreID, month: month, rules: store.book.pay) {
                        RuleMark(y: .value("予算", b)).foregroundStyle(.orange).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .chartYAxis {
                    AxisMarks { v in
                        AxisGridLine()
                        AxisValueLabel { if let n = v.as(Int.self) { Text(Self.short(n)) } }
                    }
                }
                .frame(height: 160)
                .accessibilityLabel("\(month.year)年の月ごとの人件費")
                .accessibilityValue(totals.enumerated().map { "\($0.offset + 1)月 \(Self.yen($0.element))" }.joined(separator: "、"))
                Text("年の合計 \(Self.yen(totals.reduce(0, +)))").appFont(.caption).foregroundStyle(.secondary).monospacedDigit()
            } else if yearTotals == nil {
                HStack { ProgressView(); Text("数えています…").foregroundStyle(.secondary) }
            } else {
                Text("この年のシフトはまだありません。").foregroundStyle(.secondary)
            }
        } header: {
            Text("\(String(month.year))年の推移")
        }
    }

    private func shareDetailCSV(groups: [DepartmentGroup]) {
        let rows = groups.flatMap { g in g.members.map { (member: $0, department: g.department.name) } }
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("シフト明細_\(month.year)年\(month.month)月.csv")
            try Data(Payroll.detailCSV(rows: rows, month: month, in: store.book).utf8).write(to: url, options: .atomic)
            csvFile = ExportFile(url: url)
        } catch {
            failure = "CSVを作れませんでした（\(error.localizedDescription)）"
        }
    }

    static func percent(_ v: Double) -> String { String(format: v < 10 ? "%.1f%%" : "%.0f%%", v) }
    /// 前の月からの増減（前の月が 0 なら金額）
    static func change(_ now: Int, from prev: Int) -> String {
        guard prev > 0 else { return now > 0 ? "+\(yen(now))" : "±0" }
        let r = Double(now - prev) / Double(prev) * 100
        return abs(r) < 0.05 ? "±0%" : (r > 0 ? "+" : "") + String(format: "%.1f%%", r)
    }
    /// グラフの目盛り（万円）
    static func short(_ v: Int) -> String { v >= 10_000 ? "\(v / 10_000)万" : "\(v)" }

    private func shareCSV(groups: [DepartmentGroup], pays: [String: StaffPay]) {
        let rows = groups.flatMap { g in g.members.map { (member: $0, department: g.department.name, pay: pays[$0.id] ?? StaffPay()) } }
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("人件費_\(month.year)年\(month.month)月.csv")
            try Data(Payroll.csv(rows: rows, month: month).utf8).write(to: url, options: .atomic)
            csvFile = ExportFile(url: url)
        } catch {
            failure = "CSVを作れませんでした（\(error.localizedDescription)）"
        }
    }

    static func yen(_ v: Double) -> String { yen(Int(v.rounded())) }
    static func yen(_ v: Int) -> String { "¥" + v.formatted(.number.grouping(.automatic)) }
    static func hours(_ minutes: Int) -> String { String(format: "%.1f時間", Double(minutes) / 60) }
}

// MARK: - 人件費の月予算

struct BudgetEditView: View {
    let month: MonthKey
    @Environment(\.shiftStore) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var monthOnly = false
    @State private var loaded = false
    @State private var failure: String?

    var body: some View {
        let book = store.book
        let storeName = book.scopeStoreID.flatMap { id in book.stores.first { $0.id == id }?.name }
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("¥").foregroundStyle(.secondary)
                        TextField("例：1,200,000 または 120万", text: $text)
                            .keyboardType(.numbersAndPunctuation)
                            .monospacedDigit()
                    }
                    if !text.isEmpty, LaborBudget.parse(text) == nil {
                        Text("金額を数字で入れてください。").appFont(.footnote).foregroundStyle(.red)
                    }
                    Toggle("\(month.month)月だけの予算にする", isOn: $monthOnly)
                } header: {
                    Text((storeName.map { "\($0)・" } ?? "") + "人件費の月予算")
                } footer: {
                    Text(monthOnly ? "\(month.description)だけに使います。繁忙期など、月で予算が違うときに。"
                                   : "毎月の予算です。月だけの予算を入れた月は、そちらを使います。")
                }
                if LaborBudget.value(store: book.scopeStoreID, month: month, rules: book.pay) != nil {
                    Section {
                        Button(monthOnly ? "\(month.month)月だけの予算を消す" : "毎月の予算を消す", role: .destructive) { save(nil) }
                    }
                }
            }
            .navigationTitle("予算")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("やめる") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save(LaborBudget.parse(text)) }.disabled(LaborBudget.parse(text) == nil)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                monthOnly = LaborBudget.isMonthOnly(store: book.scopeStoreID, month: month, rules: book.pay)
                if let v = LaborBudget.value(store: book.scopeStoreID, month: month, rules: book.pay) {
                    text = v.formatted(.number.grouping(.automatic))
                }
            }
            .errorAlert($failure)
        }
        .presentationDetents([.medium, .large])
    }

    private func save(_ value: Int?) {
        var rules = store.book.pay
        let key = LaborBudget.key(store: store.book.scopeStoreID, month: monthOnly ? month : nil)
        rules.budgets[key] = value
        // 毎月の予算に切り替えたら、この月だけの予算は外す（入れた金額がこの月にそのまま出るように）
        if !monthOnly, value != nil { rules.budgets[LaborBudget.key(store: store.book.scopeStoreID, month: month)] = nil }
        do { try store.setPayRules(rules); dismiss() } catch { failure = "保存できませんでした（\(error.localizedDescription)）" }
    }
}

// MARK: - 設定 → 人件費

struct PayRulesView: View {
    @Environment(\.shiftStore) private var store
    @State private var rules = PayRules()
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        let lock = LaborCostLock.shared
        Form {
            Section {
                Toggle("この端末で人件費・給与を隠す", isOn: Binding(get: { lock.hidden }, set: { on in
                    Task {
                        if !(await lock.setHidden(on)) {
                            error = lock.deviceCanAuthenticate ? "確認できなかったため、変更していません。"
                                                               : "この端末にパスコードが設定されていないため、隠す設定は使えません。"
                        }
                    }
                }))
            } footer: {
                Text("オンにすると、集計の人件費とスタッフの給与は、Face ID・パスコードで確認するまで表示しません。アプリを離れると、また隠れます。オン・オフの切り替えにも確認が要ります。設定はこの端末だけです（同じ Apple ID のほかの端末は、それぞれで決めます）。")
            }

            if lock.canView {
                Section {
                    Stepper("時間外の割増 \(rules.overtimeRate)%", value: $rules.overtimeRate, in: 0...100, step: 5)
                    Stepper("深夜（22時〜5時）の割増 \(rules.nightRate)%", value: $rules.nightRate, in: 0...100, step: 5)
                } header: {
                    Text("割増")
                }
                Section {
                    Toggle("1日の実働", isOn: $rules.dailyEnabled)
                    if rules.dailyEnabled {
                        Stepper("\(rules.dailyHours)時間を超えた分", value: $rules.dailyHours, in: 4...16)
                    }
                    Toggle("週（月〜日）の実働", isOn: $rules.weeklyEnabled)
                    if rules.weeklyEnabled {
                        Stepper("\(rules.weeklyHours)時間を超えた分", value: $rules.weeklyHours, in: 20...60)
                    }
                } header: {
                    Text("時間外にする時間")
                } footer: {
                    Text("週は、1日の時間外として数えた分を除いて合計します。週の時間は、掛け持ちのほかの店舗の勤務も合わせて数えます。")
                }
                Section {
                    Stepper("月の所定労働時間 \(rules.monthlyStandardHours)時間", value: $rules.monthlyStandardHours, in: 80...240, step: 1)
                } header: {
                    Text("月給の人")
                } footer: {
                    Text("月給の人の1時間あたりの金額＝月給÷この時間。時間外はその\(100 + rules.overtimeRate)%、深夜は\(rules.nightRate)%を足します。月給そのものは在籍した日数で日割りします。")
                }
            } else {
                Section { LaborCostLockedView(compact: true) }
            }
        }
        .navigationTitle("人件費")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !loaded { rules = store.book.pay; loaded = true }
        }
        .onChange(of: rules) {
            guard loaded, rules != store.book.pay else { return }
            do { try store.setPayRules(rules) } catch { self.error = error.localizedDescription }
        }
        .errorAlert($error)
    }
}

// MARK: - スタッフ → 給与（「この日から時給〇円」の履歴）

struct WageSection: View {
    @Binding var member: StaffMember
    @Environment(\.shiftStore) private var store
    @State private var editing: WageEntry?

    var body: some View {
        Section {
            if LaborCostLock.shared.canView {
                let today = DayKey.today
                let current = member.wage(on: today)
                let minimum = MinimumWage.value(for: member, in: store.book)
                ForEach(member.wages.sorted { $0.from > $1.from }) { w in
                    Button { editing = w } label: {
                        HStack {
                            Text("\(Self.date(w.from))〜").monospacedDigit().foregroundStyle(.primary)
                            if w.id == current?.id { StatusPill(text: "いま", color: .green) }
                            if MinimumWage.shortfall(w, minimum: minimum) != nil { StatusPill(text: "最低賃金未満", color: .red) }
                            Spacer()
                            Text("\(w.kind.label) \(LaborCostView.yen(w.amount))").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                Button {
                    let last = member.wages.max { $0.from < $1.from }
                    let start = member.joinDate.isEmpty || last != nil ? today.description : member.joinDate
                    editing = WageEntry(id: UUID().uuidString, from: start, kind: last?.kind ?? .hourly, amount: last?.amount ?? 0)
                } label: { Label(member.wages.isEmpty ? "給与を入れる" : "給与の変更を追加", systemImage: "plus") }
                if let minimum {
                    LabeledContent("店舗の最低賃金", value: LaborCostView.yen(minimum)).appFont(.subheadline)
                }
            } else {
                LaborCostLockedView(compact: true)
            }
        } header: {
            Text("給与")
        } footer: {
            if LaborCostLock.shared.canView {
                Text("「この日から時給〇円（月給〇円）」を入れます。昇給したら、変える日から新しい金額を追加してください。その日より前のシフトは前の金額で計算します。人件費の集計にだけ使います。")
            }
        }
        .shiftSheet(item: $editing) { w in
            WageEditView(entry: w, wages: $member.wages, minimumWage: MinimumWage.value(for: member, in: store.book))
        }
    }

    static func date(_ s: String) -> String {
        guard let d = DayKey(s) else { return s }
        return "\(d.year)/\(d.month)/\(d.day)"
    }
}

struct WageEditView: View {
    @State var entry: WageEntry
    @Binding var wages: [WageEntry]
    /// その人の店舗の最低賃金（決まっていなければ nil）
    var minimumWage: Int? = nil
    @Environment(\.dismiss) private var dismiss
    /// 決定するとき、時給を10円単位に切り上げる（端末ごとに覚える）
    @AppStorage("wageRoundUp10") private var roundUp10 = false
    @State private var initial: WageEntry?
    @State private var askDiscard = false
    @State private var confirmDelete = false

    private var isNew: Bool { !wages.contains { $0.id == entry.id } }
    /// 同じ日から始まるほかの決まり（どちらを使うか決まらないので保存させない）
    private var sameDay: Bool { wages.contains { $0.id != entry.id && $0.from == entry.from } }
    private var dirty: Bool { initial.map { $0 != entry } ?? false }
    /// 決定したときに入る内容（10円単位の切り上げを入れたもの）
    private var saved: WageEntry {
        var e = entry
        if roundUp10, e.kind == .hourly { e.amount = MinimumWage.roundUp10(e.amount) }
        return e
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("この日から", selection: Binding(get: { DayKey(entry.from)?.date ?? Date() },
                                                            set: { entry.from = DayKey($0).description }),
                               displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "ja_JP"))
                    Picker("種類", selection: $entry.kind) {
                        ForEach(WageEntry.Kind.allCases) { Text($0.label).tag($0) }
                    }
                    .segmented(WageEntry.Kind.allCases.count)
                    HStack {
                        Text(entry.kind == .hourly ? "時給" : "月給")
                        TextField("金額", value: $entry.amount, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        Text("円").foregroundStyle(.secondary)
                    }
                    if sameDay {
                        Text("同じ日から始まる給与がもう入っています。日付を変えてください。").appFont(.footnote).foregroundStyle(.red)
                    }
                    if entry.kind == .hourly {
                        if let minimumWage {
                            LabeledContent("店舗の最低賃金", value: LaborCostView.yen(minimumWage))
                        }
                        Toggle("10円単位に切り上げる", isOn: $roundUp10)
                        if roundUp10, MinimumWage.roundUp10(entry.amount) != entry.amount {
                            Text("決定すると \(LaborCostView.yen(MinimumWage.roundUp10(entry.amount))) にします。").appFont(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if let short = MinimumWage.shortfall(saved, minimum: minimumWage) {
                        Text("最低賃金より \(LaborCostView.yen(short)) 低い時給です。都道府県の最低賃金を確かめてください。").appFont(.footnote).foregroundStyle(.red)
                    }
                    if entry.amount <= 0 {
                        Text("金額を入れてください。").appFont(.footnote).foregroundStyle(.red)
                    } else if entry.kind == .hourly && entry.amount > 20_000 || entry.kind == .monthly && entry.amount < 10_000 {
                        Text("時給・月給の種類が合っているか確かめてください。").appFont(.footnote).foregroundStyle(.orange)
                    }
                }
                if !isNew {
                    Section {
                        Button("この給与を削除", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "給与を追加" : "給与")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { if initial == nil { initial = entry } }
            .discardGuard(dirty: dirty, asking: $askDiscard) { dismiss() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("やめる") { if dirty { askDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("決定") {
                        let e = saved
                        if let i = wages.firstIndex(where: { $0.id == e.id }) { wages[i] = e } else { wages.append(e) }
                        dismiss()
                    }
                    .disabled(entry.amount <= 0 || sameDay)
                }
            }
            .confirmationDialog("この給与を削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("削除する", role: .destructive) {
                    wages.removeAll { $0.id == entry.id }
                    dismiss()
                }
            } message: {
                Text("削除した期間のシフトは、その前の給与で計算します（前が無ければ未設定）。")
            }
        }
    }
}
