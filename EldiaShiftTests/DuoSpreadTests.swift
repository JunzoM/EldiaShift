import Foundation
import Testing
@testable import EldiaShift

@Suite("Duo：見開きにするか・右のページの幅・開くとつづき")
@MainActor
struct DuoSpreadTests {
    /// 開いた Duo の横向き（951 × 669 ポイント、折り目はまん中）
    private func open(_ hinge: HingeState = .fullyOpen, landscape: Bool = true) -> DuoInfo {
        DuoInfo(hinge: hinge, foldX: 475.5, windowWidth: 951, landscape: landscape)
    }

    @Test func spreadOnlyWhenOpenAndLandscape() {
        #expect(open().spread)
        #expect(open(.partiallyOpen).spread)
        #expect(!open(.closed).spread)
        // Duo 以外（iPhone・iPad・Mac）
        #expect(!open(.none).spread)
        // 開いて縦にしたときは折り目が横に通るので、左右の見開きにしない
        #expect(!open(landscape: false).spread)
    }

    @Test func noSpreadWhenWindowDoesNotCoverBothPages() {
        // ほかのアプリと並べて、窓が折り目の右だけ・左だけのとき
        #expect(!DuoInfo(hinge: .fullyOpen, foldX: -10, windowWidth: 460, landscape: true).spread)
        #expect(!DuoInfo(hinge: .fullyOpen, foldX: 475, windowWidth: 600, landscape: true).spread)
    }

    @Test func rightPageStartsAtFold() {
        let d = open()
        // サイドバー（たたんで 72）の右から窓の右端までが見開きの画面
        #expect(d.rightPageWidth(in: CGRect(x: 72, y: 0, width: 879, height: 600)) == 475.5)
        // 狭すぎるときも、左右に1ページずつは残す
        #expect(d.rightPageWidth(in: CGRect(x: 400, y: 0, width: 551, height: 600)) == 280)
    }

    @Test func continueOnlyRecentLook() {
        let f = DuoFocus()
        #expect(f.dayToContinue() == nil)
        let day = DayKey(2026, 11, 7)
        f.look(staffID: "s1", day: day)
        #expect(f.dayToContinue() == day)
        #expect(f.staffID == "s1")
        // 15分より前に見ていたものは続きにしない
        #expect(f.dayToContinue(now: Date().addingTimeInterval(DuoFocus.keep + 1)) == nil)
        // 日だけ変えても、見ていた人はそのまま
        f.look(day: day.adding(days: 1))
        #expect(f.staffID == "s1")
        #expect(f.dayToContinue() == day.adding(days: 1))
        f.clearStaff()
        #expect(f.staffID == nil)
    }
}
