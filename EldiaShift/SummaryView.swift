import SwiftUI

/// 月の集計（PC版の「集計」と同じ：部門ごとに 出勤日数・実働時間・有休の残り・個人の時間）
struct SummaryView: View {
    @State var month: MonthKey

    @Environment(\.shiftStore) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("summaryTab") private var tab = 0

    var body: some View {
        Group {
            if tab == 1 { StaffingAnalysisView(month: month) } else if tab == 2 { LaborIssuesView(month: month) }
            else if tab == 3 { LaborCostView(month: month) } else { hoursList }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("見るもの", selection: $tab) {
                Text("勤務時間・有休").tag(0)
                Text("適正人員").tag(1)
                Text("注意").tag(2)
                Text("人件費").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(.bar)
        }
        .onAppear { CoachCenter.shared.show(.summary(), after: 0.6) }
        .navigationTitle("集計 \(month.description)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if tab == 1 {
                    NavigationLink { StaffingSettingsView() } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("適正人員を決める")
                }
                if tab == 2 {
                    NavigationLink { LaborRulesView() } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("注意の決まりを変える")
                }
                if tab == 3 {
                    NavigationLink { PayRulesView() } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("人件費の決まりを変える")
                }
                Button { month = month.adding(months: -1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("前の月")
                Button { month = month.adding(months: 1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("次の月")
            }
        }
    }

    @ViewBuilder
    private var hoursList: some View {
        let book = store.book
        let groups = book.staffByDepartment(visibleIn: month)
        // 1人ずつの集計は一度だけ（見出しの合計と行で使い回す）
        let sums = Dictionary(groups.flatMap(\.members).map { ($0.id, MonthSummary.of($0, month: month, in: book)) },
                              uniquingKeysWith: { a, _ in a })
        List {
            ForEach(groups) { g in
                Section {
                    if sizeClass != .compact { header }
                    ForEach(g.members) { m in
                        row(m, book: book, s: sums[m.id] ?? MonthSummary())
                            .modifier(OptionalCoachTarget(id: m.id == groups.first?.members.first?.id ? "summaryLeave" : nil))
                    }
                } header: {
                    HStack {
                        Text(g.department.name).foregroundStyle(PaletteColor.fg(g.department.colorIndex))
                        Spacer()
                        let total = g.members.reduce(0.0) { $0 + (sums[$1.id]?.hours ?? 0) }
                        Text("\(g.members.count)人・合計 \(String(format: "%.1f", total))時間").monospacedDigit()
                    }
                }
            }
            Section {
                Text("時間は休憩を引いた実働です（休憩の決まり：\(store.book.breakRules.summary)。設定で変えられます）。有休は入社日と週間パターンから付与日数を出し、今期の付与日から表示している月の末日までに「有休」を入れた日数を引いています。")
                    .appFont(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("スタッフ").frame(maxWidth: .infinity, alignment: .leading)
            Text("出勤日数").frame(width: 72)
            Text("総時間").frame(width: 84)
            Text("有休残").frame(width: 130)
            Text("個人の時間").frame(width: 200, alignment: .leading)
        }
        .appFont(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func row(_ m: StaffMember, book: ShiftBook, s: MonthSummary) -> some View {
        let leave = PaidLeave.balance(of: m, month: month, in: book)
        if sizeClass == .compact {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(m.number)").appFont(.caption2).foregroundStyle(.secondary)
                    Text(m.name).appFont(.headline)
                    Spacer()
                    Text("\(s.workDays)日").bold()
                    Text(String(format: "%.1f時間", s.hours))
                }
                .monospacedDigit()
                leaveView(m, leave, compact: true)
                if !m.timeBlocks.isEmpty { blocks(m) }
            }
            .padding(.vertical, 2)
        } else {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Text("\(m.number)").appFont(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    Text(m.name).appFont(.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(s.workDays)日").appFont(.body.weight(.bold)).monospacedDigit().frame(width: 72)
                Text(String(format: "%.1f時間", s.hours)).appFont(.body.weight(.bold)).monospacedDigit().frame(width: 84)
                leaveView(m, leave, compact: false).frame(width: 130)
                blocks(m).frame(width: 200, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func leaveView(_ m: StaffMember, _ b: PaidLeave.Balance?, compact: Bool) -> some View {
        if m.joinDate.isEmpty {
            Text(compact ? "有休：入社日が未設定" : "—").appFont(.caption).foregroundStyle(.tertiary)
        } else if let b {
            let detail = "付与\(b.grant.total)日 / 使用済\(b.used)日"
                + (b.usedThisMonth > 0 ? "・今月\(b.usedThisMonth)日" : "")
                + (b.grant.isProportional ? "・比例付与（週\(b.grant.weeklyDays ?? 0)日）" : "")
            if compact {
                Text("有休 残\(b.remaining)日（\(detail)）").appFont(.caption).foregroundStyle(.teal)
            } else {
                VStack(spacing: 1) {
                    Text("残\(b.remaining)日").appFont(.subheadline.weight(.bold)).foregroundStyle(.teal)
                    Text(detail).appFont(.system(size: 9.5)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .monospacedDigit()
            }
        } else {
            Text(compact ? "有休：未付与（入社6か月未満）" : "未付与\n（入社6か月未満）")
                .appFont(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    private func blocks(_ m: StaffMember) -> some View {
        HStack(spacing: 4) {
            if m.timeBlocks.isEmpty {
                Text("—").appFont(.caption).foregroundStyle(.tertiary)
            }
            ForEach(m.timeBlocks) { b in
                Text(b.isOff ? b.short : "\(b.short) \(b.inTime)-\(b.outTime)")
                    .appFont(.system(size: 10, weight: .bold)).monospacedDigit()
                    .foregroundStyle(PaletteColor.fg(b.colorIndex))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(PaletteColor.bg(b.colorIndex), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}
