import SwiftUI

/// シフト表（月・週。左に名前、右に日付）
/// 月は横に動かして見る。週は7日を画面の幅に収め、マスを大きくして勤務時間も出す
struct MonthGridView: View {
    let mode: GridMode
    let days: [DayKey]
    /// 日付を押したとき（その日のタイムラインへ）
    var onOpenDay: (DayKey) -> Void = { _ in }

    @Environment(ShiftStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selected: Selection?

    private struct Selection: Identifiable {
        let member: StaffMember
        let day: DayKey
        var id: String { CellKey(staffID: member.id, day: day).description }
    }

    /// スタッフの設定を開く（名前の下の「＋パターン」など）
    private struct StaffSheet: Identifiable {
        let member: StaffMember
        let isNew: Bool
        var id: String { member.id }
    }

    /// 表の1行（名前の列と表の本体を同じ並び・同じ高さで描くため）
    private enum Row: Identifiable {
        case section(Department, Int)
        case staff(StaffMember)
        case hourToggle(Department)
        case hour(Department, [StaffMember], Int)

        var id: String {
            switch self {
            case .section(let d, _): "s-\(d.id)"
            case .staff(let m): "m-\(m.id)"
            case .hourToggle(let d): "t-\(d.id)"
            case .hour(let d, _, let h): "h-\(d.id)-\(h)"
            }
        }
    }

    @AppStorage("showInactive") private var showInactive = false
    @State private var openHourly: Set<String> = []
    @State private var staffSheet: StaffSheet?

    private var compact: Bool { sizeClass == .compact }
    private var nameWidth: CGFloat { compact ? 104 : 156 }
    @State private var availableWidth: CGFloat = 0
    private var isWeek: Bool { mode == .week }
    private var cellWidth: CGFloat {
        guard isWeek else { return compact ? 46 : 54 }
        return max(compact ? 64 : 96, (availableWidth - nameWidth - summaryWidth) / 7)
    }
    private var rowHeight: CGFloat { isWeek ? (compact ? 78 : 70) : 58 }
    private let headerHeight: CGFloat = 46
    private let sectionHeight: CGFloat = 28
    private let toggleHeight: CGFloat = 26
    private let hourHeight: CGFloat = 22
    private let summaryWidth: CGFloat = 70
    /// 時間帯別在籍人数の並び（PC版と同じ：9時〜翌8時）
    private let hours = [9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 0, 1, 2, 3, 4, 5, 6, 7, 8]

    @State private var scroll = ScrollTracker()

    private func rows(_ book: ShiftBook) -> [Row] {
        var out: [Row] = []
        for g in book.staffByDepartment(visibleIn: MonthKey(days[0]), includeInactive: showInactive) {
            out.append(.section(g.department, g.members.count))
            out += g.members.map(Row.staff)
            out.append(.hourToggle(g.department))
            if openHourly.contains(g.department.id) {
                out += hours.map { Row.hour(g.department, g.members, $0) }
            }
        }
        return out
    }

    private func height(_ r: Row) -> CGFloat {
        switch r {
        case .section: sectionHeight
        case .staff: rowHeight
        case .hourToggle: toggleHeight
        case .hour: hourHeight
        }
    }

    var body: some View {
        let book = store.book
        let rows = rows(book)
        let today = DayKey.today

        // 上：日付の行（縦には動かない。横は下の表と同じだけずらす）
        // 下：縦に動く。左に名前の列、右に横に動く表
        // 画面の幅は外から受け取る（表の中身の幅を測ると、広がった幅をまた使ってしまい、名前の列が画面の外に出る）
        GeometryReader { geo in
        VStack(spacing: 0) {
            toolbarRow
            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("No").frame(width: 26)
                    Text("氏名").frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .frame(width: nameWidth, height: headerHeight)
                .overlay(alignment: .trailing) { Divider() }
                FollowingHeader(tracker: scroll) {
                    HStack(spacing: 0) {
                        ForEach(days, id: \.self) { d in
                            dayHeader(d, today: today)
                                .contentShape(Rectangle())
                                .onTapGesture { onOpenDay(d) }
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
                        ForEach(rows) { r in leftCell(r, book: book).frame(height: height(r)) }
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
                                ForEach(rows) { r in rightCells(r, book: book, today: today).frame(height: height(r)) }
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
        .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        .onAppear { availableWidth = geo.size.width }
        .onChange(of: geo.size.width) { availableWidth = geo.size.width }
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
        .sheet(item: $staffSheet) { s in
            if s.isNew {
                StaffEditView(member: s.member, isNew: true)
            } else {
                NavigationStack { StaffEditView(member: s.member, isNew: false) }
            }
        }
    }

    // MARK: 表の上の操作

    private var toolbarRow: some View {
        HStack(spacing: 14) {
            Button {
                staffSheet = StaffSheet(member: store.newStaff(in: store.book.departments.first?.id ?? ""), isNew: true)
            } label: {
                Label("スタッフを追加", systemImage: "person.badge.plus")
            }
            Toggle("退職者も表示", isOn: $showInactive)
                .toggleStyle(.button)
            Spacer(minLength: 0)
            if !compact {
                HStack(spacing: 4) {
                    Circle().fill(Color.orange.opacity(0.8)).frame(width: 6, height: 6)
                    Text("パターンから自動で入ったシフト")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            if !store.editing {
                Text("ロック中（鉛筆で編集）").font(.caption).foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: 行の中身

    @ViewBuilder
    private func leftCell(_ r: Row, book: ShiftBook) -> some View {
        switch r {
        case .section(let d, let n):
            sectionLabel(d, count: n)
        case .staff(let m):
            nameCell(m, book: book)
        case .hourToggle(let d):
            Button {
                if openHourly.contains(d.id) { openHourly.remove(d.id) } else {
                    openHourly.insert(d.id)
                    CoachCenter.shared.show(.hourly("hourly-\(d.id)"), after: 0.3)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: openHourly.contains(d.id) ? "chevron.down" : "chevron.right").font(.caption2)
                    Text("時間帯別在籍人数").font(.caption.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .coachTarget("hourly-\(d.id)")
            .overlay(alignment: .bottom) { Divider() }
        case .hour(_, _, let h):
            let night = h <= 8
            HStack(spacing: 0) {
                Text(night ? "明" : "").font(.system(size: 9)).foregroundStyle(.secondary).frame(width: 26)
                Text(String(format: "%02d:00", h)).font(.system(size: 11, weight: .bold)).monospacedDigit()
                    .foregroundStyle(night ? Color.blue : Color.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(maxHeight: .infinity)
            .background(night ? Color.blue.opacity(0.06) : Color(.secondarySystemBackground).opacity(0.4))
        }
    }

    @ViewBuilder
    private func rightCells(_ r: Row, book: ShiftBook, today: DayKey) -> some View {
        switch r {
        case .section:
            Rectangle().fill(Color(.secondarySystemBackground))
                .frame(width: cellWidth * CGFloat(days.count) + summaryWidth)
        case .staff(let m):
            HStack(spacing: 0) {
                ForEach(days, id: \.self) { d in
                    ShiftCellView(member: m, day: d, resolved: Schedule.resolve(m, on: d, in: book),
                                  book: book, isToday: d == today, compact: compact, large: isWeek)
                        .frame(width: cellWidth, height: rowHeight)
                        .contentShape(Rectangle())
                        .onTapGesture { if !m.hasLeft(on: d) { selected = Selection(member: m, day: d) } }
                }
                summaryCell(MonthSummary.of(m, days: days, in: book))
            }
            .overlay(alignment: .bottom) { Divider() }
        case .hourToggle:
            Color(.systemBackground)
                .frame(width: cellWidth * CGFloat(days.count) + summaryWidth)
                .overlay(alignment: .bottom) { Divider() }
        case .hour(_, let members, let h):
            let night = h <= 8
            HStack(spacing: 0) {
                ForEach(days, id: \.self) { d in
                    let n = Headcount.working(members, on: d, hour: h, in: book)
                    Text(n == 0 ? "0" : "\(n)")
                        .font(.system(size: n > 2 ? 13 : 11, weight: n > 2 ? .heavy : n > 0 ? .bold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(n == 0 ? Color(.tertiaryLabel) : night ? Color.blue : Color.green)
                        .frame(width: cellWidth, height: hourHeight)
                        .background(n > 0 ? (night ? Color.blue.opacity(0.15) : Color.green.opacity(0.15)) : Color.clear)
                        .overlay(alignment: .trailing) { Rectangle().fill(Color(.separator)).frame(width: 0.5) }
                }
                Color.clear.frame(width: summaryWidth, height: hourHeight)
            }
            .background(night ? Color.blue.opacity(0.04) : Color(.secondarySystemBackground).opacity(0.3))
        }
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

    private func sectionLabel(_ d: Department, count: Int) -> some View {
        HStack(spacing: 6) {
            Circle().fill(PaletteColor.fg(d.colorIndex)).frame(width: 8, height: 8)
            Text(d.name).font(.caption.bold()).foregroundStyle(PaletteColor.fg(d.colorIndex))
            Text("\(count)人").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        .background(Color(.secondarySystemBackground))
    }

    /// 番号・名前・使う週間パターン（切り替え）・個人の時間
    private func nameCell(_ m: StaffMember, book: ShiftBook) -> some View {
        let active = m.patterns.first { $0.id == m.activePatternID }
        return HStack(alignment: .center, spacing: 0) {
            Text("\(m.number)").font(.caption2).foregroundStyle(.secondary).monospacedDigit().frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.name)
                    .font(compact ? .footnote.weight(.bold) : .subheadline.weight(.bold))
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .foregroundStyle(m.active && m.leaveDate.isEmpty ? Color.primary : Color.secondary)
                if m.active {
                    if m.patterns.isEmpty {
                        Button("＋パターン") { staffSheet = StaffSheet(member: m, isNew: false) }
                            .font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Menu {
                            ForEach(m.patterns) { p in
                                Button {
                                    var x = m
                                    x.activePatternID = p.id
                                    try? store.save(x)
                                    CoachCenter.shared.show(.pattern("pattern-\(m.id)"), after: 0.5)
                                } label: {
                                    if p.id == m.activePatternID { Label(patternTitle(p), systemImage: "checkmark") }
                                    else { Text(patternTitle(p)) }
                                }
                            }
                        } label: {
                            Text(active?.label ?? "パターン").font(.caption2.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .foregroundStyle(PaletteColor.fg(active?.colorIndex ?? 8))
                                .background(PaletteColor.bg(active?.colorIndex ?? 8), in: RoundedRectangle(cornerRadius: 4))
                        }
                        .coachTarget("pattern-\(m.id)")
                    }
                }
                if !m.timeBlocks.isEmpty && !compact {
                    Button("個人の時間 \(m.timeBlocks.count)件") { staffSheet = StaffSheet(member: m, isNew: false) }
                        .font(.system(size: 10)).foregroundStyle(Color.accentColor)
                }
            }
            Spacer(minLength: 0)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 4)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .contextMenu {
            Button("スタッフの設定を開く") { staffSheet = StaffSheet(member: m, isNew: false) }
        }
        .overlay(alignment: .bottom) { Divider() }
    }

    private func patternTitle(_ p: WeekPattern) -> String {
        (p.label.isEmpty ? "パターン" : p.label) + (p.activeFrom.map { "（\($0)〜）" } ?? "（標準）")
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
                            if let h = r.netHours(book.breakRules) { Text(String(format: "%.1fh", h)).foregroundStyle(.secondary) }
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
