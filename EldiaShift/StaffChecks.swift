import Foundation

// MARK: - スタッフを消す前に、何が一緒に消えるかを数える（HOTEL SHIFT から移植）

struct StaffDeletionImpact: Equatable, Sendable {
    /// 手で入れたシフトの日数（休みの入力も含む）
    var enteredDays: Int
    /// そのうち今日以降の日数
    var upcomingDays: Int
    var weekPatterns: Int
    var periodPatterns: Int
    var personalTimes: Int
    var offRequests: Int

    init(member: StaffMember, book: ShiftBook, today: DayKey) {
        var entered = 0, upcoming = 0
        for key in book.cells.keys where key.staffID == member.id {
            entered += 1
            if key.day >= today { upcoming += 1 }
        }
        enteredDays = entered
        upcomingDays = upcoming
        weekPatterns = member.patterns.count
        periodPatterns = member.periodPatterns.count
        personalTimes = member.timeBlocks.count
        offRequests = member.offRequests.count
    }

    /// 確認画面に出す文章
    var message: String {
        var parts: [String] = []
        if enteredDays > 0 {
            parts.append(upcomingDays > 0 ? "入力したシフト \(enteredDays)日分（うち今日以降 \(upcomingDays)日）"
                                          : "入力したシフト \(enteredDays)日分")
        }
        if weekPatterns > 0 { parts.append("週間パターン \(weekPatterns)件") }
        if periodPatterns > 0 { parts.append("期間限定パターン \(periodPatterns)件") }
        if personalTimes > 0 { parts.append("個人の時間 \(personalTimes)件") }
        if offRequests > 0 { parts.append("希望休 \(offRequests)日") }
        var text = parts.isEmpty ? "この人の記録はまだありません。"
                                 : "一緒に消えるもの：" + parts.joined(separator: "、") + "。"
        text += "\n同じ部門の番号が繰り上がります。元には戻せません。"
        if enteredDays > 0 {
            text += "\n辞めた人は、削除せずに退職にすると、これまでのシフトが残ります。"
        }
        return text
    }
}
