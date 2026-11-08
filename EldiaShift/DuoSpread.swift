import SwiftUI
import UIKit

// MARK: - 折りたたみの iPhone（Duo）：開き具合と折り目の位置

/// 折り目（ヒンジ）の状態。Duo 以外（iPhone・iPad・Mac）や iOS 27.1 より前は `.none`
enum HingeState: Equatable {
    case none
    case closed
    case partiallyOpen
    case fullyOpen

    var isOpen: Bool { self == .partiallyOpen || self == .fullyOpen }
}

/// Duo の見開き（左右2ページ）を作るのに使う情報。窓の座標（SwiftUI の .global と同じ）で持つ
struct DuoInfo: Equatable {
    var hinge: HingeState = .none
    /// 折り目の x（窓の左から）
    var foldX: CGFloat = 0
    /// 窓の幅
    var windowWidth: CGFloat = 0
    /// 画面が横向き（折り目が縦に通っている）
    var landscape = false

    /// 左右のページの、いちばん狭くてよい幅（これより狭くなる窓では見開きにしない）
    static let minPage: CGFloat = 280

    /// 見開きにする：開いていて、横向きで、折り目が窓の中にあり、左右に1ページずつ取れる
    var spread: Bool {
        hinge.isOpen && landscape
            && foldX >= Self.minPage && windowWidth - foldX >= Self.minPage
    }

    /// 右のページの幅。`frame` は見開きにする画面の .global の位置（サイドバーの右など、窓の途中から始まってもよい）。
    /// 右のページは折り目から始める（左のページ＝サイドバー＋月の表、右のページ＝タイムライン）
    func rightPageWidth(in frame: CGRect) -> CGFloat {
        let w = frame.maxX - foldX
        return min(max(w, Self.minPage), max(Self.minPage, frame.width - Self.minPage))
    }

    /// 画面確認用（-demoLayout -demoSpread）：Duo でなくても見開きにする
    static var demoForced: Bool { DemoMode.flag("-demoSpread") || demoHingeScript }

    /// 画面確認用（-demoLayout -demoHingeScript）：開き具合を 全開 → 一瞬だけ半分 → 半分のまま → 全開 と順に変える
    /// （シミュレーターでは半分開きにできないため、半分開いたときの自動の掲示をこれで確かめる）
    static var demoHingeScript: Bool { DemoMode.flag("-demoHingeScript") }
}

private struct DuoInfoKey: EnvironmentKey {
    static let defaultValue = DuoInfo()
}

extension EnvironmentValues {
    /// 折りたたみの iPhone の開き具合と折り目の位置（MainTabsView が入れる）
    var duo: DuoInfo {
        get { self[DuoInfoKey.self] }
        set { self[DuoInfoKey.self] = newValue }
    }
}

/// 見えない部品。折り目の状態（UIHingeInteraction、iOS 27.1 以降）と窓の大きさを調べて知らせる
struct HingeReader: UIViewRepresentable {
    /// 画面の大きさ（変わったら測り直す。横向きで起動したときなど、窓に入った時点ではまだ回る前の大きさのことがある）
    var size: CGSize
    var onChange: (DuoInfo) -> Void

    func makeUIView(context: Context) -> HingeProbeView {
        let v = HingeProbeView()
        v.onChange = onChange
        return v
    }

    func updateUIView(_ v: HingeProbeView, context: Context) {
        v.onChange = onChange
        v.measureWindow()
    }
}

final class HingeProbeView: UIView {
    var onChange: ((DuoInfo) -> Void)?
    private var info = DuoInfo() {
        didSet { if info != oldValue { onChange?(info) } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        installHinge()
        if DuoInfo.demoHingeScript { runHingeScript() }
    }

    /// 画面確認用の開き具合（-demoHingeScript のとき、本物の折り目の代わりに使う）
    private var scriptedHinge: HingeState = .fullyOpen

    private func runHingeScript() {
        let steps: [(Double, HingeState)] = [
            (4, .partiallyOpen), (4.8, .fullyOpen),   // 0.8秒だけ半分：掲示にしない
            (8, .partiallyOpen),                      // 半分のまま：2秒後に掲示
            (14, .fullyOpen),                         // 開ききる：掲示をやめる
        ]
        for (t, h) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
                guard let self else { return }
                print("demoHingeScript t=\(t) hinge=\(h)")
                scriptedHinge = h
                info.hinge = h
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func installHinge() {
        // UIHingeInteraction は iOS 27.1 の SDK から（Xcode 26 の CI でもビルドできるよう、古いコンパイラでは入れない）
        #if compiler(>=6.4.1) && !targetEnvironment(macCatalyst)
        if #available(iOS 27.1, *) {
            addInteraction(UIHingeInteraction { [weak self] _, update in
                // 画面確認用に開いたことにしているときは、本物の折り目の知らせで上書きしない
                guard !DuoInfo.demoForced else { return }
                self?.info.hinge = HingeState(update.hinge)
            })
        }
        #endif
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        measureWindow()
        // 窓に入った直後は回る前の大きさのことがあるので、次の描画のあとにもう一度測る
        DispatchQueue.main.async { [weak self] in self?.measureWindow() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        measureWindow()
    }

    /// 折り目は画面のまん中。窓が画面いっぱいでないとき（ほかのアプリと並べたとき）も合うよう、画面の座標から窓の座標へ直す
    func measureWindow() {
        guard let w = window else { return }
        let screen = w.windowScene?.screen ?? w.screen
        let mid = CGPoint(x: screen.bounds.midX, y: screen.bounds.midY)
        var next = info
        next.foldX = w.convert(mid, from: screen.coordinateSpace).x
        next.windowWidth = w.bounds.width
        next.landscape = screen.bounds.width > screen.bounds.height
        if DuoInfo.demoForced {
            next.hinge = DuoInfo.demoHingeScript ? scriptedHinge : .fullyOpen
            next.foldX = w.bounds.midX
            next.landscape = true
        }
        info = next
    }
}

#if compiler(>=6.4.1) && !targetEnvironment(macCatalyst)
@available(iOS 27.1, *)
extension HingeState {
    init(_ hinge: UIHinge?) {
        switch hinge?.status {
        case .closed: self = .closed
        case .partiallyOpen: self = .partiallyOpen
        case .fullyOpen: self = .fullyOpen
        default: self = .none
        }
    }
}
#endif

// MARK: - 開くとつづき：閉じた画面で見ていた日・人

/// 閉じた画面（や開いた画面）で最後に見ていた日と人。Duo を開いたとき、ここから見開きを始める。
/// 端末の中だけで持つ（保存しない・iCloud で同期しない）
@Observable @MainActor
final class DuoFocus {
    static let shared = DuoFocus()

    /// 見ていた人（いなければ日だけ）
    private(set) var staffID: String?
    private(set) var day: DayKey?
    private(set) var at: Date = .distantPast

    /// これより前に見ていたものは、開いても続きにしない（ポケットから出してすぐ開くくらいの間）
    static let keep: TimeInterval = 15 * 60

    /// 人と日を見た（ホームの「今日の出勤」・シフト表のマス）
    func look(staffID: String?, day: DayKey) {
        self.staffID = staffID
        self.day = day
        at = Date()
    }

    /// 日だけ見た（タイムラインの日を変えた）。見ていた人はそのまま
    func look(day: DayKey) {
        self.day = day
        at = Date()
    }

    /// 人の印を消す
    func clearStaff() { staffID = nil }

    /// 開いたときに続きにする日（少し前に見ていたときだけ）
    func dayToContinue(now: Date = Date()) -> DayKey? {
        guard let day, now.timeIntervalSince(at) < Self.keep else { return nil }
        return day
    }
}

// MARK: - 見開きのシフト表

/// 見開きの左のページに出すもの
enum SpreadPage: String {
    /// 月（週）の表。右のページはその日のタイムライン
    case table
    /// 人が足りない日の一覧。右のページはその日に入れられる人（案3：左右で穴埋め）
    case fill
}

/// 開いた Duo のシフト表：左のページに月（週）の表、右のページに選んだ日のタイムライン。
/// 左のページを「人が足りない」に切り替えると、左に足りない日・時間帯、右に入れられる人が出る。
/// 右のページは折り目から始めるので、折り目の上に部品が来ない
struct SpreadBoard: View {
    let mode: GridMode
    @Binding var anchor: DayKey

    @Environment(\.duo) private var duo
    @Environment(\.shiftStore) private var store
    @Environment(\.shiftDatabase) private var db
    @AppStorage("duoSpreadPage") private var page: SpreadPage = .table
    /// 「人が足りない」で選んでいる行
    @State private var gapID: ShortageItem.ID?

    /// 「見るだけ」で共有されたシフト表では、穴埋め（勤務を入れる）を出さない
    private var filling: Bool { page == .fill && !db.readOnly }

    var body: some View {
        let focus = DuoFocus.shared
        let days = mode.days(around: anchor)
        let gaps = filling ? ShortageFinder.items(store.book, days: days) : []
        let gap = gaps.first { $0.id == gapID }
        GeometryReader { geo in
            let rightWidth = duo.rightPageWidth(in: geo.frame(in: .global))
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    pageBar
                    if filling {
                        GapList(items: gaps, today: store.today, selected: $gapID) { anchor = $0.day }
                    } else {
                        MonthGridView(mode: mode, days: days, selectedDay: anchor,
                                      highlightStaffID: focus.staffID,
                                      onPickCell: { _, d in anchor = d }) { d in
                            // 日付を押したら、日の表示に切り替えずに右のページだけ変える
                            anchor = d
                        }
                        // 左のページは iPhone くらいの幅なので、iPhone と同じ詰めた表にする
                        .environment(\.horizontalSizeClass, .compact)
                    }
                }
                .frame(width: max(0, geo.size.width - rightWidth))

                Group {
                    if filling {
                        GapPanel(item: gap, hasPlan: !store.book.staffing.isEmpty, isEmpty: gaps.isEmpty)
                    } else {
                        DuoDayPage(day: $anchor)
                    }
                }
                .frame(width: rightWidth)
                .overlay(alignment: .leading) { Rectangle().fill(Color(.separator)).frame(width: 0.5) }
            }
        }
        // 「人が足りない」に切り替えた・月を変えたら、いちばん上の行（選んでいる日があればその日）を選ぶ
        .onChange(of: gaps.map(\.id)) { pickGap(gaps) }
        .onAppear {
            pickGap(gaps)
            // 画面確認用（-demoSpreadFocus）：閉じた画面で2人目を見ていたことにする
            if DemoMode.flag("-demoSpreadFocus"), let m = store.book.staff.dropFirst().first {
                DuoFocus.shared.look(staffID: m.id, day: anchor)
            }
            if DemoMode.flag("-demoSpreadFill") { page = .fill }
        }
    }

    private func pickGap(_ gaps: [ShortageItem]) {
        guard !gaps.contains(where: { $0.id == gapID }) else { return }
        gapID = (gaps.first { $0.day == anchor } ?? gaps.first)?.id
    }

    /// 左のページの上：表／人が足りない・掲示
    private var pageBar: some View {
        HStack(spacing: DS.gap) {
            if !db.readOnly {
                Picker("左のページ", selection: $page) {
                    Text("表").tag(SpreadPage.table)
                    Text("人が足りない").tag(SpreadPage.fill)
                }
                .segmented(2)
                .frame(maxWidth: 260)
            }
            Spacer(minLength: 0)
            Button { DuoPosting.shared.show(byHinge: false) } label: {
                Label("掲示", systemImage: "rectangle.split.2x1")
            }
            .buttonStyle(.bordered).controlSize(.small)
            .accessibilityHint("今日と明日の出勤を大きく出します")
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// 見開きの左のページ（人が足りない）：足りない日・部門・時間帯の一覧。押すと右のページにその日の入れられる人
private struct GapList: View {
    let items: [ShortageItem]
    let today: DayKey
    @Binding var selected: ShortageItem.ID?
    var onPick: (ShortageItem) -> Void

    var body: some View {
        if items.isEmpty {
            ContentUnavailableView("人は足りています", systemImage: "checkmark.circle",
                                   description: Text("この期間に、必要な人数より少ない時間はありません。"))
        } else {
            List(items) { item in
                Button {
                    selected = item.id
                    onPick(item)
                } label: { row(item) }
                .buttonStyle(.plain)
                .listRowBackground(item.id == selected ? Color.accentColor.opacity(0.14) : Color(.systemBackground))
            }
            .listStyle(.plain)
        }
    }

    private func row(_ item: ShortageItem) -> some View {
        let past = item.day < today
        return HStack(spacing: 10) {
            Text(HomeView.dayLabel(item.day)).appFont(.subheadline.weight(.bold)).monospacedDigit()
                .frame(width: 84, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Circle().fill(PaletteColor.fg(item.department.colorIndex)).frame(width: 8, height: 8)
                    Text(item.department.name).appFont(.subheadline).lineLimit(1)
                }
                Text(item.hoursLabel).appFont(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(2)
            }
            Spacer(minLength: 0)
            Text("−\(item.short)").appFont(.subheadline.weight(.heavy)).monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(StaffingStyle.short, in: RoundedRectangle(cornerRadius: DS.chipRadius))
                .accessibilityLabel("\(item.short)人時間足りない")
                // 折り目のすぐ左なので、少し離す
                .padding(.trailing, 8)
        }
        .opacity(past ? 0.5 : 1)
        .contentShape(Rectangle())
    }
}

/// 見開きの右のページ（人が足りない）：選んだ日・部門に入れられる人。押すと勤務が入る
private struct GapPanel: View {
    let item: ShortageItem?
    let hasPlan: Bool
    let isEmpty: Bool

    @Environment(\.shiftStore) private var store

    var body: some View {
        if !hasPlan {
            ContentUnavailableView("必要な人数が決まっていません", systemImage: "person.3",
                                   description: Text("集計 → 適正人員 で時間帯ごとの必要な人数を決めると、足りない日がここに並びます。"))
        } else if let item {
            VStack(spacing: 0) {
                HStack {
                    Text("\(HomeView.dayLabel(item.day)) \(item.department.name)に入れられる人")
                        .appFont(.headline).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.bar)
                .overlay(alignment: .bottom) { Divider() }
                if !store.editing {
                    HStack(spacing: 10) {
                        Image(systemName: "lock.fill").foregroundStyle(.secondary)
                        Text("ロック中のため、勤務は入れられません").appFont(.subheadline)
                        Spacer(minLength: 0)
                        Button("編集する") { store.editing = true }.buttonStyle(.borderedProminent).controlSize(.small)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.yellow.opacity(0.12))
                    .overlay(alignment: .bottom) { Divider() }
                }
                CandidatesList(target: item.target)
                    .id(item.id)
                    .disabled(!store.editing)
            }
        } else if isEmpty {
            ContentUnavailableView("入れる人を探す日はありません", systemImage: "checkmark.circle")
        } else {
            ContentUnavailableView("左で日を選んでください", systemImage: "hand.point.left")
        }
    }
}

/// 見開きの右のページ：日の見出し（前後の日へ）・見ていた人の今月・その日のタイムライン
struct DuoDayPage: View {
    @Binding var day: DayKey

    @Environment(\.shiftStore) private var store

    var body: some View {
        let focus = DuoFocus.shared
        VStack(spacing: 0) {
            header
            if let id = focus.staffID, let m = store.book.staff.first(where: { $0.id == id }) {
                personStrip(m)
            }
            DayTimelineView(day: day, highlightStaffID: focus.staffID)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button { day = day.adding(days: -1) } label: { Image(systemName: "chevron.left").frame(width: 32, height: 32) }
                .accessibilityLabel("前の日")
            Text(GridMode.day.title(around: day))
                .appFont(.headline).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
            Button { day = day.adding(days: 1) } label: { Image(systemName: "chevron.right").frame(width: 32, height: 32) }
                .accessibilityLabel("次の日")
            Spacer(minLength: 0)
            if day != store.today {
                Button("今日") { day = store.today }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    /// 見ていた人のこの月（出勤・時間・休み）。× で印を消す
    private func personStrip(_ m: StaffMember) -> some View {
        let book = store.book
        let month = MonthKey(day)
        let s = MonthSummary.of(m, month: month, in: book)
        let color = book.departments.first { $0.id == m.departmentID }?.colorIndex ?? 8
        return HStack(spacing: 10) {
            InitialAvatar(name: m.name, colorIndex: color, size: 28, photo: m.photo)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.name).appFont(.subheadline.weight(.bold)).lineLimit(1)
                Text("\(month.month)月 出勤\(s.workDays)日・\(String(format: "%.1f", s.hours))時間・休み\(s.offDays)日")
                    .appFont(.caption).foregroundStyle(.secondary).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            Button { DuoFocus.shared.clearStaff() } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(m.name)さんの印を消す")
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
    }
}

// MARK: - 立てて掲示（案4）

/// 掲示の画面を出しているか。半分開いて立てたとき（自動）と、見開きの「掲示」ボタンで出す
@Observable @MainActor
final class DuoPosting {
    static let shared = DuoPosting()

    private(set) var shown = false
    /// 半分開いたので自動で出した（開ききったら自動で閉じる）
    private(set) var byHinge = false

    func show(byHinge: Bool) {
        self.byHinge = byHinge
        shown = true
    }

    func hide() {
        shown = false
        byHinge = false
    }

    /// 半分開いてから掲示にするまで待つ時間（開け閉めの途中で一瞬だけ半分開きになるのを無視する）
    static let settle: Duration = .seconds(2)
}

/// 掲示の画面：左のページに今日、右のページに明日の出勤を大きく出す（朝礼・バックヤードに立てておく）。
/// 出している間は画面が暗くならない
struct PostedBoard: View {
    @Environment(\.duo) private var duo
    @Environment(\.shiftStore) private var store
    /// 半分開いて立てたら自動で掲示にする（端末ごとに覚える）
    @AppStorage("duoAutoPost") private var autoPost = true

    var body: some View {
        let today = store.today
        GeometryReader { geo in
            let rightWidth = duo.spread ? duo.rightPageWidth(in: geo.frame(in: .global)) : geo.size.width / 2
            HStack(spacing: 0) {
                page(today, title: "今日").frame(width: max(0, geo.size.width - rightWidth))
                page(today.adding(days: 1), title: "明日").frame(width: rightWidth)
                    .overlay(alignment: .leading) { Rectangle().fill(Color(.separator)).frame(width: 0.5) }
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var footer: some View {
        HStack(spacing: DS.gap) {
            Toggle("半分開いて立てたら自動で出す", isOn: $autoPost)
                .appFont(.footnote).fixedSize()
            Spacer(minLength: 0)
            Button { DuoPosting.shared.hide() } label: { Label("掲示をやめる", systemImage: "xmark") }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, DS.page).padding(.vertical, 8)
        .background(.bar)
    }

    private func page(_ d: DayKey, title: String) -> some View {
        let r = Self.roster(store.book, on: d)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title).appFont(.largeTitle.weight(.heavy))
                Text(HomeView.dayLabel(d)).appFont(.title2.weight(.bold)).foregroundStyle(.secondary).monospacedDigit()
                Spacer(minLength: 0)
                Text("\(r.working.count)人").appFont(.title2.weight(.bold)).monospacedDigit()
            }
            .padding(.horizontal, DS.page).padding(.top, DS.page).padding(.bottom, 8)
            Divider()
            if r.working.isEmpty {
                ContentUnavailableView("出勤はありません", systemImage: "moon.zzz")
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(r.working) { w in
                            row(w)
                            Divider().padding(.leading, DS.page)
                        }
                    }
                }
            }
            if !r.off.isEmpty {
                Text("休み：" + r.off.joined(separator: "・"))
                    .appFont(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    .padding(.horizontal, DS.page).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func row(_ w: HomeInfo.Working) -> some View {
        HStack(spacing: 12) {
            InitialAvatar(name: w.member.name, colorIndex: w.department?.colorIndex ?? 8, size: 40, photo: w.member.photo)
            VStack(alignment: .leading, spacing: 2) {
                Text(w.member.name).appFont(.title2.weight(.bold)).lineLimit(1).minimumScaleFactor(0.6)
                HStack(spacing: 6) {
                    // 勤務の記号は名前の下に置き、右の時間を削らない
                    if let b = w.block {
                        Text(b.label).appFont(.caption.weight(.bold))
                            .foregroundStyle(PaletteColor.fg(b.colorIndex))
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(PaletteColor.bg(b.colorIndex), in: Capsule())
                            .fixedSize()
                    }
                    Text(w.department?.name ?? "").appFont(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            Spacer(minLength: 8)
            Text("\(w.shift.inTime)〜\(w.shift.outTime)").appFont(.title3.weight(.semibold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.5)
                .layoutPriority(1)
        }
        .padding(.horizontal, DS.page).padding(.vertical, 10)
    }

    /// その日の出勤（出勤の早い順）と休みの人の名前
    static func roster(_ book: ShiftBook, on d: DayKey) -> (working: [HomeInfo.Working], off: [String]) {
        let working = HomeInfo(book: book, today: d).working
        let members = book.staffByDepartment(visibleIn: MonthKey(d)).flatMap(\.members)
        let off = members.filter { m in
            guard !m.hasLeft(on: d), let r = Schedule.resolve(m, on: d, in: book) else { return false }
            return r.isOff
        }.map(\.name)
        return (working, off)
    }
}
