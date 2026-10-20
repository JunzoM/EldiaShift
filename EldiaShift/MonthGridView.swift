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
    private var rowHeight: CGFloat { isWeek ? 70 : 52 }
    private let headerHeight: CGFloat = 46
    private let sectionHeight: CGFloat = 28
    private let summaryWidth: CGFloat = 70

    @State private var scroll = ScrollTracker()

    var body: some View {
        let book = store.book
        let groups = book.staffByDepartment(visibleIn: MonthKey(days[0]))
        let today = DayKey.today

        // 縦横どちらにも動く1枚の表。日付の行は上に、名前の列は左に貼り付けて見せる
        // （動いた量は ScrollTracker だけが持ち、表の本体は動かすたびに作り直さない）
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        // スクロール位置を合わせるための目印（日付ごと）
                        HStack(spacing: 0) {
                            Color.clear.frame(width: nameWidth)
                            ForEach(days, id: \.self) { d in Color.clear.frame(width: cellWidth).id(d) }
                            Color.clear.frame(width: summaryWidth)
                        }
                        .frame(height: headerHeight)
                        ForEach(groups) { g in
                            Rectangle().fill(Color(.secondarySystemBackground))
                                .frame(height: sectionHeight)
                            ForEach(g.members) { m in
                                HStack(spacing: 0) {
                                    Color.clear.frame(width: nameWidth)
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

                    // 名前の列（横に動かしても左に残る）
                    PinnedView(tracker: scroll, axis: .horizontal) {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: headerHeight)
                            ForEach(groups) { g in
                                sectionLabel(g.department)
                                ForEach(g.members) { m in nameCell(m) }
                            }
                        }
                        .frame(width: nameWidth)
                        .background(Color(.systemBackground))
                        .overlay(alignment: .trailing) { Divider() }
                    }
                    .zIndex(1)

                    // 日付の行（縦に動かしても上に残る）
                    PinnedView(tracker: scroll, axis: .vertical) {
                        HStack(spacing: 0) {
                            Color.clear.frame(width: nameWidth)
                            ForEach(days, id: \.self) { d in
                                dayHeader(d, today: today)
                                    .contentShape(Rectangle())
                                    .onTapGesture { timelineDay = d }
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityHint("その日のタイムラインを開きます")
                            }
                            summaryHeader
                        }
                        .background(.bar)
                        .overlay(alignment: .bottom) { Divider() }
                    }
                    .zIndex(2)

                    // 左上の角（どちらに動かしても残る）
                    PinnedView(tracker: scroll, axis: nil) {
                        Text(isWeek ? "週" : "\(days[0].month)月").font(.subheadline.weight(.bold))
                            .frame(width: nameWidth, height: headerHeight)
                            .background(.bar)
                            .overlay(alignment: .trailing) { Divider() }
                            .overlay(alignment: .bottom) { Divider() }
                    }
                    .zIndex(3)
                }
                .background(GeometryReader { g in
                    Color.clear.preference(key: ScrollOffsetKey.self, value: g.frame(in: .named("monthGrid")).origin)
                })
            }
            .coordinateSpace(name: "monthGrid")
            .onPreferenceChange(ScrollOffsetKey.self) { origin in
                MainActor.assumeIsolated {
                    scroll.offset = CGPoint(x: max(0, -origin.x), y: max(0, -origin.y))
                }
            }
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { availableWidth = g.size.width }
                    .onChange(of: g.size.width) { availableWidth = g.size.width }
            })
            .onAppear { scrollToToday(proxy, days: days, today: today) }
            .onChange(of: days) { scrollToToday(proxy, days: days, today: today) }
        }
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
        let target = !isWeek && days.contains(today) ? today.adding(days: -(compact ? 2 : 3)) : nil
        if let target, days.contains(target) { proxy.scrollTo(target, anchor: .topLeading) }
        else if let first = days.first { proxy.scrollTo(first, anchor: .topLeading) }
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

/// スクロールした量（表の本体ではなく、貼り付ける部分だけがこれを見る）
@MainActor
@Observable
final class ScrollTracker {
    var offset: CGPoint = .zero
}

private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGPoint = .zero
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) { value = nextValue() }
}

/// スクロールした分だけずらして、画面の端に貼り付いて見せる
/// axis: .horizontal＝左に貼り付く、.vertical＝上に貼り付く、nil＝左上に貼り付く
private struct PinnedView<Content: View>: View {
    let tracker: ScrollTracker
    let axis: Axis?
    @ViewBuilder let content: Content

    var body: some View {
        let o = tracker.offset
        content.offset(x: axis == .vertical ? 0 : o.x, y: axis == .horizontal ? 0 : o.y)
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
        ZStack(alignment: .topTrailing) {
            background(block)
            content(block)
            if resolved?.isAuto == true {
                Circle().fill(Color.orange).frame(width: 5, height: 5).padding(3)
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
                        Text("\(r.inTime.isEmpty ? "—" : r.inTime)〜\(r.outTime.isEmpty ? "—" : r.outTime)")
                            .font(.system(size: compact ? 12 : 14, weight: .bold))
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
