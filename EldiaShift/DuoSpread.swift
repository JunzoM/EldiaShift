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
    static var demoForced: Bool { DemoMode.flag("-demoSpread") }
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
    var onChange: (DuoInfo) -> Void

    func makeUIView(context: Context) -> HingeProbeView {
        let v = HingeProbeView()
        v.onChange = onChange
        return v
    }

    func updateUIView(_ v: HingeProbeView, context: Context) {
        v.onChange = onChange
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
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func installHinge() {
        // UIHingeInteraction は iOS 27.1 の SDK から（Xcode 26 の CI でもビルドできるよう、古いコンパイラでは入れない）
        #if compiler(>=6.4.1) && !targetEnvironment(macCatalyst)
        if #available(iOS 27.1, *) {
            addInteraction(UIHingeInteraction { [weak self] _, update in
                self?.info.hinge = HingeState(update.hinge)
            })
        }
        #endif
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        measureWindow()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        measureWindow()
    }

    /// 折り目は画面のまん中。窓が画面いっぱいでないとき（ほかのアプリと並べたとき）も合うよう、画面の座標から窓の座標へ直す
    private func measureWindow() {
        guard let w = window else { return }
        let screen = w.windowScene?.screen ?? w.screen
        let mid = CGPoint(x: screen.bounds.midX, y: screen.bounds.midY)
        var next = info
        next.foldX = w.convert(mid, from: screen.coordinateSpace).x
        next.windowWidth = w.bounds.width
        next.landscape = screen.bounds.width > screen.bounds.height
        if DuoInfo.demoForced {
            next.hinge = .fullyOpen
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

/// 開いた Duo のシフト表：左のページに月（週）の表、右のページに選んだ日のタイムライン。
/// 右のページは折り目から始めるので、折り目の上に部品が来ない
struct SpreadBoard: View {
    let mode: GridMode
    @Binding var anchor: DayKey

    @Environment(\.duo) private var duo
    @Environment(\.shiftStore) private var store

    var body: some View {
        let focus = DuoFocus.shared
        GeometryReader { geo in
            let rightWidth = duo.rightPageWidth(in: geo.frame(in: .global))
            HStack(spacing: 0) {
                MonthGridView(mode: mode, days: mode.days(around: anchor), selectedDay: anchor,
                              highlightStaffID: focus.staffID,
                              onPickCell: { _, d in anchor = d }) { d in
                    // 日付を押したら、日の表示に切り替えずに右のページだけ変える
                    anchor = d
                }
                // 左のページは iPhone くらいの幅なので、iPhone と同じ詰めた表にする
                .environment(\.horizontalSizeClass, .compact)
                .frame(width: max(0, geo.size.width - rightWidth))

                DuoDayPage(day: $anchor)
                    .frame(width: rightWidth)
            }
        }
        .onAppear {
            // 画面確認用（-demoSpreadFocus）：閉じた画面で2人目を見ていたことにする
            if DemoMode.flag("-demoSpreadFocus"), let m = store.book.staff.dropFirst().first {
                DuoFocus.shared.look(staffID: m.id, day: anchor)
            }
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
        // 折り目のすぐ右なので、左に線を引いて左右のページを分ける
        .overlay(alignment: .leading) { Rectangle().fill(Color(.separator)).frame(width: 0.5) }
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
