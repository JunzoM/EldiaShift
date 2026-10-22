import SwiftUI
import CoreText

// MARK: - コーチマーク（スポットライト＋手書きの吹き出し）
// 押したボタン（など）のまわりだけを明るく残し、ほかを黒い半透明で覆って目を向けさせる。説明は手書き風の吹き出しで。
// くどくならないよう、次の決まりにしている。
// ・その機能を初めて押したときだけ出す（押していない機能の説明は出さない）
// ・1つの説明は1回だけ。画面のどこかを押すと閉じ、二度と出ない
// ・ふだんから見えている説明文は置かない
// 設定の「操作のヒントをもう一度見る」で、最初の状態に戻せる。

/// 1つの説明
struct CoachStep: Equatable {
    /// 「見た」を覚えておく名前（同じ種類の説明は1回だけ）
    let key: String
    /// 明るく残す部品の名前（.coachTarget で付けた名前）
    let target: String
    let title: String
    let message: String
    /// どの画面に重ねるか（シートの中は別）
    var scope: CoachScope = .main

    static func edit() -> CoachStep {
        CoachStep(key: "edit", target: "edit", title: "編集できるようになりました",
                  message: "マスを押すと勤務を選べます。終わったら、ここをもう一度押すとロックに戻ります。")
    }

    static func timeline(_ target: String) -> CoachStep {
        CoachStep(key: "timeline", target: target, title: "ドラッグで変えられます",
                  message: "バーを左右に動かすと時刻が、両端を動かすと長さが変わります（30分刻み）。空いているところを押すと、8時間のシフトを作ります。")
    }

    static func cellPicker(_ target: String) -> CoachStep {
        CoachStep(key: "cellPicker", target: target, title: "押すとすぐ決まります",
                  message: "ひな形を押すと、この日のシフトになります。ひな形にない時刻は、下の「この日だけ時刻を直接入力」で。",
                  scope: .sheet)
    }

    static func hourly(_ target: String) -> CoachStep {
        CoachStep(key: "hourly", target: target, title: "1時間ごとの人数です",
                  message: "この部門で、その時間に勤務している人数です。夜（0時〜8時）は青、昼は緑で出ます。")
    }

    static func pattern(_ target: String) -> CoachStep {
        CoachStep(key: "pattern", target: target, title: "使うパターンを変えました",
                  message: "この人の自動で入るシフトが、選んだ週間パターンに変わります。パターンを作る・直すときは、名前を長押し。")
    }

    static func summary() -> CoachStep {
        CoachStep(key: "summary", target: "summaryLeave", title: "時間は休憩を引いた実働です",
                  message: "引く休憩は 設定 →「休憩の決まり」で変えられます。有休の残りは、入社日と週間パターンから出しています。")
    }

    static func print() -> CoachStep {
        CoachStep(key: "print", target: "printShare", title: "PDFはLINEやメールで送れます",
                  message: "ここから LINE・メール・AirDrop・ファイルに保存ができます。白黒で印刷しても、土日や有休が見分けられます。",
                  scope: .sheet)
    }

    static func undo() -> CoachStep {
        CoachStep(key: "undo", target: "undo", title: "まちがえたら、ここ",
                  message: "変えた直後の数秒だけ「元に戻す」が出ます。")
    }
}

enum CoachScope: Hashable {
    case main, sheet
}

/// 説明を出す・覚えておく
@MainActor
@Observable
final class CoachCenter {
    static let shared = CoachCenter()

    private(set) var active: CoachStep?
    /// 部品の位置（画面全体の座標）
    @ObservationIgnored private var frames: [String: CGRect] = [:]
    /// 部品の UIKit の部品（ツールバーのボタンは SwiftUI の座標が取れないことがあるので、画面上の位置はこちらから測る）
    @ObservationIgnored private var views: [String: WeakView] = [:]

    private final class WeakView {
        weak var view: UIView?
        init(_ v: UIView) { view = v }
    }

    /// 部品の今の位置（画面全体の座標）
    func frame(of id: String) -> CGRect? {
        if let v = views[id]?.view, let w = v.window {
            let f = v.convert(v.bounds, to: w)
            if f.width > 1, f.height > 1 { return f }
        }
        return frames[id]
    }

    func register(_ id: String, view: UIView) {
        views[id] = WeakView(view)
    }
    /// 位置が変わったら描き直すため
    private(set) var frameVersion = 0

    @ObservationIgnored private let seenKey = "coachSeen"
    @ObservationIgnored private var pending: Task<Void, Never>?

    init() {
        // 画面確認用：毎回まっさらな状態で出す
        if ProcessInfo.processInfo.arguments.contains("-demoCoach") { UserDefaults.standard.removeObject(forKey: seenKey) }
    }

    /// 画面確認・テストでは出さない（-demoCoach のときだけ出す）
    var enabled: Bool {
        if ProcessInfo.processInfo.arguments.contains("-demoCoach") { return true }
        if DemoMode.enabled { return false }
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }

    private var seen: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: seenKey) }
    }

    func hasSeen(_ key: String) -> Bool { seen.contains(key) }

    /// 初めてのときだけ出す。画面が切り替わる・シートが開くのを待ってから（部品の位置が決まってから）出す
    func show(_ step: CoachStep, after delay: Double = 0.45) {
        guard enabled, !hasSeen(step.key), active == nil else { return }
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, self.active == nil, self.frame(of: step.target) != nil else { return }
            self.active = step
            self.seen.insert(step.key)
        }
    }

    func dismiss() {
        active = nil
    }

    /// 「操作のヒントをもう一度見る」
    func resetAll() {
        seen = []
        active = nil
    }

    func report(_ id: String, frame: CGRect) {
        guard frames[id] != frame else { return }
        frames[id] = frame
        if active?.target == id { frameVersion += 1 }
    }

    func remove(_ id: String) {
        frames.removeValue(forKey: id)
        views.removeValue(forKey: id)
        if active?.target == id { active = nil }
    }
}

extension View {
    /// コーチマークで明るく残す部品にする
    func coachTarget(_ id: String) -> some View {
        background {
            GeometryReader { g in
                let f = g.frame(in: .global)
                Color.clear
                    .onAppear { CoachCenter.shared.report(id, frame: f) }
                    .onChange(of: f) { CoachCenter.shared.report(id, frame: f) }
                    .onDisappear { CoachCenter.shared.remove(id) }
            }
            CoachViewMarker(id: id).allowsHitTesting(false)
        }
    }

    /// この画面の上にコーチマークを重ねる
    func coachOverlay(_ scope: CoachScope) -> some View {
        overlay { CoachOverlayHost(scope: scope) }
    }
}

private struct CoachOverlayHost: View {
    let scope: CoachScope
    @State private var center = CoachCenter.shared
    /// この幕の左上（画面全体の座標。UIKit で測る）
    @State private var hostOrigin: CGPoint = .zero

    var body: some View {
        GeometryReader { g in
            if let step = center.active, step.scope == scope, let f = center.frame(of: step.target) {
                let _ = center.frameVersion
                CoachOverlay(step: step, hole: f.offsetBy(dx: -hostOrigin.x, dy: -hostOrigin.y), size: g.size) {
                    withAnimation(.easeOut(duration: 0.2)) { center.dismiss() }
                }
                .transition(.opacity)
            }
        }
        .background(WindowOriginReader(origin: $hostOrigin).allowsHitTesting(false))
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.25), value: center.active)
        .allowsHitTesting(center.active?.scope == scope)
    }
}

/// 暗い幕（穴あき）＋手書きの丸囲み＋手書きの吹き出し
private struct CoachOverlay: View {
    let step: CoachStep
    let hole: CGRect
    let size: CGSize
    let onClose: () -> Void

    @State private var appeared = false

    var body: some View {
        let spot = hole.insetBy(dx: -8, dy: -8)
        let layout = BubbleLayout(spot: spot, area: size, step: step)
        ZStack(alignment: .topLeading) {
            // 暗い幕（明るく残すところだけ穴を開ける）
            Canvas { ctx, s in
                var p = Path(CGRect(origin: .zero, size: s))
                p.addRoundedRect(in: spot, cornerSize: CGSize(width: 12, height: 12))
                ctx.fill(p, with: .color(.black.opacity(0.62)), style: FillStyle(eoFill: true))
                // 手書きの丸囲み（2回なぞったような線）
                for seed in [1, 2] {
                    ctx.stroke(Sketch.roundedRect(spot.insetBy(dx: -3, dy: -3), radius: 14, seed: seed, wobble: 2.2),
                               with: .color(Color(red: 1, green: 0.84, blue: 0.3)), lineWidth: seed == 1 ? 3 : 1.6)
                }
            }

            // 吹き出し
            ZStack(alignment: .topLeading) {
                BubbleShape(layout: layout, seed: 3)
                    .fill(Color(red: 1, green: 0.99, blue: 0.95))
                BubbleShape(layout: layout, seed: 3)
                    .stroke(Color(white: 0.15), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                BubbleShape(layout: layout, seed: 7)
                    .stroke(Color(white: 0.15).opacity(0.45), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                VStack(alignment: .leading, spacing: 6) {
                    Text(step.title).font(HandFont.font(size: 19))
                    Text(step.message).font(HandFont.font(size: 15)).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("どこかを押すと閉じます").font(HandFont.font(size: 11)).foregroundStyle(Color(white: 0.45))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .foregroundStyle(Color(white: 0.12))
                .padding(.horizontal, 18).padding(.vertical, 14)
                .frame(width: layout.bubble.width, height: layout.bubble.height, alignment: .topLeading)
                .offset(x: layout.bubble.minX, y: layout.bubble.minY)
            }
            .scaleEffect(appeared ? 1 : 0.92, anchor: layout.below ? .top : .bottom)
            .opacity(appeared ? 1 : 0)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
        .onAppear { withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { appeared = true } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel("\(step.title)。\(step.message)")
        .accessibilityAction(named: "閉じる", onClose)
    }
}

/// 吹き出しの位置（明るいところの下に入れば下、入らなければ上）
private struct BubbleLayout: Equatable {
    var bubble: CGRect
    var tailBase: CGFloat
    var tailTip: CGPoint
    var below: Bool

    init(spot: CGRect, area: CGSize, step: CoachStep) {
        let width = min(340, area.width - 32)
        let textWidth = width - 36
        func h(_ t: String, _ size: CGFloat, _ spacing: CGFloat = 0) -> CGFloat {
            let f = UIFont(name: HandFont.name, size: size) ?? .systemFont(ofSize: size, weight: .semibold)
            let style = NSMutableParagraphStyle()
            style.lineSpacing = spacing
            return ceil((t as NSString).boundingRect(with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                                                     options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                     attributes: [.font: f, .paragraphStyle: style], context: nil).height)
        }
        let height = 14 + h(step.title, 19) + 6 + h(step.message, 15, 3) + 6 + 16 + 14 + 6
        let gap: CGFloat = 26
        below = spot.maxY + gap + height + 20 < area.height || spot.minY - gap - height < 40
        let x = min(max(16, spot.midX - width / 2), area.width - width - 16)
        let y = below ? spot.maxY + gap : spot.minY - gap - height
        bubble = CGRect(x: x, y: y, width: width, height: height)
        tailBase = min(max(bubble.minX + 34, spot.midX), bubble.maxX - 34)
        tailTip = CGPoint(x: min(max(spot.minX + 12, spot.midX), spot.maxX - 12), y: below ? spot.maxY + 4 : spot.minY - 4)
    }
}

/// 手書き風の吹き出し（角の丸い四角＋しっぽ）
private struct BubbleShape: Shape {
    let layout: BubbleLayout
    let seed: Int

    func path(in rect: CGRect) -> Path {
        let b = layout.bubble
        let edgeY = layout.below ? b.minY : b.maxY
        let half: CGFloat = 13
        // 四角の外周をなぞり、しっぽの付け根のところでしっぽに寄り道する
        var pts = Sketch.roundedRectPoints(b, radius: 18)
        let base1 = CGPoint(x: layout.tailBase - half, y: edgeY)
        let base2 = CGPoint(x: layout.tailBase + half, y: edgeY)
        // 付け根の幅にある辺の点を除き、しっぽ（付け根 → 先 → 付け根）を差し込む。外周は時計回りなので、上の辺は左から右、下の辺は右から左
        let onEdge = { (q: CGPoint) in abs(q.y - edgeY) < 0.5 }
        pts.removeAll { onEdge($0) && $0.x > base1.x - 4 && $0.x < base2.x + 4 }
        let tail = layout.below ? [base1, layout.tailTip, base2] : [base2, layout.tailTip, base1]
        let i = pts.firstIndex { onEdge($0) && (layout.below ? $0.x > base2.x : $0.x < base1.x) }
            ?? pts.indices.min { hypot(pts[$0].x - layout.tailBase, pts[$0].y - edgeY) < hypot(pts[$1].x - layout.tailBase, pts[$1].y - edgeY) }
            ?? 0
        pts.insert(contentsOf: tail, at: i)
        return Sketch.path(through: Sketch.jitter(pts, seed: seed, amount: 1.6), closed: true)
    }
}

/// 部品の場所に置く見えない UIView（画面上の位置を UIKit で測るため）
private struct CoachViewMarker: UIViewRepresentable {
    let id: String

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        CoachCenter.shared.register(id, view: v)
        return v
    }

    func updateUIView(_ v: UIView, context: Context) {
        CoachCenter.shared.register(id, view: v)
    }
}

/// 幕の左上の位置（画面全体の座標）
private struct WindowOriginReader: UIViewRepresentable {
    @Binding var origin: CGPoint

    func makeUIView(context: Context) -> ReaderView {
        let v = ReaderView()
        v.isUserInteractionEnabled = false
        v.onMove = { p in if origin != p { origin = p } }
        return v
    }

    func updateUIView(_ v: ReaderView, context: Context) {
        v.onMove = { p in if origin != p { origin = p } }
    }

    final class ReaderView: UIView {
        var onMove: ((CGPoint) -> Void)?

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        private func report() {
            guard let w = window else { return }
            let p = convert(CGPoint.zero, to: w)
            DispatchQueue.main.async { [weak self] in self?.onMove?(p) }
        }
    }
}

/// 条件つきで .coachTarget を付ける
struct OptionalCoachTarget: ViewModifier {
    let id: String?

    func body(content: Content) -> some View {
        if let id { content.coachTarget(id) } else { content }
    }
}

// MARK: - 手書き風の線

enum Sketch {
    /// 角の丸い四角の外周の点（時計回り）
    static func roundedRectPoints(_ r: CGRect, radius: CGFloat) -> [CGPoint] {
        var pts: [CGPoint] = []
        let rad = min(radius, min(r.width, r.height) / 2)
        func arc(_ c: CGPoint, _ from: CGFloat, _ to: CGFloat) {
            for k in 0...6 {
                let a = from + (to - from) * CGFloat(k) / 6
                pts.append(CGPoint(x: c.x + cos(a) * rad, y: c.y + sin(a) * rad))
            }
        }
        func line(_ a: CGPoint, _ b: CGPoint) {
            let n = max(2, Int(hypot(b.x - a.x, b.y - a.y) / 24))
            for k in 1..<n { pts.append(CGPoint(x: a.x + (b.x - a.x) * CGFloat(k) / CGFloat(n), y: a.y + (b.y - a.y) * CGFloat(k) / CGFloat(n))) }
        }
        arc(CGPoint(x: r.minX + rad, y: r.minY + rad), .pi, .pi * 1.5)
        line(CGPoint(x: r.minX + rad, y: r.minY), CGPoint(x: r.maxX - rad, y: r.minY))
        arc(CGPoint(x: r.maxX - rad, y: r.minY + rad), .pi * 1.5, .pi * 2)
        line(CGPoint(x: r.maxX, y: r.minY + rad), CGPoint(x: r.maxX, y: r.maxY - rad))
        arc(CGPoint(x: r.maxX - rad, y: r.maxY - rad), 0, .pi * 0.5)
        line(CGPoint(x: r.maxX - rad, y: r.maxY), CGPoint(x: r.minX + rad, y: r.maxY))
        arc(CGPoint(x: r.minX + rad, y: r.maxY - rad), .pi * 0.5, .pi)
        line(CGPoint(x: r.minX, y: r.maxY - rad), CGPoint(x: r.minX, y: r.minY + rad))
        return pts
    }

    static func roundedRect(_ r: CGRect, radius: CGFloat, seed: Int, wobble: CGFloat) -> Path {
        var pts = jitter(roundedRectPoints(r, radius: radius), seed: seed, amount: wobble)
        // 手で囲んだように、終わりを少し重ねて閉じない
        if pts.count > 4 { pts.append(contentsOf: pts.prefix(3).map { CGPoint(x: $0.x + 2, y: $0.y - 2) }) }
        return path(through: pts, closed: false)
    }

    /// 決まった揺れ（毎回同じ形になるよう、seed から作る）
    static func jitter(_ pts: [CGPoint], seed: Int, amount: CGFloat) -> [CGPoint] {
        pts.enumerated().map { i, p in
            let a = Double(i) * 1.7 + Double(seed) * 3.1
            return CGPoint(x: p.x + CGFloat(sin(a) * 0.7 + sin(a * 2.3) * 0.3) * amount,
                           y: p.y + CGFloat(cos(a * 1.3) * 0.7 + sin(a * 3.1) * 0.3) * amount)
        }
    }

    /// 点を滑らかにつなぐ
    static func path(through pts: [CGPoint], closed: Bool) -> Path {
        var p = Path()
        guard pts.count > 2 else { return p }
        let mid = { (a: CGPoint, b: CGPoint) in CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        p.move(to: closed ? mid(pts[pts.count - 1], pts[0]) : pts[0])
        for i in 0..<(closed ? pts.count : pts.count - 1) {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            p.addQuadCurve(to: mid(a, b), control: a)
        }
        if closed { p.closeSubpath() } else if let last = pts.last { p.addLine(to: last) }
        return p
    }
}

// MARK: - 手書き風の文字（Klee One。SIL Open Font License 1.1。説明に使う文字だけに絞って入れている）

enum HandFont {
    static let name = "KleeOne-SemiBold"

    static func register() {
        guard let url = Bundle.main.url(forResource: "CoachHand", withExtension: "ttf")
                ?? Bundle.main.url(forResource: "CoachHand", withExtension: "ttf", subdirectory: "Fonts") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    static func font(size: CGFloat) -> Font {
        UIFont(name: name, size: size) != nil ? .custom(name, size: size) : .system(size: size, weight: .semibold, design: .rounded)
    }
}
