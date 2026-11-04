import SwiftUI

// MARK: - 時間帯別在籍人数の行・不足の行を、部品を並べずに1枚の絵として描く
// 時間帯別を開くと「24時間 × 日数 × 部門」のマスが一度に増える（2部門・1か月で約 1,500 マス）。
// マスを部品で並べると、古い iPad では開いたまま月を切り替えると 3 秒ほどかかっていたので、
// マスの表（MonthRowCanvas）と同じく 1 行を Canvas 1 枚で描く。見た目は以前の部品と同じ。

/// 時間帯別在籍人数の1行（その時間に勤務している人数。必要人数があれば「実際/必要」を色で）
struct HourRowCanvas: View {
    struct Cell {
        var day: DayKey
        var count: Int
        /// 必要人数（決めていない時間は nil）
        var need: Int?
    }

    let hour: Int
    let cells: [Cell]
    let cellWidth: CGFloat
    let rowHeight: CGFloat
    /// 読み上げ（VoiceOver）で、足りない時間を押したとき
    var onShort: (DayKey) -> Void = { _ in }

    @Environment(\.appZoom) private var zoom

    var body: some View {
        let night = hour <= 8
        Canvas { ctx, _ in
            for (i, c) in cells.enumerated() {
                let rect = CGRect(x: CGFloat(i) * cellWidth, y: 0, width: cellWidth, height: rowHeight)
                draw(c, night: night, in: rect, ctx: ctx)
            }
        }
        .frame(width: cellWidth * CGFloat(cells.count), height: rowHeight)
        .accessibilityElement(children: .contain)
        .accessibilityChildren {
            HStack(spacing: 0) {
                ForEach(cells.indices, id: \.self) { i in
                    let c = cells[i]
                    Color.clear
                        .frame(width: cellWidth, height: rowHeight)
                        .accessibilityElement()
                        .accessibilityLabel(c.need.map { "\(c.day.day)日 \(hour)時 \(c.count)人（必要\($0)人）" }
                                            ?? "\(c.day.day)日 \(hour)時 \(c.count)人")
                        .accessibilityAddTraits(c.need.map { c.count < $0 } == true ? .isButton : [])
                        .accessibilityAction { if let need = c.need, c.count < need { onShort(c.day) } }
                }
            }
        }
    }

    private func draw(_ c: Cell, night: Bool, in rect: CGRect, ctx: GraphicsContext) {
        let n = c.count
        if let need = c.need, let color = StaffingStyle.color(n, need: need) {
            // 必要人数がある時間：実際/必要 を色で（足りない＝赤、多い＝オレンジ）
            ctx.fill(Path(rect), with: .color(n < need ? color.opacity(0.85) : color.opacity(0.15)))
            let fg = n < need ? Color.white : color
            let t = ctx.resolve(
                Text("\(n)").font(AppFont.system(size: 12, weight: .heavy).font(zoom: zoom)).foregroundStyle(fg)
                + Text("/\(need)").font(AppFont.system(size: 8).font(zoom: zoom)).foregroundStyle(Color(.secondaryLabel))
            )
            ctx.draw(t, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
        } else {
            if n > 0 {
                ctx.fill(Path(rect), with: .color(night ? Color.blue.opacity(0.15) : Color.green.opacity(0.15)))
            }
            let weight: Font.Weight = n > 2 ? .heavy : n > 0 ? .bold : .regular
            let fg: Color = n == 0 ? Color(.tertiaryLabel) : night ? .blue : .green
            let t = ctx.resolve(Text("\(n)").font(AppFont.system(size: n > 2 ? 13 : 11, weight: weight).font(zoom: zoom))
                .monospacedDigit().foregroundStyle(fg))
            ctx.draw(t, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
        }
        // 右の区切り線
        ctx.fill(Path(CGRect(x: rect.maxX - 0.5, y: rect.minY, width: 0.5, height: rect.height)), with: .color(Color(.separator)))
    }
}

/// 時間帯別の見出しの行（必要人数を決めている部門）：日ごとの不足（人×時間）の札、足りていればチェック
struct ShortRowCanvas: View {
    struct Cell {
        var day: DayKey
        /// 足りない人×時間（0 は足りている）
        var short: Int
    }

    let departmentName: String
    let cells: [Cell]
    let cellWidth: CGFloat
    let rowHeight: CGFloat
    /// 読み上げで、不足の札を押したとき
    var onShort: (DayKey) -> Void = { _ in }

    @Environment(\.appZoom) private var zoom

    var body: some View {
        Canvas { ctx, _ in
            for (i, c) in cells.enumerated() {
                let rect = CGRect(x: CGFloat(i) * cellWidth, y: 0, width: cellWidth, height: rowHeight)
                draw(c, in: rect, ctx: ctx)
            }
        }
        .frame(width: cellWidth * CGFloat(cells.count), height: rowHeight)
        .accessibilityElement(children: .contain)
        .accessibilityChildren {
            HStack(spacing: 0) {
                ForEach(cells.indices, id: \.self) { i in
                    let c = cells[i]
                    Color.clear
                        .frame(width: cellWidth, height: rowHeight)
                        .accessibilityElement()
                        .accessibilityLabel(c.short > 0 ? "\(c.day.day)日 \(departmentName) 不足 \(c.short)人時。入れられる人を見る"
                                                         : "\(c.day.day)日 \(departmentName) 足りている")
                        .accessibilityAddTraits(c.short > 0 ? .isButton : [])
                        .accessibilityAction { if c.short > 0 { onShort(c.day) } }
                }
            }
        }
    }

    private func draw(_ c: Cell, in rect: CGRect, ctx: GraphicsContext) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        if c.short > 0 {
            let t = ctx.resolve(Text("−\(c.short)").font(AppFont.system(size: 11, weight: .heavy).font(zoom: zoom))
                .monospacedDigit().foregroundStyle(.white))
            let s = t.measure(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity))
            let box = CGRect(x: center.x - s.width / 2 - 4, y: center.y - s.height / 2 - 3, width: s.width + 8, height: s.height + 6)
            ctx.fill(Path(roundedRect: box, cornerRadius: 4), with: .color(StaffingStyle.short))
            ctx.draw(t, at: center, anchor: .center)
        } else {
            let t = ctx.resolve(Text(Image(systemName: "checkmark")).font(AppFont.system(size: 9, weight: .bold).font(zoom: zoom))
                .foregroundStyle(StaffingStyle.ok.opacity(0.7)))
            ctx.draw(t, at: center, anchor: .center)
        }
    }
}
