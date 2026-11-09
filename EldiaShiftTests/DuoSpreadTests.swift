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

    /// 開いた Duo の縦向き（669 × 951 ポイント、折り目はまん中）
    private func tall(_ hinge: HingeState = .fullyOpen) -> DuoInfo {
        DuoInfo(hinge: hinge, foldX: 334.5, windowWidth: 669, landscape: false, foldY: 475.5, windowHeight: 951)
    }

    @Test func stackedOnlyWhenOpenAndPortrait() {
        #expect(tall().stacked)
        #expect(tall(.partiallyOpen).stacked)
        #expect(!tall().spread)
        #expect(tall().opened)
        #expect(!tall(.closed).stacked)
        #expect(!tall(.none).stacked)
        // 横向きは左右の見開き
        #expect(!open().stacked)
        #expect(open().opened)
        // 窓が折り目の上だけのとき
        #expect(!DuoInfo(hinge: .fullyOpen, landscape: false, foldY: 480, windowHeight: 470).stacked)
    }

    @Test func bottomPageStartsAtFold() {
        let d = tall()
        // ナビゲーションバーの下（y=100）から窓の下まで
        #expect(d.bottomPageHeight(in: CGRect(x: 0, y: 100, width: 669, height: 851)) == 475.5)
        // 折り目の上が低すぎるときは、上のページを 240 残して、下のページを折り目より上から始める
        #expect(d.bottomPageHeight(in: CGRect(x: 0, y: 400, width: 669, height: 551)) == 311)
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

    @Test func continueRequestOnlyUntilAnotherLook() {
        let f = DuoFocus()
        let m = StaffMember(id: "s1", number: 1, name: "鈴木", departmentID: "d", active: true, joinDate: "", leaveDate: "",
                            timeBlocks: [], patterns: [], activePatternID: nil, periodPatterns: [])
        let r = LeaveRequest(id: "r1", day: "2026-11-14", note: "", status: .pending, receivedAt: Date(), decidedAt: nil)
        f.look(request: r, of: m)
        #expect(f.requestToContinue() == "r1")
        #expect(f.dayToContinue() == DayKey(2026, 11, 14))
        #expect(f.requestToContinue(now: Date().addingTimeInterval(DuoFocus.keep + 1)) == nil)
        // そのあとシフト表を見たら、開いたときはシフト表のつづき
        f.look(day: DayKey(2026, 11, 8))
        #expect(f.requestToContinue() == nil)
    }

    @Test func miniGridShortLabels() {
        #expect(MiniGrid.short("早番 9:00〜18:00") == "早番")
        #expect(MiniGrid.short("9:00〜18:00（別館）") == "9:00〜")
        #expect(MiniGrid.short("公休") == "公休")
        #expect(MiniGrid.short("") == "")
    }
}
