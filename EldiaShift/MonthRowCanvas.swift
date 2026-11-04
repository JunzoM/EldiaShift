import SwiftUI
import UIKit

// MARK: - 月の表の1行（1人×その月の日数）を、部品を並べずに1枚の絵として描く
// マスを部品（背景・チップ・文字・印・線）の組み合わせで描くと、月の表では 1 画面に 7,000 個を超える部品になり、
// iPad（第6世代）など古い端末では月を切り替えるたびに十数秒かかっていた。
// 週の表（large）も同じ部品で描く。見た目は以前のマス（ShiftCellView）の月表示・週表示と同じにする。

struct MonthRowCanvas: View {
    /// 1マス分の中身
    struct Cell {
        var day: DayKey
        /// 退職したあとの日
        var left: Bool
        var resolved: ResolvedShift?
        var block: TimeBlock?
        /// ほかの店舗で勤務する日の店舗と、その略称
        var awayStore: Store?
        var awayLabel: String
        var isToday: Bool
        var issues: [LaborIssue]
        var requested: Bool
        var picked: Bool
        /// 実働時間（週の表で出す）
        var hours: Double? = nil
    }

    let name: String
    let cells: [Cell]
    let cellWidth: CGFloat
    let rowHeight: CGFloat
    /// 週の表（マスが大きい）：時刻を大きく、ひな形の名前と勤務時間も出す
    var large = false
    /// iPhone（幅が狭い）：週の表で出勤・退勤を2行にする
    var compact = false
    /// 読み上げ（VoiceOver）でマスを押したとき
    var onActivate: (DayKey) -> Void = { _ in }

    /// 文字の倍率（表の倍率と同じ。MonthGridView が入れる）
    @Environment(\.appZoom) private var zoom

    var body: some View {
        Canvas { ctx, _ in
            for (i, c) in cells.enumerated() {
                let rect = CGRect(x: CGFloat(i) * cellWidth, y: 0, width: cellWidth, height: rowHeight)
                draw(c, in: rect, ctx: ctx)
            }
        }
        .frame(width: cellWidth * CGFloat(cells.count), height: rowHeight)
        // 読み上げ用には、マスごとの要素を用意する（絵の上に重ねる見えない部品。読み上げが動いているときだけ使われる）
        .accessibilityElement(children: .contain)
        .accessibilityChildren {
            HStack(spacing: 0) {
                ForEach(cells.indices, id: \.self) { i in
                    Color.clear
                        .frame(width: cellWidth, height: rowHeight)
                        .accessibilityElement()
                        .accessibilityLabel(Self.accessibilityText(cells[i], name: name))
                        .accessibilityAddTraits(cells[i].picked ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction { onActivate(cells[i].day) }
                }
            }
        }
    }

    // MARK: 1マスを描く

    private func draw(_ c: Cell, in rect: CGRect, ctx: GraphicsContext) {
        var ctx = ctx
        ctx.clip(to: Path(rect))

        // 背景
        ctx.fill(Path(rect), with: .color(background(c)))
        if !c.left, c.resolved?.elsewhere == true { drawHatch(in: rect, ctx: ctx) }

        // 中身
        if c.left {
            drawText(Text("－").font(AppFont.caption2.font(zoom: zoom)).foregroundStyle(Color(.tertiaryLabel)),
                     center: CGPoint(x: rect.midX, y: rect.midY), maxWidth: rect.width, ctx: ctx)
        } else if let r = c.resolved, r.elsewhere {
            drawElsewhere(r, c, in: rect, ctx: ctx)
        } else if large, let r = c.resolved {
            drawLarge(r, c, in: rect, ctx: ctx)
        } else if let r = c.resolved {
            let chipColor = c.block?.colorIndex ?? 8
            if r.isOff {
                let label = c.block.map(ShiftChip.label) ?? "休み"
                let chipH = chipHeight(label)
                drawChip(label, colorIndex: chipColor,
                         in: CGRect(x: rect.minX + 4, y: rect.midY - chipH / 2, width: rect.width - 8, height: chipH), ctx: ctx)
            } else {
                // チップと、その下に短い時刻（ひな形のままでない日は時刻をチップに）
                let template = c.block.map { $0.inTime == r.inTime && $0.outTime == r.outTime } ?? false
                let chipText = template ? ShiftChip.label(c.block!) : (r.inTime.isEmpty ? "—" : r.inTime)
                let small = template ? "\(ShortTime.compact(r.inTime))-\(ShortTime.compact(r.outTime))" : "〜\(r.outTime)"
                let smallText = Text(small).font(AppFont.system(size: 9).font(zoom: zoom)).monospacedDigit()
                    .foregroundStyle(Color(.secondaryLabel))
                let resolvedSmall = ctx.resolve(smallText)
                let smallH = resolvedSmall.measure(in: CGSize(width: CGFloat.infinity, height: rect.height)).height
                let chipH = chipHeight(chipText)
                let top = rect.midY - (chipH + 2 + smallH) / 2
                drawChip(chipText, colorIndex: chipColor,
                         in: CGRect(x: rect.minX + 4, y: top, width: rect.width - 8, height: chipH), ctx: ctx)
                drawResolved(resolvedSmall, center: CGPoint(x: rect.midX, y: top + chipH + 2 + smallH / 2),
                             maxWidth: rect.width - 8, minScale: template ? 1 : 0.8, ctx: ctx)
            }
        }

        // 右の区切り線
        ctx.fill(Path(CGRect(x: rect.maxX - 0.5, y: rect.minY, width: 0.5, height: rect.height)), with: .color(Color(.separator)))

        // 印
        drawMarks(c, in: rect, ctx: ctx)
    }

    private func background(_ c: Cell) -> Color {
        if c.left || c.resolved?.elsewhere == true { return Color(.secondarySystemBackground) }
        // 週の表の休み：休みの種類の色で塗る
        if large, c.resolved?.isOff == true { return PaletteColor.bg(c.block?.colorIndex ?? 8) }
        if c.isToday { return Color.accentColor.opacity(0.10) }
        if c.day.weekday == 0 || JapaneseHolidays.isHoliday(c.day) { return Color.red.opacity(0.04) }
        if c.day.weekday == 6 { return Color.blue.opacity(0.04) }
        return Color(.systemBackground)
    }

    /// ほかの店舗で勤務する日の斜線（ElsewhereHatch と同じ）
    private func drawHatch(in rect: CGRect, ctx: GraphicsContext) {
        var p = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            p.move(to: CGPoint(x: x, y: rect.maxY))
            p.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += 7
        }
        var c = ctx
        c.opacity = 0.5
        c.stroke(p, with: .color(Color(.separator)), lineWidth: 1)
    }

    /// ほかの店舗：店舗の略称の札と、出勤の時刻
    private func drawElsewhere(_ r: ResolvedShift, _ c: Cell, in rect: CGRect, ctx: GraphicsContext) {
        let time = ctx.resolve(Text(r.inTime.isEmpty ? "—" : r.inTime).font(AppFont.system(size: large ? 12 : 10).font(zoom: zoom))
            .monospacedDigit().foregroundStyle(Color(.secondaryLabel)))
        // 週の表は退勤の時刻も出す
        let out = large ? ctx.resolve(Text(r.outTime).font(AppFont.system(size: 11).font(zoom: zoom))
            .monospacedDigit().foregroundStyle(Color(.tertiaryLabel))) : nil
        let outH = out.map { $0.measure(in: CGSize(width: CGFloat.infinity, height: rect.height)).height + 2 } ?? 0
        let timeH = time.measure(in: CGSize(width: CGFloat.infinity, height: rect.height)).height
        var tagH: CGFloat = 0
        var tag: GraphicsContext.ResolvedText?
        var tagSize = CGSize.zero
        if let st = c.awayStore {
            let t = ctx.resolve(Text(c.awayLabel).font(AppFont.system(size: large ? 11 : 9, weight: .heavy).font(zoom: zoom))
                .foregroundStyle(PaletteColor.fg(st.colorIndex)))
            tagSize = t.measure(in: CGSize(width: rect.width - 8, height: rect.height))
            tagH = tagSize.height + 2
            tag = t
        }
        let total = tagH + (tag == nil ? 0 : 2) + timeH + outH
        var y = rect.midY - total / 2
        if let tag, let st = c.awayStore {
            let w = min(tagSize.width + 6, rect.width - 4)
            let box = CGRect(x: rect.midX - w / 2, y: y, width: w, height: tagH)
            ctx.fill(Path(roundedRect: box, cornerRadius: 3), with: .color(PaletteColor.bg(st.colorIndex)))
            drawResolved(tag, center: CGPoint(x: box.midX, y: box.midY), maxWidth: w - 6, minScale: 0.7, ctx: ctx)
            y += tagH + 2
        }
        drawResolved(time, center: CGPoint(x: rect.midX, y: y + timeH / 2), maxWidth: rect.width - 4, minScale: 0.7, ctx: ctx)
        if let out {
            drawResolved(out, center: CGPoint(x: rect.midX, y: y + timeH + outH / 2 + 1), maxWidth: rect.width - 4, minScale: 0.7, ctx: ctx)
        }
    }

    // MARK: 週の表のマス

    /// 週の表：休みは種類の名前を大きく。勤務は時刻を大きく、その下にひな形の名前と勤務時間
    private func drawLarge(_ r: ResolvedShift, _ c: Cell, in rect: CGRect, ctx: GraphicsContext) {
        let maxW = rect.width - 4
        if r.isOff {
            let t = ctx.resolve(Text(c.block?.label ?? "休み").font(AppFont.headline.font(zoom: zoom))
                .foregroundStyle(PaletteColor.fg(c.block?.colorIndex ?? 8)))
            drawResolved(t, center: CGPoint(x: rect.midX, y: rect.midY), maxWidth: maxW, minScale: 0.7, ctx: ctx)
            return
        }
        let inT = r.inTime.isEmpty ? "—" : r.inTime
        let outT = r.outTime.isEmpty ? "—" : r.outTime
        var lines: [GraphicsContext.ResolvedText] = []
        if compact {
            // iPhone は幅が狭いので、出勤・退勤を2行に
            lines.append(ctx.resolve(Text(inT).font(AppFont.system(size: 13, weight: .bold).font(zoom: zoom)).monospacedDigit()
                .foregroundStyle(Color(.label))))
            lines.append(ctx.resolve(Text(outT).font(AppFont.system(size: 13).font(zoom: zoom)).monospacedDigit()
                .foregroundStyle(Color(.secondaryLabel))))
        } else {
            lines.append(ctx.resolve(Text("\(inT)〜\(outT)").font(AppFont.system(size: 14, weight: .bold).font(zoom: zoom))
                .monospacedDigit().foregroundStyle(Color(.label))))
        }
        // ひな形の名前と勤務時間（1行）
        var info = Text("")
        var hasInfo = false
        if let b = c.block {
            info = Text(b.label).bold().foregroundStyle(PaletteColor.fg(b.colorIndex))
            hasInfo = true
        }
        if let h = c.hours {
            let ht = Text(String(format: "%.1fh", h)).foregroundStyle(Color(.secondaryLabel))
            info = hasInfo ? info + Text(" ") + ht : ht
            hasInfo = true
        }
        if hasInfo {
            lines.append(ctx.resolve(info.font(AppFont.caption2.font(zoom: zoom)).monospacedDigit()))
        }
        let sizes = lines.map { $0.measure(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity)) }
        let total = sizes.reduce(0) { $0 + $1.height } + CGFloat(max(0, lines.count - 1)) * 2
        var y = rect.midY - total / 2
        for (t, sz) in zip(lines, sizes) {
            drawResolved(t, center: CGPoint(x: rect.midX, y: y + sz.height / 2), maxWidth: maxW, minScale: 0.7, ctx: ctx)
            y += sz.height + 2
        }
    }

    // MARK: チップ（ShiftChip と同じ見た目）

    private func chipFont() -> Font { AppFont.system(size: 11, weight: .bold).font(zoom: zoom) }

    private func chipHeight(_ text: String) -> CGFloat {
        // ShiftChip：高さ 22（倍率をかける）。文字が高いときは文字に合わせる
        max(22 * zoom, UIFont.systemFont(ofSize: 11 * zoom, weight: .bold).lineHeight + 4)
    }

    private func drawChip(_ text: String, colorIndex: Int, in box: CGRect, ctx: GraphicsContext) {
        let shape = Path(roundedRect: box, cornerRadius: DS.chipRadius, style: .continuous)
        ctx.fill(shape, with: .color(PaletteColor.bg(colorIndex)))
        let inset = Path(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), cornerRadius: DS.chipRadius - 0.5, style: .continuous)
        ctx.stroke(inset, with: .color(PaletteColor.fg(colorIndex).opacity(0.22)), lineWidth: 1)
        let t = ctx.resolve(Text(text).font(chipFont()).monospacedDigit().foregroundStyle(PaletteColor.fg(colorIndex)))
        // 2文字まで（早番・公休など）は縮めない。長いときだけ 0.6 倍まで縮める（ShiftChip と同じ）
        drawResolved(t, center: CGPoint(x: box.midX, y: box.midY), maxWidth: box.width - 10,
                     minScale: text.count <= 2 ? 1 : 0.6, ctx: ctx)
    }

    // MARK: 印（CellMarks の月表示と同じ）

    private func drawMarks(_ c: Cell, in rect: CGRect, ctx: GraphicsContext) {
        if c.picked {
            ctx.fill(Path(rect), with: .color(Color.accentColor.opacity(0.18)))
            ctx.stroke(Path(rect.insetBy(dx: 1.25, dy: 1.25)), with: .color(Color.accentColor), lineWidth: 2.5)
        }
        if c.resolved?.isAuto == true {
            // 自動（くり返し・期間の予定）で決まったマスの印
            // 時刻に重ならないよう隅に小さく（週の表は右下、月の表は右上）
            let pad: CGFloat = large ? 5 : 2
            let d = large ? CGRect(x: rect.maxX - pad - 5, y: rect.maxY - pad - 5, width: 5, height: 5)
                          : CGRect(x: rect.maxX - pad - 5, y: rect.minY + pad, width: 5, height: 5)
            ctx.fill(Path(ellipseIn: d), with: .color(Color.orange.opacity(0.8)))
        }
        if c.resolved?.note?.isEmpty == false {
            // メモがある日の印
            // メモがある日の印（自動の印と重ならない隅に：週の表は右上、月の表は右下）
            let t = ctx.resolve(Text(Image(systemName: "note.text")).font(AppFont.system(size: large ? 10 : 7, weight: .bold).font(zoom: zoom))
                .foregroundStyle(Color(.secondaryLabel)))
            let s = t.measure(in: rect.size)
            let pad: CGFloat = large ? 4 : 1.5
            let y = large ? rect.minY + pad + s.height / 2 : rect.maxY - pad - s.height / 2
            ctx.draw(t, at: CGPoint(x: rect.maxX - pad - s.width / 2, y: y), anchor: .center)
        }
        if !c.issues.isEmpty {
            let color = c.issues.contains(.requestedOff) ? Color.purple : Color.orange
            let t = ctx.resolve(Text(Image(systemName: "exclamationmark.triangle.fill"))
                .font(AppFont.system(size: large ? 11 : 9).font(zoom: zoom)).foregroundStyle(color))
            let s = t.measure(in: rect.size)
            ctx.draw(t, at: CGPoint(x: rect.minX + 2 + s.width / 2, y: rect.minY + 2 + s.height / 2), anchor: .center)
        }
        if c.requested {
            let t = ctx.resolve(Text("希").font(AppFont.system(size: 8, weight: .heavy).font(zoom: zoom)).foregroundStyle(.white))
            let s = t.measure(in: rect.size)
            let box = CGRect(x: rect.minX + 2, y: rect.maxY - 2 - s.height, width: s.width + 4, height: s.height)
            ctx.fill(Path(roundedRect: box, cornerRadius: 2), with: .color(.purple))
            ctx.draw(t, at: CGPoint(x: box.midX, y: box.midY), anchor: .center)
        }
    }

    // MARK: 文字

    private func drawText(_ text: Text, center: CGPoint, maxWidth: CGFloat, minScale: CGFloat = 1, ctx: GraphicsContext) {
        drawResolved(ctx.resolve(text), center: center, maxWidth: maxWidth, minScale: minScale, ctx: ctx)
    }

    /// 幅に入りきらないときは minScale まで縮める（それでも入らなければ、マスの外は切れる）
    private func drawResolved(_ t: GraphicsContext.ResolvedText, center: CGPoint, maxWidth: CGFloat, minScale: CGFloat,
                              ctx: GraphicsContext) {
        let size = t.measure(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity))
        guard size.width > maxWidth, maxWidth > 0, minScale < 1 else {
            ctx.draw(t, at: center, anchor: .center)
            return
        }
        var c = ctx
        let k = max(minScale, maxWidth / size.width)
        c.translateBy(x: center.x, y: center.y)
        c.scaleBy(x: k, y: k)
        c.draw(t, at: .zero, anchor: .center)
    }

    // MARK: 読み上げ

    static func accessibilityText(_ c: Cell, name: String) -> String {
        let date = "\(c.day.month)月\(c.day.day)日 \(name)"
        let base: String
        if c.left {
            base = "\(date)、退職後"
        } else if let r = c.resolved {
            if r.isOff { base = "\(date)、\(c.block?.label ?? "休み")" }
            else if r.elsewhere { base = "\(date)、\(c.awayStore?.name ?? "ほかの店舗")で\(r.inTime)から\(r.outTime)" }
            else { base = "\(date)、\(r.inTime)から\(r.outTime)\(r.isAuto ? "、自動" : "")" }
        } else {
            base = "\(date)、未定"
        }
        let extra = (c.requested ? "、希望休" : "") + (c.issues.isEmpty ? "" : "、注意：" + c.issues.map(\.text).joined(separator: "、"))
            + (c.resolved?.note.map { "、メモ：\($0)" } ?? "")
        return base + extra
    }
}

// MARK: - まとめて選ぶときの、押す・長押し（押した位置を知るため UIKit で受ける）

/// 月の表の行に重ねる：押した・長押しした横の位置を返す。まとめて選んでいるときだけ重ねる
/// （SwiftUI の長押しは押した位置が分からないため。縦横のスクロールは今までどおり効く）
struct RowTouchCatcher: UIViewRepresentable {
    var onTap: (CGFloat) -> Void
    var onLongPress: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        let long = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.long(_:)))
        long.minimumPressDuration = 0.35
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        tap.require(toFail: long)
        v.addGestureRecognizer(long)
        v.addGestureRecognizer(tap)
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onLongPress = onLongPress
    }

    final class Coordinator: NSObject {
        var onTap: (CGFloat) -> Void = { _ in }
        var onLongPress: (CGFloat) -> Void = { _ in }

        @objc func tap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, let v = g.view else { return }
            onTap(g.location(in: v).x)
        }

        @objc func long(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let v = g.view else { return }
            onLongPress(g.location(in: v).x)
        }
    }
}
