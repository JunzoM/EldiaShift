import SwiftUI
import UIKit
import TipKit

// MARK: - 印刷・PDF（PC版の「印刷 / PDF」と同じ4つの形式。白黒で印刷しても見分けられる）

enum PrintFormat: String, CaseIterable, Identifiable {
    case weekByDepartment       // ① 週表示A4縦（部門ごとに1枚）
    case monthByDepartment      // ② 月表示A4縦（部門ごと × 前半／後半）
    case monthCombined          // ③ 月表示A4縦（選んだ部門を1枚にまとめる × 前半／後半）
    case monthLandscape         // ④ 月表示A4横（前半を上・後半を下に1枚）

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekByDepartment: "① 週表示 A4縦（部門ごと）"
        case .monthByDepartment: "② 月表示 A4縦（部門ごと）"
        case .monthCombined: "③ 月表示 A4縦（部門をまとめて）"
        case .monthLandscape: "④ 月表示 A4横（前半・後半を1枚に）"
        }
    }

    var landscape: Bool { self == .monthLandscape }
    var usesHalf: Bool { self == .monthByDepartment || self == .monthCombined }
}

enum HalfSelection: String, CaseIterable, Identifiable {
    case first, second, both
    var id: String { rawValue }
    var title: String { self == .first ? "前半のみ" : self == .second ? "後半のみ" : "両方" }
}

/// 1枚分の内容
struct PrintPageSpec: Identifiable {
    let id = UUID()
    var label: String
    /// 表（上から順に。④は前半・後半の2つ）
    var tables: [(caption: String?, days: [DayKey])]
    var departmentIDs: [String]
    var landscape: Bool
}

enum PrintPlanner {
    static func pages(format: PrintFormat, half: HalfSelection, departments: [Department],
                      anchor: DayKey) -> [PrintPageSpec] {
        let month = MonthKey(anchor)
        let all = month.days
        let h1 = Array(all.prefix(15)), h2 = Array(all.dropFirst(15))
        let chunks: [[DayKey]] = half == .first ? [h1] : half == .second ? [h2] : [h1, h2]
        let ym = "\(month.year)年 \(month.month)月 シフト表"
        func range(_ c: [DayKey]) -> String { "\(c.first!.day)日〜\(c.last!.day)日" }
        switch format {
        case .weekByDepartment:
            let w = GridMode.week.days(around: anchor)
            let label = "\(w[0].year)年 シフト表　%@　\(w[0].month)月\(w[0].day)日（月）〜 \(w[6].month)月\(w[6].day)日（日）"
            return departments.map { d in
                PrintPageSpec(label: String(format: label, d.name), tables: [(nil, w)], departmentIDs: [d.id], landscape: false)
            }
        case .monthByDepartment:
            return departments.flatMap { d in
                chunks.map { c in
                    PrintPageSpec(label: "\(ym)　\(d.name)　\(range(c))", tables: [(nil, c)], departmentIDs: [d.id], landscape: false)
                }
            }
        case .monthCombined:
            let names = departments.map(\.name).joined(separator: "・")
            return chunks.map { c in
                PrintPageSpec(label: "\(ym)　\(names)　\(range(c))", tables: [(nil, c)], departmentIDs: departments.map(\.id),
                              landscape: false)
            }
        case .monthLandscape:
            let names = departments.map(\.name).joined(separator: "・")
            return [PrintPageSpec(label: "\(ym)　\(names)",
                                  tables: [("前半（1〜\(h1.last!.day)日）", h1), ("後半（\(h2.first!.day)〜\(h2.last!.day)日）", h2)],
                                  departmentIDs: departments.map(\.id), landscape: true)]
        }
    }
}

/// A4 1枚（72dpi の pt。A4 は 595×842）
struct PrintPageView: View {
    let spec: PrintPageSpec
    let book: ShiftBook
    let title: String

    static let a4 = CGSize(width: 595.28, height: 841.89)
    var size: CGSize { spec.landscape ? CGSize(width: Self.a4.height, height: Self.a4.width) : Self.a4 }

    var body: some View {
        let margin: CGFloat = spec.landscape ? 17 : 20
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(spec.label).font(.system(size: 9.5, weight: .bold)).frame(maxWidth: .infinity, alignment: .leading)
                Text(title).font(.system(size: 11, weight: .heavy)).frame(maxWidth: .infinity)
                Text("出力日: \(Self.today)").font(.system(size: 6.5)).foregroundStyle(Color(white: 0.33))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .lineLimit(1).minimumScaleFactor(0.6)
            .padding(.bottom, 3)
            .overlay(alignment: .bottom) { Rectangle().fill(Color(white: 0.8)).frame(height: 0.5) }

            let rowsTotal = spec.tables.reduce(0) { n, _ in n + 1 + groups.reduce(0) { $0 + 1 + $1.members.count } }
            let available = size.height - margin * 2 - 24 - CGFloat(spec.tables.count - 1) * 18
            let rowH = min(26, max(11, available / CGFloat(max(1, rowsTotal))))
            ForEach(Array(spec.tables.enumerated()), id: \.offset) { _, t in
                if let c = t.caption {
                    Text(c).font(.system(size: 7, weight: .bold)).foregroundStyle(Color(white: 0.33)).padding(.top, 2)
                }
                PrintTable(days: t.days, groups: groups, book: book, landscape: spec.landscape,
                           width: size.width - margin * 2, rowHeight: rowH)
            }
            Spacer(minLength: 0)
        }
        .padding(margin)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(Color.black)
        .environment(\.colorScheme, .light)
    }

    private var groups: [DepartmentGroup] {
        let month = MonthKey(spec.tables.first?.days.first ?? .today)
        return book.staffByDepartment(visibleIn: month).filter { spec.departmentIDs.contains($0.department.id) }
    }

    private static var today: String {
        let d = DayKey.today
        return "\(d.year)/\(d.month)/\(d.day)"
    }
}

/// 印刷用の表（PC版と同じ見た目：黒い見出し、日曜は濃い灰色・土曜は中くらいの灰色、有休は○有・当欠は○欠、公休は空白）
private struct PrintTable: View {
    let days: [DayKey]
    let groups: [DepartmentGroup]
    let book: ShiftBook
    let landscape: Bool
    let width: CGFloat
    let rowHeight: CGFloat

    private var noW: CGFloat { 14 }
    private var nameW: CGFloat { landscape ? 42 : 46 }
    private var ioW: CGFloat { 10 }
    private var sumW: CGFloat { 24 }
    private var cellW: CGFloat { (width - noW - nameW - ioW - sumW) / CGFloat(days.count) }
    private let line = Color(white: 0.53)

    var body: some View {
        VStack(spacing: 0) {
            header
            ForEach(groups) { g in
                Text("■ \(g.department.name)")
                    .font(.system(size: 8.5, weight: .heavy))
                    .frame(width: width, height: max(12, rowHeight * 0.7), alignment: .leading)
                    .padding(.leading, 5)
                    .background(Color(white: 0.91))
                    .overlay(alignment: .leading) { Rectangle().fill(Color.black).frame(width: 3) }
                    .border(Color.black, width: 0.75)
                ForEach(g.members) { m in row(m) }
            }
        }
        .frame(width: width, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 0) {
            headCell("No", noW, size: 7)
            headCell("氏名", nameW, size: 8)
            VStack(spacing: 0) { Text("入"); Text("出") }
                .font(.system(size: 5, weight: .heavy)).foregroundStyle(.white)
                .frame(width: ioW, height: 26).background(Color(white: 0.2))
            ForEach(days, id: \.self) { d in
                let sun = d.weekday == 0, sat = d.weekday == 6
                VStack(spacing: 0) {
                    Text(days.count <= 7 ? "\(d.month)/\(d.day)" : "\(d.day)").font(.system(size: 8, weight: .heavy))
                    Text(sun ? "㊐" : sat ? "㊏" : ["日", "月", "火", "水", "木", "金", "土"][d.weekday])
                        .font(.system(size: 6.5)).opacity(0.85)
                }
                .foregroundStyle(.white)
                .frame(width: cellW, height: 26)
                .background(sun ? Color(white: 0.33) : sat ? Color(white: 0.53) : .black)
                .overlay(alignment: .bottom) { if sun || sat { Rectangle().fill(.white).frame(height: 2) } }
            }
            headCell("計", sumW, size: 7)
        }
    }

    private func headCell(_ t: String, _ w: CGFloat, size: CGFloat) -> some View {
        Text(t).font(.system(size: size, weight: .bold)).foregroundStyle(.white)
            .frame(width: w, height: 26).background(Color.black)
            .border(Color.black, width: 0.5)
    }

    private func row(_ m: StaffMember) -> some View {
        // 計：月の表は月全体の実働（前半・後半どちらの表でも同じ。PC版と同じ）、週の表はその週の実働
        let total = MonthSummary.of(m, days: days.count <= 7 ? days : MonthKey(days[0]).days, in: book).hours
        let fs: CGFloat = landscape ? 7 : 7.5
        return HStack(spacing: 0) {
            Text("\(m.number)").font(.system(size: 7)).foregroundStyle(Color(white: 0.33))
                .frame(width: noW, height: rowHeight).border(Color(white: 0.33), width: 0.5)
            Text(m.name).font(.system(size: 9, weight: .bold)).lineLimit(1).minimumScaleFactor(0.5)
                .frame(width: nameW, height: rowHeight).border(Color(white: 0.8), width: 0.5)
            VStack(spacing: 0) {
                Text("入").frame(maxHeight: .infinity)
                Rectangle().fill(Color(white: 0.73)).frame(height: 0.3)
                Text("出").frame(maxHeight: .infinity)
            }
            .font(.system(size: 6.5, weight: .heavy))
            .frame(width: ioW, height: rowHeight).background(Color(white: 0.92)).border(Color(white: 0.33), width: 0.5)
            ForEach(days, id: \.self) { d in cell(m, d, fs: fs) }
            Text(String(format: "%.1fh", total)).font(.system(size: 7.5, weight: .heavy, design: .monospaced))
                .minimumScaleFactor(0.6)
                .frame(width: sumW, height: rowHeight).background(Color(white: 0.91)).border(Color(white: 0.33), width: 0.5)
        }
    }

    @ViewBuilder
    private func cell(_ m: StaffMember, _ d: DayKey, fs: CGFloat) -> some View {
        let left = m.hasLeft(on: d)
        let r = left ? nil : Schedule.resolve(m, on: d, in: book)
        let sun = d.weekday == 0, sat = d.weekday == 6
        let bg: Color = left ? Color(white: 0.78) : r?.isOff == true ? Color(white: 0.91)
            : sun ? Color(white: 0.82) : sat ? Color(white: 0.88) : .white
        ZStack {
            bg
            if left {
                Text("×").font(.system(size: 7)).foregroundStyle(Color(white: 0.6))
            } else if let r, r.isOff {
                if r.blockID == "off2" || r.blockID == "off3" {
                    Text(r.blockID == "off2" ? "有" : "欠").font(.system(size: 8, weight: .heavy))
                        .frame(width: 11, height: 11).overlay(Circle().stroke(Color.black, lineWidth: 1))
                }
            } else if let r {
                VStack(spacing: 0) {
                    Text(short(r.inTime)).frame(maxHeight: .infinity)
                    Rectangle().fill(Color(white: 0.73)).frame(height: 0.3)
                    Text(short(r.outTime)).frame(maxHeight: .infinity)
                }
                .font(.system(size: fs, weight: .bold, design: .monospaced))
                .minimumScaleFactor(0.6)
            }
        }
        .frame(width: cellW, height: rowHeight)
        .border(sun || sat ? Color(white: 0.33) : line, width: 0.5)
    }

    /// 印刷では先頭の0を取る（09:00 → 9:00）
    private func short(_ t: String) -> String { t.hasPrefix("0") ? String(t.dropFirst()) : t }
}

// MARK: - PDF にする

enum PDFMaker {
    @MainActor
    static func make(pages: [PrintPageSpec], book: ShiftBook, title: String) -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return Data() }
        var box = CGRect(origin: .zero, size: PrintPageView.a4)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        for spec in pages {
            let view = PrintPageView(spec: spec, book: book, title: title)
            var media = CGRect(origin: .zero, size: view.size)
            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = ProposedViewSize(view.size)
            renderer.render { _, draw in
                ctx.beginPage(mediaBox: &media)
                draw(ctx)
                ctx.endPage()
            }
        }
        ctx.closePDF()
        return data as Data
    }
}

// MARK: - 印刷・PDF の画面

struct PrintSheet: View {
    let anchor: DayKey

    @Environment(ShiftStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("printFormat") private var format: PrintFormat = .monthByDepartment
    @AppStorage("printHalf") private var half: HalfSelection = .both
    @AppStorage("printTitle") private var title = ""
    @State private var selected: Set<String> = []
    @State private var shareFile: ExportFile?
    @State private var busy = false

    var body: some View {
        let book = store.book
        let depts = book.departments.sorted { $0.sortOrder < $1.sortOrder }
            .filter { d in book.staff.contains { $0.departmentID == d.id } }
        let chosen = depts.filter { selected.contains($0.id) }
        let pages = chosen.isEmpty ? [] : PrintPlanner.pages(format: format, half: half, departments: chosen, anchor: anchor)

        NavigationStack {
            Form {
                TipView(PrintTip())
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                Section("形式") {
                    Picker("形式", selection: $format) {
                        ForEach(PrintFormat.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("部門") {
                    ForEach(depts) { d in
                        Toggle(d.name, isOn: Binding(get: { selected.contains(d.id) },
                                                     set: { if $0 { selected.insert(d.id) } else { selected.remove(d.id) } }))
                    }
                }
                if format.usesHalf {
                    Section("印刷範囲") {
                        Picker("印刷範囲", selection: $half) {
                            ForEach(HalfSelection.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                Section {
                    TextField("表の上に出す名前（例：店名）", text: $title)
                } footer: {
                    Text("白黒で印刷しても見分けられるよう、日曜は濃い灰色・土曜は中くらいの灰色にします。有休は○有、当欠は○欠で印刷し、公休は空白にします。")
                }

                Section("プレビュー（\(pages.count)枚）") {
                    if let first = pages.first {
                        let v = PrintPageView(spec: first, book: book, title: title)
                        let scale = min(1, 320 / v.size.width)
                        v.scaleEffect(scale, anchor: .topLeading)
                            .frame(width: v.size.width * scale, height: v.size.height * scale, alignment: .topLeading)
                            .shadow(color: .black.opacity(0.15), radius: 4)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("部門を選んでください").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("印刷・PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button { printNow(pages, book: book) } label: { Label("印刷", systemImage: "printer") }
                        .disabled(pages.isEmpty || busy)
                    Button { share(pages, book: book) } label: { Label("PDFを共有", systemImage: "square.and.arrow.up") }
                        .disabled(pages.isEmpty || busy)
                }
            }
            .sheet(item: $shareFile) { f in ShareSheet(items: [f.url]) }
            .presentationDetents([.large])
            .onAppear { if selected.isEmpty { selected = Set(depts.map(\.id)) } }
        }
    }

    private func pdfURL(_ pages: [PrintPageSpec], book: ShiftBook) throws -> URL {
        let data = PDFMaker.make(pages: pages, book: book, title: title)
        let m = MonthKey(anchor)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("シフト表_\(m.year)年\(m.month)月.pdf")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// LINE・メール・AirDrop・ファイルに保存 など（iPad の共有）
    private func share(_ pages: [PrintPageSpec], book: ShiftBook) {
        PrintTip().invalidate(reason: .actionPerformed)
        busy = true
        defer { busy = false }
        if let url = try? pdfURL(pages, book: book) { shareFile = ExportFile(url: url) }
    }

    private func printNow(_ pages: [PrintPageSpec], book: ShiftBook) {
        busy = true
        defer { busy = false }
        guard let url = try? pdfURL(pages, book: book) else { return }
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .grayscale
        info.jobName = url.deletingPathExtension().lastPathComponent
        let c = UIPrintInteractionController.shared
        c.printInfo = info
        c.printingItem = url
        c.present(animated: true)
    }
}
