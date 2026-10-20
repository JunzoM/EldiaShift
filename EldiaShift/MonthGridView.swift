import SwiftUI

/// 月のシフト表（左に名前、右に日付。横に動かして見る）
struct MonthGridView: View {
    let month: MonthKey

    @Environment(ShiftStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selected: Selection?

    private struct Selection: Identifiable {
        let member: StaffMember
        let day: DayKey
        var id: String { CellKey(staffID: member.id, day: day).description }
    }

    private var compact: Bool { sizeClass == .compact }
    private var nameWidth: CGFloat { compact ? 76 : 116 }
    private var cellWidth: CGFloat { compact ? 46 : 54 }
    private let rowHeight: CGFloat = 52
    private let headerHeight: CGFloat = 46
    private let sectionHeight: CGFloat = 28
    private let summaryWidth: CGFloat = 70

    var body: some View {
        let book = store.book
        let days = month.days
        let groups = book.staffByDepartment(visibleIn: month)
        let today = DayKey.today

        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                // 名前の列（横には動かない）
                VStack(spacing: 0) {
                    Color.clear.frame(height: headerHeight)
                    ForEach(groups) { g in
                        sectionLabel(g.department)
                        ForEach(g.members) { m in
                            nameCell(m)
                        }
                    }
                }
                .frame(width: nameWidth)
                .background(Color(.systemBackground))
                .overlay(alignment: .trailing) { Divider() }
                .zIndex(1)

                // 日付の列（横に動く）
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                ForEach(days, id: \.self) { d in dayHeader(d, today: today).id(d) }
                                summaryHeader
                            }
                            ForEach(groups) { g in
                                Rectangle().fill(Color(.secondarySystemBackground))
                                    .frame(height: sectionHeight)
                                ForEach(g.members) { m in
                                    HStack(spacing: 0) {
                                        ForEach(days, id: \.self) { d in
                                            ShiftCellView(member: m, day: d, resolved: Schedule.resolve(m, on: d, in: book),
                                                          book: book, isToday: d == today, compact: compact)
                                                .frame(width: cellWidth, height: rowHeight)
                                                .contentShape(Rectangle())
                                                .onTapGesture { selected = Selection(member: m, day: d) }
                                        }
                                        summaryCell(MonthSummary.of(m, month: month, in: book))
                                    }
                                    .overlay(alignment: .bottom) { Divider() }
                                }
                            }
                        }
                    }
                    .scrollIndicators(.visible)
                    .onAppear { scrollToToday(proxy, days: days, today: today) }
                    .onChange(of: month) { scrollToToday(proxy, days: days, today: today) }
                }
            }
        }
        .sheet(item: $selected) { s in
            CellDetailSheet(member: s.member, day: s.day)
                .presentationDetents([.medium])
        }
    }

    private func scrollToToday(_ proxy: ScrollViewProxy, days: [DayKey], today: DayKey) {
        let target = days.contains(today) ? today.adding(days: -2) : days.first
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
        return VStack(spacing: 1) {
            Text("\(d.day)").font(.subheadline.weight(.bold)).monospacedDigit()
            Text(["日", "月", "火", "水", "木", "金", "土"][d.weekday]).font(.caption2)
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

/// 1人×1日のマス
struct ShiftCellView: View {
    let member: StaffMember
    let day: DayKey
    let resolved: ResolvedShift?
    let book: ShiftBook
    let isToday: Bool
    let compact: Bool

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
                Text(block?.short ?? "休")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PaletteColor.fg(block?.colorIndex ?? 8))
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
