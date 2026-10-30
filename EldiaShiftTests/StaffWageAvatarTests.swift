import Foundation
import Testing
import UIKit
@testable import EldiaShift

@Suite("スタッフ：最低賃金・10円の切り上げ・似顔絵")
@MainActor
struct StaffWageAvatarTests {
    private func member(_ id: String, dept: String, hourly: Int?) -> StaffMember {
        var m = StaffMember(id: id, number: 1, name: "スタッフ\(id)", departmentID: dept, active: true, joinDate: "", leaveDate: "",
                            timeBlocks: [], patterns: [], activePatternID: nil, periodPatterns: [])
        if let hourly { m.wages = [WageEntry(id: "w\(id)", from: "2026-04-01", kind: .hourly, amount: hourly)] }
        return m
    }

    @Test("表は47都道府県。店舗の最低賃金は、手で入れた金額 → 表 の順")
    func table() throws {
        #expect(MinimumWage.prefectures.count == 47)
        #expect(Set(MinimumWage.prefectures) == Set(MinimumWage.table.keys))
        var st = Store(id: "a", name: "神戸")
        #expect(MinimumWage.value(for: st) == nil)
        st.prefecture = "兵庫県"
        #expect(MinimumWage.value(for: st) == 1172)
        st.minimumWageOverride = 1200
        #expect(MinimumWage.value(for: st) == 1200)
        // 前の版の店舗の記録は未設定として読む
        let old = try JSONDecoder().decode(Store.self, from: Data(#"{"id":"a","name":"本館"}"#.utf8))
        #expect(old.prefecture.isEmpty && old.minimumWageOverride == nil)
    }

    @Test("時給が最低賃金に足りないときだけ注意（月給・未設定は注意しない）")
    func shortfall() {
        var b = ShiftBook()
        var kobe = Store(id: "a", name: "神戸", sortOrder: 0)
        kobe.prefecture = "兵庫県"
        b.stores = [kobe, Store(id: "b", name: "大阪", sortOrder: 1)]
        b.departments = [Department(id: "da", name: "フロント", colorIndex: 0, sortOrder: 0, storeID: "a"),
                         Department(id: "db", name: "フロント", colorIndex: 0, sortOrder: 1, storeID: "b")]
        let day = DayKey(2026, 11, 1)
        #expect(MinimumWage.shortfall(of: member("1", dept: "da", hourly: 1100), on: day, in: b) == 72)
        #expect(MinimumWage.shortfall(of: member("2", dept: "da", hourly: 1172), on: day, in: b) == nil)
        #expect(MinimumWage.shortfall(of: member("3", dept: "da", hourly: nil), on: day, in: b) == nil)
        // 都道府県を決めていない店舗の人は注意しない
        #expect(MinimumWage.shortfall(of: member("4", dept: "db", hourly: 900), on: day, in: b) == nil)
        // 月給は比べない
        var monthly = member("5", dept: "da", hourly: nil)
        monthly.wages = [WageEntry(id: "m", from: "2026-04-01", kind: .monthly, amount: 200_000)]
        #expect(MinimumWage.shortfall(of: monthly, on: day, in: b) == nil)
        // まだ始まっていない時給は見ない
        #expect(MinimumWage.shortfall(of: member("6", dept: "da", hourly: 900), on: DayKey(2026, 3, 1), in: b) == nil)
    }

    @Test("10円単位に切り上げる")
    func roundUp() {
        #expect(MinimumWage.roundUp10(1201) == 1210)
        #expect(MinimumWage.roundUp10(1210) == 1210)
        #expect(MinimumWage.roundUp10(1209) == 1210)
        #expect(MinimumWage.roundUp10(0) == 0)
    }

    @Test("似顔絵は 240px の PNG で、選んだ内容を読み戻せる")
    func avatar() throws {
        var c = StaffAvatarConfiguration()
        c.hair = "ボブ"
        c.glasses = true
        c.skin = 3
        let data = try #require(StaffAvatarDrawing.png(c))
        #expect(data.starts(with: Data([0x89, 0x50, 0x4E, 0x47])))
        let img = try #require(UIImage(data: data))
        #expect(img.size.width * img.scale == StaffAvatarDrawing.storedSize)
        #expect(StaffAvatarDrawing.restored(from: data) == c)
        // ふつうの写真は似顔絵として読まない
        let jpeg = try #require(UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { _ in }.jpegData(compressionQuality: 0.5))
        #expect(StaffAvatarDrawing.restored(from: jpeg) == nil)
    }

    @Test("透明な画像（ミー文字など）を写真にすると、背景は白になる")
    func transparentPhoto() throws {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.opaque = false
        fmt.scale = 1
        let png = try #require(UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100), format: fmt).image { _ in }.pngData())
        let small = try #require(StaffPhoto.shrink(png))
        let cg = try #require(UIImage(data: small)?.cgImage)
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = try #require(CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(px[0] > 240 && px[1] > 240 && px[2] > 240)
    }
}
