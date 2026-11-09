import SwiftUI

// MARK: - 縦に開いて上下で使う

/// 下のページに出すもの
enum StackedPage: String, CaseIterable, Identifiable {
    /// 選んだ日のタイムライン
    case day
    /// 選んだ日に人が足りない部門と、入れられる人
    case fill
    /// 今月の人件費と予算
    case cost

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "その日"
        case .fill: "入れられる人"
        case .cost: "人件費"
        }
    }
}

/// 開いた Duo を縦に持ったとき（折り目が横に通る）のシフト表：上のページに月（週）の表、下のページに選んだ日の操作。
/// 半分開いて机に置けば、ノート PC のように上で表を見て、下で人を入れる。下のページは折り目から始めるので、折り目の上に部品が来ない
struct StackedBoard: View {
    let mode: GridMode
    @Binding var anchor: DayKey

    @Environment(\.duo) private var duo
    @Environment(\.shiftStore) private var store
    @Environment(\.shiftDatabase) private var db
    @AppStorage("duoStackedPage") private var page: StackedPage = .day
    /// 「入れられる人」で選んでいる部門（その日に足りない部門が2つ以上あるとき）
    @State private var gapID: ShortageItem.ID?

    /// 出せるもの：「見るだけ」の共有では入れられる人を、共有されたシフト表では人件費を出さない
    private var pages: [StackedPage] {
        StackedPage.allCases.filter { p in
            switch p {
            case .fill: !db.readOnly
            case .cost: !LaborCostLock.shared.sharedTeam
            case .day: true
            }
        }
    }

    private var shown: StackedPage { pages.contains(page) ? page : .day }

    var body: some View {
        let focus = DuoFocus.shared
        let gaps = shown == .fill ? ShortageFinder.items(store.book, days: [anchor]) : []
        GeometryReader { geo in
            let bottom = duo.bottomPageHeight(in: geo.frame(in: .global))
            VStack(spacing: 0) {
                MonthGridView(mode: mode, days: mode.days(around: anchor), selectedDay: anchor,
                              highlightStaffID: focus.staffID,
                              onPickCell: { _, d in anchor = d }) { d in
                    // 日付を押したら、日の表示に切り替えずに下のページだけ変える
                    anchor = d
                }
                .frame(height: max(0, geo.size.height - bottom))

                VStack(spacing: 0) {
                    pageBar
                    switch shown {
                    case .day: DuoDayPage(day: $anchor)
                    case .fill: fillPage(gaps)
                    case .cost: CostPanel(month: MonthKey(anchor))
                    }
                }
                .frame(height: bottom)
                .overlay(alignment: .top) { Rectangle().fill(Color(.separator)).frame(height: 0.5) }
            }
        }
        .onChange(of: gaps.map(\.id)) { pickGap(gaps) }
        .onAppear {
            pickGap(gaps)
            if DemoMode.flag("-demoStackedFill") { page = .fill }
            if DemoMode.flag("-demoStackedCost") { page = .cost }
        }
    }

    /// 下のページの上：何を出すか・掲示
    private var pageBar: some View {
        HStack(spacing: DS.gap) {
            Picker("下に出すもの", selection: $page) {
                ForEach(pages) { p in Text(p.title).tag(p) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        // 折り目のすぐ下なので、少し離す
        .padding(.top, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    /// 入れられる人：その日に足りない部門を選び、その下に入れられる人
    @ViewBuilder
    private func fillPage(_ gaps: [ShortageItem]) -> some View {
        let gap = gaps.first { $0.id == gapID }
        if gaps.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(gaps) { g in
                        Button { gapID = g.id } label: {
                            HStack(spacing: 4) {
                                Circle().fill(PaletteColor.fg(g.department.colorIndex)).frame(width: 8, height: 8)
                                Text("\(g.department.name) −\(g.short)").appFont(.subheadline).monospacedDigit()
                            }
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .tint(g.id == gapID ? .accentColor : .secondary)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
            }
            .overlay(alignment: .bottom) { Divider() }
        }
        GapPanel(item: gap, hasPlan: !store.book.staffing.isEmpty, isEmpty: gaps.isEmpty)
    }

    private func pickGap(_ gaps: [ShortageItem]) {
        guard !gaps.contains(where: { $0.id == gapID }) else { return }
        gapID = gaps.first?.id
    }
}
