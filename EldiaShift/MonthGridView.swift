import SwiftUI

/// シフト表（月・週。左に名前、右に日付）
/// 月は横に動かして見る。週は7日を画面の幅に収め、マスを大きくして勤務時間も出す
struct MonthGridView: View {
    let mode: GridMode
    let days: [DayKey]

    @Environment(ShiftStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selected: Selection?
    @State private var timelineDay: DayKey?

    private struct Selection: Identifiable {
        let member: StaffMember
        let day: DayKey
        var id: String { CellKey(staffID: member.id, day: day).description }
    }

    private var compact: Bool { sizeClass == .compact }
    private var nameWidth: CGFloat { compact ? 76 : 116 }
    @State private var availableWidth: CGFloat = 0
    private var isWeek: Bool { mode == .week }
    private var cellWidth: CGFloat {
        guard isWeek else { return compact ? 46 : 54 }
        return max(compact ? 64 : 96, (availableWidth - nameWidth - summaryWidth) / 7)
    }
    private var rowHeight: CGFloat { isWeek ? (compact ? 78 : 70) : 52 }
    private let headerHeight: CGFloat = 46
    private let sectionHeight: CGFloat = 28
    private let summaryWidth: CGFloat = 70

    @State private var scroll = ScrollTracker()

    var body: some View {
        let book = store.book
        let groups = book.staffByDepartment(visibleIn: MonthKey(days[0]))
        let today = DayKey.today

        // 上：日付の行（縦には動かない。横は下の表と同じだけずらす）
        // 下：縦に動く。左に名前の列、右に横に動く表
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(isWeek ? "週" : "\(days[0].month)月").font(.subheadline.weight(.bold))
                    .frame(width: nameWidth, height: headerHeight)
                    .overlay(alignment: .trailing) { Divider() }
                FollowingHeader(tracker: scroll) {
                    HStack(spacing: 0) {
                        ForEach(days, id: \.self) { d in
                            dayHeader(d, today: today)
                                .contentShape(Rectangle())
                                .onTapGesture { timelineDay = d }
                                .accessibilityAddTraits(.isButton)
                                .accessibilityHint("その日のタイムラインを開きます")
                        }
                        summaryHeader
                    }
                }
            }
            .frame(height: headerHeight)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }

            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        ForEach(groups) { g in
                            sectionLabel(g.department)
                            ForEach(g.members) { m in nameCell(m) }
                        }
                    }
                    .frame(width: nameWidth)
                    .overlay(alignment: .trailing) { Divider() }

                    ScrollViewReader { proxy in
                        ScrollView(.horizontal) {
                            VStack(spacing: 0) {
                                // スクロール位置を合わせるための目印（日付ごと）
                                HStack(spacing: 0) {
                                    ForEach(days, id: \.self) { d in Color.clear.frame(width: cellWidth, height: 1).id(d) }
                                }
                                ForEach(groups) { g in
                                    Rectangle().fill(Color(.secondarySystemBackground))
                                        .frame(height: sectionHeight)
                                    ForEach(g.members) { m in
                                        HStack(spacing: 0) {
                                            ForEach(days, id: \.self) { d in
                                                ShiftCellView(member: m, day: d, resolved: Schedule.resolve(m, on: d, in: book),
                                                              book: book, isToday: d == today, compact: compact, large: isWeek)
                                                    .frame(width: cellWidth, height: rowHeight)
                                                    .contentShape(Rectangle())
                                                    .onTapGesture { selected = Selection(member: m, day: d) }
                                            }
                                            summaryCell(MonthSummary.of(m, days: days, in: book))
                                        }
                                        .overlay(alignment: .bottom) { Divider() }
                                    }
                                }
                            }
                            .background(GeometryReader { g in
                                // iOS 17 用：表の位置が変わったら日付の行を合わせる（iOS 18 以降は下の onScrollGeometryChange）
                                let x = g.frame(in: .named("gridH")).minX
                                Color.clear
                                    .onAppear { scroll.x = max(0, -x) }
                                    .onChange(of: x) { scroll.x = max(0, -x) }
                            })
                        }
                        .coordinateSpace(name: "gridH")
                        // 横に動く表の幅は「画面の幅 − 名前の列」に固定する（中身の幅に合わせて広がると、名前の列が画面の外に押し出される）
                        .frame(width: max(0, availableWidth - nameWidth))
                        .scrollDisabled(isWeek && cellWidth * 7 + summaryWidth <= availableWidth - nameWidth + 1)
                        .modifier(TrackHorizontalScroll(tracker: scroll))
                        .onAppear { scrollToToday(proxy, days: days, today: today) }
                        .onChange(of: days) { scrollToToday(proxy, days: days, today: today) }
                    }
                }
            }
        }
        .background(GeometryReader { g in
            Color.clear
                .onAppear { availableWidth = g.size.width }
                .onChange(of: g.size.width) { availableWidth = g.size.width }
        })
        .sheet(item: $selected) { s in
            if store.editing {
                CellEditorSheet(member: s.member, day: s.day)
                    .presentationDetents([.medium, .large])
            } else {
                CellDetailSheet(member: s.member, day: s.day)
                    .presentationDetents([.medium])
            }
        }
        .navigationDestination(item: $timelineDay) { d in DayTimelineView(day: d) }
    }

    private func scrollToToday(_ proxy: ScrollViewProxy, days: [DayKey], today: DayKey) {
        // 左には名前の列が重なるので、今日の数日前を左端に合わせる
        // 週は月曜から見せる（動かさない）。月は今日の数日前を左端に
        guard !isWeek else { return }
        let target = days.contains(today) ? today.adding(days: -(compact ? 2 : 3)) : nil
        if let target, days.contains(target) { proxy.scrollTo(target, anchor: .leading) }
        else if let first = days.first { proxy.scrollTo(first, anchor: .leading) }
    }

    // MARK: 部品

    private func sectionLabel(_ d: Department) -> some View {
        HStack(spacing: 6) {
            Circle().fill(PaletteColor.fg(d.colorIndex)).frame(width: 8, height: 8)
            Text(d.name).font(.caption.bold()).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: sectionHeight)
        .background(Color(.secondarySystemBackground))
    }

    private func nameCell(_ m: StaffMember) -> some View {
        Text(m.name)
            .font(compact ? .footnote.weight(.semibold) : .subheadline.weight(.semibold))
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .frame(height: rowHeight)
            .overlay(alignment: .bottom) { Divider() }
    }

    private func dayHeader(_ d: DayKey, today: DayKey) -> some View {
        let holiday = JapaneseHolidays.name(d)
        let color: Color = (d.weekday == 0 || holiday != nil) ? .red : d.weekday == 6 ? .blue : .primary
        let wd = ["日", "月", "火", "水", "木", "金", "土"][d.weekday]
        return VStack(spacing: 1) {
            if isWeek {
                Text("\(d.month)/\(d.day)（\(wd)）").font(.subheadline.weight(.bold)).monospacedDigit()
                if let holiday { Text(holiday).font(.caption2).lineLimit(1) }
            } else {
                Text("\(d.day)").font(.subheadline.weight(.bold)).monospacedDigit()
                Text(wd).font(.caption2)
            }
        }
        .foregroundStyle(color)
        .frame(width: cellWidth, height: headerHeight)
        .background(d == today ? Color.accentColor.opacity(0.15) : .clear)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(d.month)月\(d.day)日\(holiday.map { "、\($0)" } ?? "")")
    }

    private var summaryHeader: some View {
        Text("合計").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            .frame(width: summaryWidth, height: headerHeight)
    }

    private func summaryCell(_ s: MonthSummary) -> some View {
        VStack(spacing: 1) {
            Text("\(s.workDays)日").font(.caption.weight(.semibold))
            Text(String(format: "%.1fh", s.hours)).font(.caption2).foregroundStyle(.secondary)
        }
        .monospacedDigit()
        .frame(width: summaryWidth, height: rowHeight)
        .background(Color(.secondarySystemBackground).opacity(0.5))
        .accessibilityElement(children: .combine)
    }
}

/// 表を横に動かした量（日付の行だけがこれを見る。表の本体は動かすたびに作り直さない）
@MainActor
@Observable
final class ScrollTracker {
    var x: CGFloat = 0
}

/// iOS 18 以降は、スクロールの位置をそのまま受け取る（確実で軽い）
private struct TrackHorizontalScroll: ViewModifier {
    let tracker: ScrollTracker

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.x + geo.contentInsets.leading
            } action: { _, x in
                tracker.x = max(0, x)
            }
        } else {
            content
        }
    }
}

/// 下の表を横に動かした分だけ、日付の行をずらす
private struct FollowingHeader<Content: View>: View {
    let tracker: ScrollTracker
    @ViewBuilder let content: Content

    var body: some View {
        // 重ねて置くだけにして、日付の行の幅が画面の幅に影響しないようにする
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .leading) {
                content.fixedSize().offset(x: -tracker.x)
            }
            .clipped()
    }
}

/// 1人×1日のマス
struct ShiftCellView: View {
    let member: StaffMember
    let day: DayKey
    let resolved: ResolvedShift?
    let book: ShiftBook
    let isToday: Bool
    let compact: Bool
    /// 週表示（マスが大きい）：時刻を大きく、勤務時間とひな形の名前も出す
    var large = false

    var body: some View {
        let block = book.block(resolved?.blockID, for: member)
        ZStack {
            background(block)
            content(block)
        }
        .overlay(alignment: large ? .bottomTrailing : .topTrailing) {
            // 自動（くり返し・期間の予定）で決まったマスの印。時刻に重ならないよう隅に小さく
            if resolved?.isAuto == true {
                Circle().fill(Color.orange.opacity(0.8)).frame(width: 5, height: 5).padding(large ? 5 : 2)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .trailing) { Rectangle().fill(Color(.separator)).frame(width: 0.5) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(block))
    }

    @ViewBuilder
    private func background(_ block: TimeBlock?) -> some View {
        if member.hasLeft(on: day) {
            Color(.secondarySystemBackground)
        } else if resolved?.isOff == true {
            PaletteColor.bg(block?.colorIndex ?? 8)
        } else if isToday {
            Color.accentColor.opacity(0.10)
        } else if day.weekday == 0 || JapaneseHolidays.isHoliday(day) {
            Color.red.opacity(0.04)
        } else if day.weekday == 6 {
            Color.blue.opacity(0.04)
        } else {
            Color(.systemBackground)
        }
    }

    @ViewBuilder
    private func content(_ block: TimeBlock?) -> some View {
        if member.hasLeft(on: day) {
            Text("－").font(.caption2).foregroundStyle(.tertiary)
        } else if let r = resolved {
            if r.isOff {
                Text(large ? (block?.label ?? "休み") : (block?.short ?? "休"))
                    .font(large ? .headline : .subheadline.weight(.bold))
                    .foregroundStyle(PaletteColor.fg(block?.colorIndex ?? 8))
            } else {
                if large {
                    VStack(spacing: 2) {
                        if compact {
                            // iPhone は幅が狭いので、出勤・退勤を2行に
                            Text(r.inTime.isEmpty ? "—" : r.inTime).font(.system(size: 13, weight: .bold))
                            Text(r.outTime.isEmpty ? "—" : r.outTime).font(.system(size: 13)).foregroundStyle(.secondary)
                        } else {
                            Text("\(r.inTime.isEmpty ? "—" : r.inTime)〜\(r.outTime.isEmpty ? "—" : r.outTime)")
                                .font(.system(size: 14, weight: .bold))
                        }
                        HStack(spacing: 4) {
                            if let block {
                                Text(block.label).foregroundStyle(PaletteColor.fg(block.colorIndex)).fontWeight(.bold)
                            }
                            if let h = r.hours { Text(String(format: "%.1fh", h)).foregroundStyle(.secondary) }
                        }
                        .font(.caption2)
                    }
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 2)
                } else {
                VStack(spacing: 0) {
                    Text(r.inTime.isEmpty ? "—" : r.inTime).font(.system(size: compact ? 11 : 12, weight: .bold))
                    Text(r.outTime.isEmpty ? "—" : r.outTime).font(.system(size: compact ? 11 : 12))
                        .foregroundStyle(.secondary)
                    if let block {
                        Text(block.short).font(.system(size: 9, weight: .bold))
                            .foregroundStyle(PaletteColor.fg(block.colorIndex))
                    }
                }
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                }
            }
        }
    }

    private func accessibilityText(_ block: TimeBlock?) -> String {
        let date = "\(day.month)月\(day.day)日 \(member.name)"
        if member.hasLeft(on: day) { return "\(date)、退職後" }
        guard let r = resolved else { return "\(date)、未定" }
        if r.isOff { return "\(date)、\(block?.label ?? "休み")" }
        return "\(date)、\(r.inTime)から\(r.outTime)\(r.isAuto ? "、自動" : "")"
    }
}

enum PaletteColor {
    static func fg(_ i: Int) -> Color { Color(hex: Palette.colors[Palette.index(i)].fg) }
    static func bg(_ i: Int) -> Color { Color(hex: Palette.colors[Palette.index(i)].bg) }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
