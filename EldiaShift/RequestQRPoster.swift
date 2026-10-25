import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - 希望休の申請フォーム（壁に貼る QR コード）
// QR を読むとスタッフのスマホで申請フォーム（Web ページ）が開く。入力した内容は LINE などで管理者に送られ、
// 管理者は「申請を受け取る」に貼る。フォームのページはサーバーに何も送らない。

enum RequestForm {
    static let page = "https://facility-manager-phi.vercel.app/hotel-shift/request"

    /// 店舗名・「〇〇 SHIFT」の〇〇を付けたフォームの URL
    static func url(storeName: String, prefix: String) -> URL {
        var c = URLComponents(string: page)!
        var items: [URLQueryItem] = []
        let s = storeName.trimmingCharacters(in: .whitespaces)
        if !s.isEmpty { items.append(URLQueryItem(name: "s", value: s)) }
        if prefix != "HOTEL" { items.append(URLQueryItem(name: "b", value: prefix)) }
        c.queryItems = items.isEmpty ? nil : items
        return c.url!
    }

    /// QR コードの画像（白黒・ぼやけないよう整数倍に拡大）
    static func qrImage(_ text: String, size: CGFloat) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage else { return nil }
        let k = max(1, (size / out.extent.width).rounded(.down))
        let scaled = out.transformed(by: CGAffineTransform(scaleX: k, y: k))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// 壁に貼るポスター（A4 縦。印刷するので色は固定）
struct RequestQRPoster: View {
    let storeName: String
    let prefix: String
    let url: URL

    static let pageSize = CGSize(width: 595, height: 842)

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 6) {
                Text("\(prefix) SHIFT").font(.system(size: 20, weight: .heavy)).foregroundStyle(Color(white: 0.35))
                Text("希望休の申請").font(.system(size: 44, weight: .heavy))
                if !storeName.isEmpty { Text(storeName).font(.system(size: 22, weight: .bold)).foregroundStyle(Color(white: 0.3)) }
            }
            if let img = RequestForm.qrImage(url.absoluteString, size: 300) {
                Image(uiImage: img).interpolation(.none).resizable().frame(width: 300, height: 300)
                    .padding(14)
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(white: 0.8), lineWidth: 2))
            }
            VStack(alignment: .leading, spacing: 12) {
                step(1, "スマホのカメラで QR コードを読み取る")
                step(2, "名前と、休みたい日を選ぶ")
                step(3, "「LINEで送る」を押して、シフトの担当者に送る")
            }
            .frame(width: 430, alignment: .leading)
            Text("入力した内容は、送るまでどこにも保存されません。LINE が使えないときは、そのまま担当者に伝えてください。")
                .font(.system(size: 13)).foregroundStyle(Color(white: 0.4))
                .multilineTextAlignment(.center).frame(width: 440)
        }
        .foregroundStyle(.black)
        .frame(width: Self.pageSize.width, height: Self.pageSize.height)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(n)").font(.system(size: 20, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 34, height: 34).background(Color.black, in: Circle())
            Text(text).font(.system(size: 20, weight: .bold))
        }
    }
}

/// 申請用 QR コード：店舗を選んで、ポスターを PDF・印刷に。リンクを送ることもできる
struct RequestQRSheet: View {
    @Environment(ShiftStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var storeID = ""
    @State private var file: ExportFile?
    @State private var error: String?

    var body: some View {
        let book = store.book
        let st = book.store(storeID) ?? store.currentStore
        let name = book.allStores.count > 1 ? st.name : ""
        let url = RequestForm.url(storeName: name, prefix: st.displayPrefix)
        NavigationStack {
            Form {
                if book.allStores.count > 1 {
                    Section {
                        Picker("店舗", selection: $storeID) {
                            ForEach(book.allStores) { Text($0.name).tag($0.id) }
                        }
                    } footer: {
                        Text("店舗名が申請の文章に入ります（どの店舗の休みか分かるように）。")
                    }
                }
                Section {
                    RequestQRPoster(storeName: name, prefix: st.displayPrefix, url: url)
                        .scaleEffect(0.5)
                        .frame(width: RequestQRPoster.pageSize.width * 0.5, height: RequestQRPoster.pageSize.height * 0.5)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(.separator)))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .accessibilityLabel("申請用のポスターの見本")
                } footer: {
                    Text("事務所・休憩室など、スタッフだけが見る場所に貼ってください。読み取ると、スタッフのスマホで申請の画面が開きます（アプリは要りません）。")
                }
                Section {
                    Button { makePDF(name: name, prefix: st.displayPrefix, url: url) } label: {
                        Label("ポスターを印刷・PDFにする", systemImage: "printer")
                    }
                    ShareLink(item: url) { Label("申請のリンクを送る（LINE グループなど）", systemImage: "link") }
                    Button { UIPasteboard.general.url = url } label: { Label("リンクをコピー", systemImage: "doc.on.doc") }
                } footer: {
                    Text(url.absoluteString).font(.caption2).textSelection(.enabled)
                }
            }
            .navigationTitle("申請用QRコード")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
            .onAppear { if storeID.isEmpty { storeID = store.currentStore.id } }
            .sheet(item: $file) { f in ShareSheet(items: [f.url]) }
            .errorAlert($error)
        }
    }

    private func makePDF(name: String, prefix: String, url: URL) {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("希望休の申請QR\(name.isEmpty ? "" : "_\(name)").pdf")
        let renderer = ImageRenderer(content: RequestQRPoster(storeName: name, prefix: prefix, url: url))
        var ok = false
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let ctx = CGContext(out as CFURL, mediaBox: &box, nil) else { return }
            ctx.beginPDFPage(nil)
            draw(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
            ok = true
        }
        if ok { file = ExportFile(url: out) } else { error = "PDFを作れませんでした" }
    }
}
