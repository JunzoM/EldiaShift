import Foundation
import ImageIO
import PDFKit
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import EldiaShift

/// メモリを抑える仕組み（大きな写真を縮めて読む・PDF をファイルへ直接書く・ID の文字列を使い回す）
@Suite("メモリ：写真の縮小・PDF の書き出し・文字列の共有")
@MainActor
struct MemoryTests {
    /// 大きな写真（JPEG）。orientation を付けると、カメラの縦向きの写真と同じ書き方になる
    private func photo(width: Int, height: Int, orientation: Int? = nil) throws -> Data {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: fmt).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let cg = try #require(img.cgImage)
        let out = NSMutableData()
        let dest = try #require(CGImageDestinationCreateWithData(out as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil))
        var props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.5]
        if let orientation { props[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
        return out as Data
    }

    private func pixels(_ data: Data) throws -> CGSize {
        let cg = try #require(UIImage(data: data)?.cgImage)
        return CGSize(width: cg.width, height: cg.height)
    }

    @Test("大きな写真も、顔写真は 240px・ホームは 1200×400・店舗は長い辺 640px になる")
    func shrinkSizes() throws {
        let big = try photo(width: 4000, height: 3000)
        #expect(try pixels(#require(StaffPhoto.shrink(big))) == CGSize(width: 240, height: 240))
        #expect(try pixels(#require(CompanyInfoView.shrinkCover(big))) == CGSize(width: 1200, height: 400))
        #expect(try pixels(#require(StorePhoto.shrink(big))) == CGSize(width: 640, height: 480))
        // 小さな写真は大きくしない（店舗）
        let small = try photo(width: 300, height: 200)
        #expect(try pixels(#require(StorePhoto.shrink(small))) == CGSize(width: 300, height: 200))
        #expect(StaffPhoto.shrink(Data("not an image".utf8)) == nil)
    }

    @Test("縦向きで撮った写真（向きの情報つき）は、縦横を入れ替えて読む")
    func orientation() throws {
        // 横 4000×縦 3000 で保存され、「90度回して見る」(6) の写真 → 見た目は縦 4000・横 3000
        let rotated = try photo(width: 4000, height: 3000, orientation: 6)
        #expect(StaffPhoto.pixelSize(rotated) == CGSize(width: 3000, height: 4000))
        #expect(try pixels(#require(StorePhoto.shrink(rotated))) == CGSize(width: 480, height: 640))
    }

    @Test("表示用の画像は長い辺 1200px までにして、同じ写真は使い回す")
    func displayCache() throws {
        let big = try photo(width: 3000, height: 1000)
        let a = try #require(StaffPhoto.image(big))
        #expect(a.size == CGSize(width: 1200, height: 400))
        #expect(StaffPhoto.image(big) === a)
    }

    @Test("PDF をファイルへ直接書き出せる（ページ数が合う）")
    func pdfFile() async throws {
        var b = ShiftBook()
        b.departments = [Department(id: "a", name: "フロント", colorIndex: 0, sortOrder: 0)]
        b.staff = (1...30).map { i in
            StaffMember(id: "s\(i)", number: i, name: "スタッフ\(i)", departmentID: "a", active: true, joinDate: "", leaveDate: "",
                        timeBlocks: [], patterns: [], activePatternID: nil, periodPatterns: [])
        }
        let pages = PrintPlanner.pages(format: .monthByDepartment, half: .both, departments: b.departments, anchor: DayKey(2026, 10, 1))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("memory-test.pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        var seen = 0
        #expect(await PDFMaker.makeFile(at: url, pages: pages, book: b, title: "見本") { seen = $0 })
        #expect(seen == pages.count)
        let doc = try #require(PDFDocument(url: url))
        #expect(doc.pageCount == pages.count)
    }

    @Test("読み込みのとき、同じ中身の文字列は1つにまとめる")
    func stringPool() {
        var pool = StringPool()
        let a = pool(String(NSString(string: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")))
        let b = pool(String(NSString(string: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")))
        #expect(a == b)
        // 同じ入れ物を指している（中身を2つ持たない）
        let same = a.utf8.withContiguousStorageIfAvailable { pa in
            b.utf8.withContiguousStorageIfAvailable { pb in pa.baseAddress == pb.baseAddress }
        }
        #expect(same == true)
        #expect(pool("") == "")
    }

    @Test("データベースから読み直しても、マスの中身は変わらない")
    func reloadKeepsCells() throws {
        let store = ShiftStore(db: ShiftDatabase(inMemory: true))
        var b = PerfBench.bigBook()
        b.scopeStoreID = nil
        try store.replaceAll(with: b)
        #expect(store.book.cells == b.cells)
        #expect(Set(store.book.staff.map(\.id)) == Set(b.staff.map(\.id)))
    }
}
