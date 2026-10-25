import Foundation
import Testing
@testable import EldiaShift

@Suite("希望休の申請")
@MainActor
struct LeaveRequestTests {
    private func member(_ id: String, _ name: String) -> StaffMember {
        StaffMember(id: id, number: 1, name: name, departmentID: "d", active: true, joinDate: "", leaveDate: "",
                    timeBlocks: [], patterns: [], activePatternID: nil, periodPatterns: [])
    }

    @Test("文章から名前を見つける（フルネーム・姓だけ・決まらないとき）")
    func detect() {
        let staff = [member("1", "山田 花子"), member("2", "山田 太郎"), member("3", "佐藤 一郎")]
        #expect(LeaveRequestInbox.detectStaff(in: "山田花子です。11/3休み希望", among: staff)?.id == "1")
        #expect(LeaveRequestInbox.detectStaff(in: "佐藤です 12日お休みください", among: staff)?.id == "3")
        // 「山田」だけだと2人いるので決めない
        #expect(LeaveRequestInbox.detectStaff(in: "山田です 12日", among: staff) == nil)
        #expect(LeaveRequestInbox.detectStaff(in: "12日お休みください", among: staff) == nil)
    }

    @Test("届いた日を承認待ちにする（重なりは足さない）")
    func receive() {
        var m = member("1", "山田 花子")
        m.offRequests = ["2026-11-05"]
        let days = [DayKey(2026, 11, 3), DayKey(2026, 11, 5), DayKey(2026, 11, 3)]
        let (next, added) = LeaveRequestInbox.receive(days, note: "通院", into: m, now: Date())
        #expect(added == 1)
        #expect(next.leaveRequests.map(\.day) == ["2026-11-03"])
        #expect(next.leaveRequests.first?.status == .pending)
        #expect(next.offRequests == ["2026-11-05"])   // 承認するまでは希望休に入らない
        // 同じ日をもう一度送っても増えない
        #expect(LeaveRequestInbox.receive([DayKey(2026, 11, 3)], note: "", into: next, now: Date()).added == 0)
    }

    @Test("承認で希望休に入り、却下・取り消しで外れる")
    func decide() {
        let (m0, _) = LeaveRequestInbox.receive([DayKey(2026, 11, 3), DayKey(2026, 11, 4)], note: "", into: member("1", "山田 花子"), now: Date())
        let a = m0.leaveRequests[0].id, b = m0.leaveRequests[1].id
        let m1 = LeaveRequestInbox.decide([a], as: .approved, in: m0, now: Date())
        #expect(m1.offRequests == ["2026-11-03"])
        #expect(m1.leaveRequests.first { $0.id == a }?.decidedAt != nil)
        let m2 = LeaveRequestInbox.decide([b], as: .rejected, in: m1, now: Date())
        #expect(m2.offRequests == ["2026-11-03"])
        let m3 = LeaveRequestInbox.decide([a], as: .pending, in: m2, now: Date())
        #expect(m3.offRequests.isEmpty)
        #expect(m3.leaveRequests.first { $0.id == a }?.decidedAt == nil)
    }

    @Test("返事の文章に、OKの日と難しい日が入る")
    func reply() {
        let (m0, _) = LeaveRequestInbox.receive([DayKey(2026, 11, 3), DayKey(2026, 11, 4)], note: "", into: member("1", "山田 花子"), now: Date())
        let m1 = LeaveRequestInbox.decide([m0.leaveRequests[0].id], as: .approved, in: m0, now: Date())
        let m2 = LeaveRequestInbox.decide([m0.leaveRequests[1].id], as: .rejected, in: m1, now: Date())
        let text = LeaveRequestInbox.reply(to: m2, m2.leaveRequests)
        #expect(text.contains("山田 花子さん"))
        #expect(text.contains("お休みOK：11/3（火）"))
        #expect(text.contains("難しい日：11/4（水）"))
    }

    @Test("端末内の保存・バックアップで申請が残る")
    func persistence() throws {
        let store = ShiftStore(db: ShiftDatabase(inMemory: true))
        try store.save(member("1", "山田 花子"))
        #expect(try store.receiveLeaveRequests([DayKey(2026, 11, 3)], note: "通院", for: "1") == 1)
        let loaded = try ShiftRecords.load(store.db.viewContext)
        #expect(loaded.staff.first?.leaveRequests.first?.note == "通院")
        let (again, _) = try BackupFile.read(try BackupFile.write(loaded))
        #expect(again.staff.first?.leaveRequests == loaded.staff.first?.leaveRequests)

        let id = try #require(store.book.staff.first?.leaveRequests.first?.id)
        try store.decideLeaveRequests([id], as: .approved, for: "1", offBlockID: nil)
        #expect(store.book.staff.first?.offRequests == ["2026-11-03"])
    }

    @Test("申請フォームの文章は、名前・休みたい日・理由の行から読む（理由の数字を日付にしない）")
    func formText() {
        let text = """
        【希望休の申請】
        名前：山田花子
        店舗：LUXURY神戸
        休みたい日：11/3(火)、11/10(火)
        理由：通院 2回目
        （SHIFT 申請フォームから）
        """
        let f = LeaveRequestInbox.formFields(text)
        #expect(f?.name == "山田花子")
        #expect(f?.reason == "通院 2回目")
        let days = OffRequestParser.parse(f?.dates ?? "", month: MonthKey(2026, 11))
        #expect(days == [DayKey(2026, 11, 3), DayKey(2026, 11, 10)])
        let staff = [member("1", "山田 花子"), member("2", "佐藤 一郎")]
        #expect(LeaveRequestInbox.detectStaff(in: f?.name ?? "", among: staff)?.id == "1")
        // 決まった形でない文章は nil（ふつうの読み取りに回す）
        #expect(LeaveRequestInbox.formFields("山田です。11/3 休み希望") == nil)
    }

    @Test("申請フォームの URL に店舗名と表示名が入る")
    func formURL() {
        let u = RequestForm.url(storeName: "LUXURY神戸", prefix: "ELDIA")
        let items = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(u.absoluteString.hasPrefix(RequestForm.page))
        #expect(items.first { $0.name == "s" }?.value == "LUXURY神戸")
        #expect(items.first { $0.name == "b" }?.value == "ELDIA")
        #expect(RequestForm.url(storeName: "", prefix: "HOTEL").absoluteString == RequestForm.page)
        #expect(RequestForm.qrImage(u.absoluteString, size: 200) != nil)
    }
}
