import Foundation

/// 日ごとのタイムラインの計算（PC版と同じ範囲・同じ規則）
/// ・表示は朝5:00〜翌10:00、30分刻み（設定で15分刻みにもできる）
/// ・出勤は当日中（〜23:30）、退勤は翌10:00まで。長さは30分〜24時間
enum TimelineMath {
    static let start = 5 * 60
    static let end = 34 * 60
    static let step = 30
    /// 空いているところを押したときの長さ
    static let newLength = 8 * 60

    enum Mode: Equatable {
        case move, left, right
    }

    /// 刻み（30分・15分）にそろえる
    static func snap(_ minutes: Double, step: Int = step) -> Int {
        Int((minutes / Double(step)).rounded()) * step
    }

    /// その日のシフトの位置（分）。退勤が出勤以前なら翌日とみなす
    static func span(of r: ResolvedShift?) -> (inM: Int, outM: Int)? {
        guard let r, !r.isOff, let i = ClockTime.parse(r.inTime), var o = ClockTime.parse(r.outTime) else { return nil }
        if o <= i { o += 1440 }
        return (i, o)
    }

    /// ドラッグした量（分、30分単位）を当てはめた結果
    static func drag(_ mode: Mode, in0: Int, out0: Int, delta: Int, step: Int = step) -> (inM: Int, outM: Int) {
        var inM = in0, outM = out0
        switch mode {
        case .move:
            let len = out0 - in0
            inM = max(min(start, in0), min(1440 - step, in0 + delta))
            outM = inM + len
            if outM > end { outM = end; inM = outM - len }
        case .left:
            inM = max(min(start, in0), min(out0 - step, in0 + delta, 1440 - step))
        case .right:
            outM = max(in0 + step, min(out0 + delta, in0 + 1440, end))
        }
        return (inM, outM)
    }

    /// 空いているところを押したとき：押した時刻から8時間（翌10:00まで）
    static func newSpan(at minutes: Int) -> (inM: Int, outM: Int)? {
        let at = max(start, minutes)
        guard at < 1440 else { return nil }
        return (at, min(at + newLength, end))
    }

    /// 保存する形（日をまたぐ時刻は 0〜24時に戻す）
    static func entry(inM: Int, outM: Int) -> CellEntry {
        CellEntry(inTime: ClockTime.format(inM % 1440), outTime: ClockTime.format(outM % 1440), blockID: nil, isOff: false)
    }

    /// 時間帯ごとの人数（h は 0:00 からの時、5〜33）
    static func headcount(_ spans: [(inM: Int, outM: Int)], hour h: Int) -> Int {
        spans.filter { $0.inM < (h + 1) * 60 && $0.outM > h * 60 }.count
    }

    static func label(_ minutes: Int) -> String {
        let m = minutes % 1440
        return "\(minutes >= 1440 ? "翌" : "")\(m / 60):\(String(format: "%02d", m % 60))"
    }
}
