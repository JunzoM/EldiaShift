import SwiftUI
import UIKit

// MARK: - 印刷・PDF（PC版の「印刷 / PDF」と同じ4つの形式。白黒で印刷しても見分けられる）

enum PrintFormat: String, CaseIterable, Identifiable {
    case weekByDepartment       // ① 週表示・縦（部門ごとに1枚）
    case monthByDepartment      // ② 月表示・縦（部門ごと × 前半／後半）
    case monthCombined          // ③ 月表示・縦（選んだ部門を1枚にまとめる × 前半／後半）
    case monthLandscape         // ④ 月表示・横（前半を上・後半を下に1枚）
    case monthSingle            // ⑤ 月表示・横（1か月を1つの表）

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekByDepartment: "① 週表示・縦（部門ごと）"
        case .monthByDepartment: "② 月表示・縦（部門ごと）"
        case .monthCombined: "③ 月表示・縦（部門をまとめて）"
        case .monthLandscape: "④ 月表示・横（前半・後半を1枚に）"
        case .monthSingle: "⑤ 月表示・横（1か月を1つの表）"
        }
    }

    var landscape: Bool { self == .monthLandscape || self == .monthSingle }
    var usesHalf: Bool { self == .monthByDepartment || self == .monthCombined }
}

enum HalfSelection: String, CaseIterable, Identifiable {
    case first, second, both
    var id: String { rawValue }
    var title: String { self == .first ? "前半のみ" : self == .second ? "後半のみ" : "両方" }
}

/// 用紙。A3 は A4 と同じ割り付けを √2 倍に大きくする（文字が大きくなる。壁に貼るとき用）
enum PaperSize: String, CaseIterable, Identifiable, Sendable {
    case a4, a3
    var id: String { rawValue }
    var title: String { self == .a4 ? "A4" : "A3" }
    /// A4 に対する倍率
    var scale: CGFloat { self == .a4 ? 1 : 841.89 / 595.28 }
}

/// 表に出すもの
struct PrintOptions: Equatable, Sendable {
    var paper: PaperSize = .a4
    /// 名前を出す（オフは番号だけ。掲示するとき用）
    var showNames = true
    /// 出勤・退勤の時刻を出す（オフは勤務の記号だけ）
    var showTimes = true
    /// マスのメモを表の下に一覧で出す
    var showNotes = false
}

/// 1枚分の内容
struct PrintPageSpec: Identifiable {
    let id = UUID()
    var label: String
    /// 表（上から順に。④は前半・後半の2つ）
    var tables: [(caption: String?, days: [DayKey])]
    var departmentIDs: [String]
    var landscape: Bool
    var paper: PaperSize = .a4
    /// 人数が多くて分けたとき、この枚に載せる人（「部門ID|スタッフID」。nil は全員）
    var memberKeys: Set<String>? = nil

    /// 用紙の大きさ（pt）
    var size: CGSize {
        let base = PrintLayout.base(landscape)
        return CGSize(width: base.width * paper.scale, height: base.height * paper.scale)
    }
}

/// 1枚の割り付け（A4 の pt で考える。A3 はこれを拡大する）
enum PrintLayout {
    static let a4 = CGSize(width: 595.28, height: 841.89)
    static func base(_ landscape: Bool) -> CGSize { landscape ? CGSize(width: a4.height, height: a4.width) : a4 }
    static func margin(_ landscape: Bool) -> CGFloat { landscape ? 17 : 20 }
    /// 表の見出し（日付）の高さ
    static let headerHeight: CGFloat = 26
    /// これより行が低くなるなら、次のページに分ける
    static let minRowHeight: CGFloat = 12
    static let maxRowHeight: CGFloat = 26
    /// メモの一覧に出す行の数（それより多いと「ほか◯件」）
    static let maxNotes = 10
    static let notesHeight: CGFloat = 16 + CGFloat(maxNotes + 1) * 9

    /// 表の行（部門の見出し・人）に使える高さ（表が2つなら1つ分）
    static func rowsHeight(_ spec: PrintPageSpec, notes: Bool) -> CGFloat {
        let page = Self.base(spec.landscape)
        let tables = CGFloat(spec.tables.count)
        // 上下の余白・見出しの行・表と表のあいだ・日付の見出し・メモの一覧
        let fixed: CGFloat = margin(spec.landscape) * 2 + 24 + (tables - 1) * 18 + tables * headerHeight
        let h: CGFloat = page.height - fixed - (notes ? notesHeight : 0)
        return max(0, h / tables)
    }

    /// 部門の見出しと人の行の数
    static func rowCount(_ groups: [DepartmentGroup]) -> Int {
        groups.reduce(0) { $0 + 1 + $1.members.count }
    }

    static func rowHeight(_ spec: PrintPageSpec, groups: [DepartmentGroup], notes: Bool) -> CGFloat {
        min(maxRowHeight, max(minRowHeight, rowsHeight(spec, notes: notes) / CGFloat(max(1, rowCount(groups)))))
    }

    /// 1枚に載る行の数（部門の見出しを含む）
    static func capacity(_ spec: PrintPageSpec, notes: Bool) -> Int {
        max(2, Int(rowsHeight(spec, notes: notes) / minRowHeight))
    }
}

/// マスのメモ（印刷の一覧用）
struct PrintNote: Hashable {
    var day: DayKey
    var who: String
    var text: String
}

enum PrintPlanner {
    static func pages(format: PrintFormat, half: HalfSelection, departments: [Department],
                      anchor: DayKey, paper: PaperSize = .a4) -> [PrintPageSpec] {
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
                PrintPageSpec(label: String(format: label, d.name), tables: [(nil, w)], departmentIDs: [d.id], landscape: false, paper: paper)
            }
        case .monthByDepartment:
            return departments.flatMap { d in
                chunks.map { c in
                    PrintPageSpec(label: "\(ym)　\(d.name)　\(range(c))", tables: [(nil, c)], departmentIDs: [d.id], landscape: false,
                                  paper: paper)
                }
            }
        case .monthCombined:
            let names = departments.map(\.name).joined(separator: "・")
            return chunks.map { c in
                PrintPageSpec(label: "\(ym)　\(names)　\(range(c))", tables: [(nil, c)], departmentIDs: departments.map(\.id),
                              landscape: false, paper: paper)
            }
        case .monthLandscape:
            let names = departments.map(\.name).joined(separator: "・")
            return [PrintPageSpec(label: "\(ym)　\(names)",
                                  tables: [("前半（1〜\(h1.last!.day)日）", h1), ("後半（\(h2.first!.day)〜\(h2.last!.day)日）", h2)],
                                  departmentIDs: departments.map(\.id), landscape: true, paper: paper)]
        case .monthSingle:
            let names = departments.map(\.name).joined(separator: "・")
            return [PrintPageSpec(label: "\(ym)　\(names)", tables: [(nil, all)], departmentIDs: departments.map(\.id),
                                  landscape: true, paper: paper)]
        }
    }

    /// 人数が多くて行が低くなりすぎる枚を、部門・人の順に何枚かに分ける（見出しに「（1/2）」を付ける）
    static func paginate(_ specs: [PrintPageSpec], book: ShiftBook, options: PrintOptions) -> [PrintPageSpec] {
        specs.flatMap { spec -> [PrintPageSpec] in
            let groups = Self.groups(for: spec, book: book)
            let notes = options.showNotes && !Self.notes(for: spec, groups: groups, book: book, showNames: options.showNames).isEmpty
            let capacity = PrintLayout.capacity(spec, notes: notes)
            guard PrintLayout.rowCount(groups) > capacity else { return [spec] }
            var chunks: [Set<String>] = []
            var current: Set<String> = [], used = 0
            for g in groups {
                var headed = false
                for m in g.members {
                    var cost = headed ? 1 : 2
                    if used + cost > capacity, !current.isEmpty {
                        chunks.append(current)
                        current = []; used = 0; headed = false; cost = 2
                    }
                    current.insert(memberKey(g, m))
                    used += cost
                    headed = true
                }
            }
            if !current.isEmpty { chunks.append(current) }
            guard chunks.count > 1 else { return [spec] }
            return chunks.enumerated().map { i, keys in
                PrintPageSpec(label: spec.label + "（\(i + 1)/\(chunks.count)）", tables: spec.tables, departmentIDs: spec.departmentIDs,
                              landscape: spec.landscape, paper: spec.paper, memberKeys: keys)
            }
        }
    }

    static func memberKey(_ g: DepartmentGroup, _ m: StaffMember) -> String { g.department.id + "|" + m.id }

    /// その枚に載せる部門と人
    static func groups(for spec: PrintPageSpec, book: ShiftBook) -> [DepartmentGroup] {
        let month = MonthKey(spec.tables.first?.days.first ?? .today)
        let groups = book.staffByDepartment(visibleIn: month).filter { spec.departmentIDs.contains($0.department.id) }
        guard let keys = spec.memberKeys else { return groups }
        return groups.compactMap { g -> DepartmentGroup? in
            let members = g.members.filter { keys.contains(memberKey(g, $0)) }
            guard !members.isEmpty else { return nil }
            var next = g
            next.members = members
            return next
        }
    }

    /// その枚の人・日のマスのメモ（日付の順）
    static func notes(for spec: PrintPageSpec, groups: [DepartmentGroup], book: ShiftBook, showNames: Bool) -> [PrintNote] {
        let days = Set(spec.tables.flatMap { $0.days }).sorted()
        var result: [PrintNote] = []
        for g in groups {
            for m in g.members {
                for d in days where !m.hasLeft(on: d) {
                    guard let note = Schedule.resolve(m, on: d, in: book)?.note?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !note.isEmpty else { continue }
                    result.append(PrintNote(day: d, who: showNames ? m.name : "No.\(m.number)", text: note))
                }
            }
        }
        return result.sorted { ($0.day, $0.who) < ($1.day, $1.who) }
    }
}

/// 1枚（A4 の pt で割り付け、A3 なら拡大する）
struct PrintPageView: View {
    let spec: PrintPageSpec
    let book: ShiftBook
    let title: String
    var options = PrintOptions()

    static let a4 = PrintLayout.a4
    var size: CGSize { spec.size }

    var body: some View {
        let base = PrintLayout.base(spec.landscape)
        let margin = PrintLayout.margin(spec.landscape)
        let groups = PrintPlanner.groups(for: spec, book: book)
        let notes = options.showNotes ? PrintPlanner.notes(for: spec, groups: groups, book: book, showNames: options.showNames) : []
        let rowH = PrintLayout.rowHeight(spec, groups: groups, notes: !notes.isEmpty)
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

            ForEach(Array(spec.tables.enumerated()), id: \.offset) { _, t in
                if let c = t.caption {
                    Text(c).font(.system(size: 7, weight: .bold)).foregroundStyle(Color(white: 0.33)).padding(.top, 2)
                }
                PrintTable(days: t.days, groups: groups, book: book, landscape: spec.landscape,
                           width: base.width - margin * 2, rowHeight: rowH, options: options)
            }
            if !notes.isEmpty { notesList(notes) }
            Spacer(minLength: 0)
        }
        .padding(margin)
        .frame(width: base.width, height: base.height, alignment: .topLeading)
        .scaleEffect(spec.paper.scale, anchor: .topLeading)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(Color.black)
        .environment(\.colorScheme, .light)
    }

    private func notesList(_ notes: [PrintNote]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("■ マスのメモ").font(.system(size: 7.5, weight: .heavy)).padding(.bottom, 2)
            ForEach(Array(notes.prefix(PrintLayout.maxNotes).enumerated()), id: \.offset) { _, n in
                Text("\(n.day.month)/\(n.day.day)　\(n.who)：\(n.text)")
                    .font(.system(size: 7)).lineLimit(1).truncationMode(.tail)
                    .frame(height: 8, alignment: .leading)
            }
            if notes.count > PrintLayout.maxNotes {
                Text("ほか \(notes.count - PrintLayout.maxNotes)件（アプリのシフト表で確かめてください）")
                    .font(.system(size: 6.5)).foregroundStyle(Color(white: 0.33))
            }
        }
        .padding(.top, 6)
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
    var options = PrintOptions()

    private var noW: CGFloat { options.showNames ? 14 : 20 }
    private var nameW: CGFloat { options.showNames ? (landscape ? 42 : 46) : 0 }
    private var ioW: CGFloat { options.showTimes ? 10 : 0 }
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
            if options.showNames { headCell("氏名", nameW, size: 8) }
            if options.showTimes {
                VStack(spacing: 0) { Text("入"); Text("出") }
                    .font(.system(size: 5, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: ioW, height: PrintLayout.headerHeight).background(Color(white: 0.2))
            }
            ForEach(days, id: \.self) { d in
                let sun = d.weekday == 0, sat = d.weekday == 6
                VStack(spacing: 0) {
                    Text(days.count <= 7 ? "\(d.month)/\(d.day)" : "\(d.day)").font(.system(size: 8, weight: .heavy))
                    Text(sun ? "㊐" : sat ? "㊏" : ["日", "月", "火", "水", "木", "金", "土"][d.weekday])
                        .font(.system(size: 6.5)).opacity(0.85)
                }
                .minimumScaleFactor(0.6)
                .foregroundStyle(.white)
                .frame(width: cellW, height: PrintLayout.headerHeight)
                .background(sun ? Color(white: 0.33) : sat ? Color(white: 0.53) : .black)
                .overlay(alignment: .bottom) { if sun || sat { Rectangle().fill(.white).frame(height: 2) } }
            }
            headCell("計", sumW, size: 7)
        }
    }

    private func headCell(_ t: String, _ w: CGFloat, size: CGFloat) -> some View {
        Text(t).font(.system(size: size, weight: .bold)).foregroundStyle(.white)
            .frame(width: w, height: PrintLayout.headerHeight).background(Color.black)
            .border(Color.black, width: 0.5)
    }

    private func row(_ m: StaffMember) -> some View {
        // 計：月の表は月全体の実働（前半・後半どちらの表でも同じ。PC版と同じ）、週の表はその週の実働
        let total = MonthSummary.of(m, days: days.count <= 7 ? days : MonthKey(days[0]).days, in: book).hours
        let fs: CGFloat = landscape ? 7 : 7.5
        return HStack(spacing: 0) {
            Text("\(m.number)").font(.system(size: options.showNames ? 7 : 8, weight: options.showNames ? .regular : .bold))
                .foregroundStyle(Color(white: options.showNames ? 0.33 : 0))
                .frame(width: noW, height: rowHeight).border(Color(white: 0.33), width: 0.5)
            if options.showNames {
                Text(m.name).font(.system(size: 9, weight: .bold)).lineLimit(1).minimumScaleFactor(0.5)
                    .frame(width: nameW, height: rowHeight).border(Color(white: 0.8), width: 0.5)
            }
            if options.showTimes {
                VStack(spacing: 0) {
                    Text("入").frame(maxHeight: .infinity)
                    Rectangle().fill(Color(white: 0.73)).frame(height: 0.3)
                    Text("出").frame(maxHeight: .infinity)
                }
                .font(.system(size: 6.5, weight: .heavy))
                .frame(width: ioW, height: rowHeight).background(Color(white: 0.92)).border(Color(white: 0.33), width: 0.5)
            }
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
        let noted = options.showNotes && !(r?.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ZStack {
            bg
            if left {
                Text("×").font(.system(size: 7)).foregroundStyle(Color(white: 0.6))
            } else if let r, r.isOff {
                if r.blockID == "off2" || r.blockID == "off3" {
                    Text(r.blockID == "off2" ? "有" : "欠").font(.system(size: 8, weight: .heavy))
                        .frame(width: 11, height: 11).overlay(Circle().stroke(Color.black, lineWidth: 1))
                }
            } else if let r, options.showTimes {
                VStack(spacing: 0) {
                    Text(short(r.inTime)).frame(maxHeight: .infinity)
                    Rectangle().fill(Color(white: 0.73)).frame(height: 0.3)
                    Text(short(r.outTime)).frame(maxHeight: .infinity)
                }
                .font(.system(size: fs, weight: .bold, design: .monospaced))
                .minimumScaleFactor(0.6)
            } else if let r {
                Text(mark(r, m)).font(.system(size: fs + 1, weight: .bold))
                    .lineLimit(1).minimumScaleFactor(0.5).padding(.horizontal, 1)
            }
        }
        .frame(width: cellW, height: rowHeight)
        .overlay(alignment: .topTrailing) {
            // メモのあるマス（下の一覧に出る）
            if noted { Text("*").font(.system(size: 6, weight: .heavy)).padding(.trailing, 1) }
        }
        .border(sun || sat ? Color(white: 0.33) : line, width: 0.5)
    }

    /// 時刻を出さないときの勤務の記号（ひな形の略称・名前。ひな形と時刻が違えば「出」）
    private func mark(_ r: ResolvedShift, _ m: StaffMember) -> String {
        guard let b = book.block(r.blockID, for: m), b.inTime == r.inTime, b.outTime == r.outTime else { return "出" }
        return b.short.isEmpty ? b.label : b.short
    }

    /// 印刷では先頭の0を取る（09:00 → 9:00）
    private func short(_ t: String) -> String { t.hasPrefix("0") ? String(t.dropFirst()) : t }
}

// MARK: - PDF にする

enum PDFMaker {
    /// 1枚ずつ作り、合間に画面を動かす（枚数が多くても固まって見えないように）
    @MainActor
    static func makeAsync(pages: [PrintPageSpec], book: ShiftBook, title: String, options: PrintOptions = PrintOptions(),
                          progress: (Int) -> Void = { _ in }) async -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return Data() }
        var box = CGRect(origin: .zero, size: PrintLayout.a4)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        for (i, spec) in pages.enumerated() {
            progress(i + 1)
            await Task.yield()
            render(spec, book: book, title: title, options: options, into: ctx)
        }
        ctx.closePDF()
        return data as Data
    }

    @MainActor
    private static func render(_ spec: PrintPageSpec, book: ShiftBook, title: String, options: PrintOptions, into ctx: CGContext) {
        let view = PrintPageView(spec: spec, book: book, title: title, options: options)
        var media = CGRect(origin: .zero, size: view.size)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(view.size)
        renderer.render { _, draw in
            ctx.beginPage(mediaBox: &media)
            draw(ctx)
            ctx.endPage()
        }
    }

    @MainActor
    static func make(pages: [PrintPageSpec], book: ShiftBook, title: String, options: PrintOptions = PrintOptions()) -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return Data() }
        var box = CGRect(origin: .zero, size: PrintLayout.a4)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        for spec in pages { render(spec, book: book, title: title, options: options, into: ctx) }
        ctx.closePDF()
        return data as Data
    }
}

// MARK: - 印刷・PDF の画面

struct PrintSheet: View {
    let anchor: DayKey
    /// サイドバーの項目として開いたとき（「閉じる」を出さない）
    var inTab = false

    @Environment(\.shiftStore) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// 画面で選び直した月（nil は開いたときの月）
    @State private var target: DayKey?
    private var day: DayKey { target ?? anchor }
    @AppStorage("printOutput") private var output: OutputKind = .pdf
    @State private var wideTab = 0
    @State private var csvFile: ExportFile?
    @AppStorage("printFormat") private var format: PrintFormat = .monthByDepartment
    @AppStorage("printHalf") private var half: HalfSelection = .both
    @AppStorage("printTitle") private var title = ""
    @AppStorage("printPaper") private var paper: PaperSize = .a4
    @AppStorage("printShowNames") private var showNames = true
    @AppStorage("printShowTimes") private var showTimes = true
    @AppStorage("printShowNotes") private var showNotes = false
    /// 全ページのプレビュー
    @State private var previewAll = false
    private var options: PrintOptions {
        PrintOptions(paper: paper, showNames: showNames, showTimes: showTimes, showNotes: showNotes)
    }
    /// 表の上に出す名前（空で店舗が2つ以上なら、見ている店舗の名前）
    private var effectiveTitle: String {
        title.isEmpty && store.book.allStores.count > 1 ? store.currentStore.name : title
    }
    @State private var selected: Set<String> = []
    @State private var shareFile: ExportFile?
    @State private var busy = false
    @State private var progress = 0
    @State private var failure: String?
    /// 変更点の文章も一緒に送る
    @AppStorage("shareWithChanges") private var withChanges = true
    @State private var images: ImageFiles?
    @State private var publishedNote: String?

    struct ImageFiles: Identifiable {
        let urls: [URL]
        var id: String { urls.map(\.path).joined() }
    }

    var body: some View {
        let book = store.book
        let depts = book.scopedDepartments
            .filter { d in book.staff.contains { $0.departmentID == d.id } }
        let chosen = depts.filter { selected.contains($0.id) }
        let pages = chosen.isEmpty ? []
            : PrintPlanner.paginate(PrintPlanner.pages(format: format, half: half, departments: chosen, anchor: day, paper: paper),
                                    book: book, options: options)

        NavigationStack {
            Group {
                if sizeClass == .regular {
                    wideLayout(book: book, depts: depts, chosen: chosen, pages: pages)
                } else {
                    formLayout(book: book, depts: depts, chosen: chosen, pages: pages)
                }
            }
            .navigationTitle("印刷・出力")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !inTab {
                    ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
                }
            }
            // iPhone：印刷・共有は下に大きく（見つけやすく、押しやすく）
            .safeAreaInset(edge: .bottom) {
                if sizeClass != .regular { bottomBar(pages: pages, book: book) }
            }
            .shiftSheet(item: $csvFile) { f in ShareSheet(items: [f.url]) }
            .coachOverlay(.sheet)
            .shiftSheet(item: $shareFile) { f in
                ShareSheet(items: shareItems(f.url, book: book)) { done in if done { publish() } }
            }
            .shiftSheet(item: $images) { f in ShareSheet(items: f.urls) }
            .shiftSheet(isPresented: $previewAll) {
                PrintPreviewSheet(pages: pages, book: book, title: effectiveTitle, options: options)
            }
            .alert("公開済みにしました", isPresented: Binding(get: { publishedNote != nil }, set: { if !$0 { publishedNote = nil } })) {
                Button("OK") { publishedNote = nil }
            } message: { Text(publishedNote ?? "") }
            .errorAlert($failure)
            .interactiveDismissDisabled(busy)
            .presentationDetents([.large])
            .onAppear {
                if selected.isEmpty { selected = Set(depts.map(\.id)) }
                CoachCenter.shared.show(.print(), after: 0.7)
            }
        }
    }

    // MARK: iPhone：今までの縦に並ぶ画面

    @ViewBuilder
    private func formLayout(book: ShiftBook, depts: [Department], chosen: [Department], pages: [PrintPageSpec]) -> some View {
            Form {
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
                Picker("用紙", selection: $paper) {
                    ForEach(PaperSize.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                displayToggles
            } header: {
                Text("用紙・表に出すもの")
            } footer: {
                Text("A3 は A4 と同じ割り付けを大きくします（壁に貼るとき用）。人数が多くて1枚に入らないときは、自動で次のページに分けます。")
            }
            Section {
                TextField("表の上に出す名前（例：店名）", text: $title)
            } footer: {
                Text("白黒で印刷しても見分けられるよう、日曜は濃い灰色・土曜は中くらいの灰色にします。有休は○有、当欠は○欠で印刷し、公休は空白にします。")
            }

            changesSection(book)
            Section {
                Button {
                    makeImages(chosen, book: book)
                } label: {
                    Label("一人ずつのシフト画像を作って送る", systemImage: "person.crop.rectangle.stack")
                }
                .disabled(chosen.isEmpty || busy)
            } header: {
                Text("一人ずつ")
            } footer: {
                Text("選んだ部門の全員分、\(MonthKey(day).month)月の自分のシフトだけの縦長の画像を作ります。LINE で本人に送れます。")
            }

            Section("プレビュー（\(pages.count)枚）") {
                if let first = pages.first {
                    let v = PrintPageView(spec: first, book: book, title: effectiveTitle, options: options)
                    let scale = min(1, 320 / v.size.width)
                    v.scaleEffect(scale, anchor: .topLeading)
                        .frame(width: v.size.width * scale, height: v.size.height * scale, alignment: .topLeading)
                        .shadow(color: .black.opacity(0.15), radius: 4)
                        .frame(maxWidth: .infinity)
                    Button { previewAll = true } label: {
                        Label("全ページを見る（\(pages.count)枚）", systemImage: "doc.on.doc")
                    }
                } else {
                    Text("部門を選んでください").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func bottomBar(pages: [PrintPageSpec], book: ShiftBook) -> some View {
                HStack(spacing: 12) {
            Button { printNow(pages, book: book) } label: {
                Label("印刷", systemImage: "printer").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Button { share(pages, book: book) } label: {
                Label("PDFを共有", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .coachTarget("printShare")
        }
        .controlSize(.large)
        .disabled(pages.isEmpty || busy)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
        .overlay {
            if busy {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("作成中… \(progress)枚目").appFont(.subheadline).monospacedDigit()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.bar)
            }
        }
    }

    // MARK: iPad：出力形式・出力設定・プレビューの3列

    @ViewBuilder
    private func wideLayout(book: ShiftBook, depts: [Department], chosen: [Department], pages: [PrintPageSpec]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                underlineTab("シフト表", 0)
                underlineTab("一人ずつの画像", 1)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 8)
            .overlay(alignment: .bottom) { Divider() }

            if wideTab == 0 {
                HStack(alignment: .top, spacing: 16) {
                    panel("出力形式") {
                        VStack(spacing: 10) {
                            ForEach(OutputKind.allCases) { outputCard($0) }
                        }
                    }
                    .frame(width: 240)
                    panel("出力設定") {
                        ScrollView { settingsColumn(book: book, depts: depts) }
                    }
                    .frame(maxWidth: .infinity)
                    panel("プレビュー") {
                        previewColumn(book: book, chosen: chosen, pages: pages)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(16)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    panel("対象") {
                        ScrollView { VStack(alignment: .leading, spacing: 18) { monthRow; departmentChecks(depts) } }
                    }
                    .frame(width: 300)
                    panel("一人ずつのシフト画像") {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("選んだ部門の全員分、\(MonthKey(day).month)月の自分のシフトだけの縦長の画像を作ります。LINE で本人に送れます。")
                                .appFont(.subheadline).foregroundStyle(.secondary)
                            if let m = book.staffByDepartment(visibleIn: MonthKey(day))
                                .first(where: { g in chosen.contains { $0.id == g.department.id } })?.members.first {
                                ScrollView {
                                    PersonalScheduleImage(member: m, month: MonthKey(day), book: book, title: effectiveTitle)
                                        .scaleEffect(0.8, anchor: .top)
                                        .shadow(color: .black.opacity(0.12), radius: 6)
                                }
                            }
                            Spacer(minLength: 0)
                            bigButton("画像を作って送る", systemImage: "person.crop.rectangle.stack", disabled: chosen.isEmpty) {
                                makeImages(chosen, book: book)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(16)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private func underlineTab(_ title: String, _ tag: Int) -> some View {
        let on = wideTab == tag
        return Button { wideTab = tag } label: {
            Text(title)
                .appFont(.subheadline.weight(on ? .bold : .medium))
                .foregroundStyle(on ? Color.accentColor : Color.secondary)
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(on ? Color.accentColor : Color.clear).frame(height: 2.5)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func panel<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).appFont(.headline)
            content()
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous))
    }

    private func outputCard(_ k: OutputKind) -> some View {
        let on = output == k
        return Button { output = k } label: {
            HStack(spacing: 12) {
                Image(systemName: k.systemImage).appFont(.title2).foregroundStyle(k.color)
                    .frame(width: 40, height: 40)
                    .background(k.color.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(k.title).appFont(.subheadline.weight(.bold)).foregroundStyle(.primary)
                    Text(k.detail).appFont(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(on ? Color.accentColor.opacity(0.07) : Color(.systemBackground),
                        in: RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous)
                .strokeBorder(on ? Color.accentColor : Color(.separator), lineWidth: on ? 2 : 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// 表に出すもの（名前・時刻・メモ）
    @ViewBuilder
    private var displayToggles: some View {
        Toggle("名前を出す（オフは番号だけ）", isOn: $showNames)
        Toggle("出勤・退勤の時刻を出す（オフは勤務の記号）", isOn: $showTimes)
        Toggle("マスのメモを表の下に出す", isOn: $showNotes)
    }

    private var monthRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("対象期間").appFont(.subheadline.weight(.semibold))
            HStack {
                Button { target = DayKey(MonthKey(day).adding(months: -1).year, MonthKey(day).adding(months: -1).month, 1) } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("前の月")
                Spacer()
                Text(MonthKey(day).description).appFont(.body.weight(.semibold)).monospacedDigit()
                Spacer()
                Button { target = DayKey(MonthKey(day).adding(months: 1).year, MonthKey(day).adding(months: 1).month, 1) } label: {
                    Image(systemName: "chevron.right")
                }
                .accessibilityLabel("次の月")
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous).strokeBorder(Color(.separator), lineWidth: 0.5))
        }
    }

    private func departmentChecks(_ depts: [Department]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("対象部門").appFont(.subheadline.weight(.semibold))
            ForEach(depts) { d in
                let on = selected.contains(d.id)
                Button {
                    if on { selected.remove(d.id) } else { selected.insert(d.id) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: on ? "checkmark.square.fill" : "square")
                            .foregroundStyle(on ? Color.accentColor : Color.secondary)
                        Text(d.name).foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private func settingsColumn(book: ShiftBook, depts: [Department]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            monthRow
            if output != .csv {
                VStack(alignment: .leading, spacing: 6) {
                    Text("レイアウト").appFont(.subheadline.weight(.semibold))
                    Picker("レイアウト", selection: $format) {
                        ForEach(PrintFormat.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if format.usesHalf {
                        Picker("印刷範囲", selection: $half) {
                            ForEach(HalfSelection.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    Picker("用紙", selection: $paper) {
                        ForEach(PaperSize.allCases) { Text("用紙 \($0.title)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text("A3 は A4 と同じ割り付けを大きくします。人数が多くて1枚に入らないときは、自動で次のページに分けます。")
                        .appFont(.caption).foregroundStyle(.secondary)
                }
            }
            departmentChecks(depts)
            VStack(alignment: .leading, spacing: 6) {
                Text("表示オプション").appFont(.subheadline.weight(.semibold))
                TextField("表の上に出す名前（例：店名）", text: $title)
                    .textFieldStyle(.roundedBorder)
                if output != .csv { displayToggles.appFont(.subheadline) }
                if output == .pdf {
                    Toggle("変更点の文章も一緒に送る", isOn: $withChanges).appFont(.subheadline)
                }
            }
            let month = MonthKey(day)
            if let diff = PublishDiff.changes(book, month: month) {
                Label(diff.changes.isEmpty ? "前回の公開から変更はありません" : "前回の公開から \(diff.changes.count)件の変更",
                      systemImage: "paperplane").appFont(.caption).foregroundStyle(.secondary)
            } else {
                Label("\(month.month)月分はまだ公開していません（送るか印刷すると公開済みになります）", systemImage: "paperplane")
                    .appFont(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func previewColumn(book: ShiftBook, chosen: [Department], pages: [PrintPageSpec]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if output == .csv {
                VStack(spacing: 8) {
                    Image(systemName: "tablecells").appFont(.system(size: 44)).foregroundStyle(OutputKind.csv.color)
                    Text("\(MonthKey(day).description)・\(chosen.map(\.name).joined(separator: "・"))")
                        .appFont(.subheadline.weight(.semibold))
                    Text("1行が1人、1列が1日。Excel・Numbers で開けます。").appFont(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let first = pages.first {
                GeometryReader { g in
                    let v = PrintPageView(spec: first, book: book, title: effectiveTitle, options: options)
                    let k = min(1, g.size.width / v.size.width, g.size.height / v.size.height)
                    v.scaleEffect(k, anchor: .topLeading)
                        .frame(width: v.size.width * k, height: v.size.height * k, alignment: .topLeading)
                        .shadow(color: .black.opacity(0.15), radius: 5)
                        .frame(maxWidth: .infinity)
                }
                Button { previewAll = true } label: {
                    Label("全ページを見る（\(pages.count)枚）", systemImage: "doc.on.doc").appFont(.caption)
                }
                .frame(maxWidth: .infinity)
            } else {
                Text("部門を選んでください").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            bigButton(output.actionTitle, systemImage: output.systemImage, disabled: output == .csv ? chosen.isEmpty : pages.isEmpty) {
                switch output {
                case .pdf: share(pages, book: book)
                case .print: printNow(pages, book: book)
                case .csv: shareCSV(chosen, book: book)
                }
            }
            .coachTarget("printShare")
        }
    }

    private func bigButton(_ title: String, systemImage: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if busy {
                    HStack(spacing: 8) {
                        ProgressView().tint(.white)
                        Text("作成中… \(progress)").monospacedDigit()
                    }
                } else {
                    Label(title, systemImage: systemImage)
                }
            }
            .appFont(.headline)
            .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(disabled || busy)
    }

    /// CSV（Excel 用に先頭に BOM。1行が1人、1列が1日）
    private func shareCSV(_ chosen: [Department], book: ShiftBook) {
        let month = MonthKey(day)
        let ids = Set(chosen.map(\.id))
        let groups = book.staffByDepartment(visibleIn: month).filter { ids.contains($0.department.id) }
        do {
            let text = ShiftCSV.make(groups: groups, month: month, book: book)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("シフト表_\(month.year)年\(month.month)月.csv")
            try Data(("\u{FEFF}" + text).utf8).write(to: url, options: .atomic)
            csvFile = ExportFile(url: url)
        } catch {
            failure = "CSVを作れませんでした（\(error.localizedDescription)）"
        }
    }

    private func pdfURL(_ pages: [PrintPageSpec], book: ShiftBook) async throws -> URL {
        let data = await PDFMaker.makeAsync(pages: pages, book: book, title: effectiveTitle, options: options) { progress = $0 }
        if data.isEmpty { throw CocoaError(.fileWriteUnknown) }
        let m = MonthKey(day)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("シフト表_\(m.year)年\(m.month)月.pdf")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// LINE・メール・AirDrop・ファイルに保存 など（iPad の共有）
    private func share(_ pages: [PrintPageSpec], book: ShiftBook) {
        guard !busy else { return }
        busy = true; progress = 0
        Task {
            defer { busy = false }
            do { shareFile = ExportFile(url: try await pdfURL(pages, book: book)) }
            catch { failure = "PDFを作れませんでした（\(error.localizedDescription)）" }
        }
    }

    private func printNow(_ pages: [PrintPageSpec], book: ShiftBook) {
        guard !busy else { return }
        busy = true; progress = 0
        Task {
            defer { busy = false }
            do { presentPrint(try await pdfURL(pages, book: book)) }
            catch { failure = "印刷用のPDFを作れませんでした（\(error.localizedDescription)）" }
        }
    }

    private func presentPrint(_ url: URL) {
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .grayscale
        info.jobName = url.deletingPathExtension().lastPathComponent
        let c = UIPrintInteractionController.shared
        c.printInfo = info
        c.printingItem = url
        c.present(animated: true) { _, completed, _ in
            if completed { publish() }
        }
    }

    // MARK: 公開と変更点

    @ViewBuilder
    private func changesSection(_ book: ShiftBook) -> some View {
        let month = MonthKey(day)
        let diff = PublishDiff.changes(book, month: month)
        Section {
            if let diff {
                if diff.changes.isEmpty {
                    Text("前回の公開から変更はありません").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(diff.changes.prefix(8).enumerated()), id: \.offset) { item in
                        let c = item.element
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(c.day.month)/\(c.day.day)").monospacedDigit().frame(width: 44, alignment: .leading)
                            Text(c.staffName).bold()
                            Text("\(c.before.isEmpty ? "なし" : c.before) → \(c.after.isEmpty ? "なし" : c.after)")
                                .appFont(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    if diff.changes.count > 8 {
                        Text("ほか \(diff.changes.count - 8)件").appFont(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle("PDFと一緒に変更点の文章も送る", isOn: $withChanges)
            } else {
                Text("\(month.month)月分はまだ公開していません。").foregroundStyle(.secondary)
            }
        } header: {
            Text("\(month.month)月の変更点（前回の公開から）")
        } footer: {
            if let diff {
                Text("前回の公開：\(diff.since.formatted(date: .abbreviated, time: .shortened))。PDFを送るか印刷すると、今の内容を「公開済み」として残し、次からはそこからの変更を出します。")
            } else {
                Text("PDFを送るか印刷すると、今の内容を「公開済み」として残します。次からは、そこからの変更点を LINE などに貼れる文章で一緒に送れます。")
            }
        }
    }

    private func shareItems(_ url: URL, book: ShiftBook) -> [Any] {
        let month = MonthKey(day)
        guard withChanges, let diff = PublishDiff.changes(book, month: month), !diff.changes.isEmpty else { return [url] }
        return [PublishDiff.text(diff.changes, month: month, title: effectiveTitle), url]
    }

    private func publish() {
        let month = MonthKey(day)
        do {
            try store.markPublished(month)
            publishedNote = "\(month.month)月分の今の内容を公開済みとして残しました。次からは、ここからの変更点を出します。"
        } catch {
            failure = "公開の記録を残せませんでした（\(error.localizedDescription)）"
        }
    }

    private func makeImages(_ chosen: [Department], book: ShiftBook) {
        guard !busy else { return }
        let month = MonthKey(day)
        let ids = Set(chosen.map(\.id))
        let members = book.staffByDepartment(visibleIn: month).filter { ids.contains($0.department.id) }.flatMap(\.members)
        busy = true; progress = 0
        Task {
            defer { busy = false }
            do {
                let urls = try await PersonalScheduleImage.files(for: members, month: month, book: book, title: effectiveTitle) { progress = $0 }
                if urls.isEmpty { failure = "画像を作れませんでした" } else { images = ImageFiles(urls: urls) }
            } catch {
                failure = "画像を作れませんでした（\(error.localizedDescription)）"
            }
        }
    }
}

// MARK: - 出力形式

enum OutputKind: String, CaseIterable, Identifiable {
    case pdf, print, csv
    var id: String { rawValue }

    var title: String {
        switch self {
        case .pdf: "PDFで出力"
        case .print: "印刷（AirPrint）"
        case .csv: "CSVで出力"
        }
    }

    var detail: String {
        switch self {
        case .pdf: "PDFを作って LINE・メール・ファイルに送る"
        case .print: "近くのプリンタで印刷する"
        case .csv: "Excel・Numbers で開ける表のファイル"
        }
    }

    var actionTitle: String {
        switch self {
        case .pdf: "PDFを作って送る"
        case .print: "印刷する"
        case .csv: "CSVを作って送る"
        }
    }

    var systemImage: String {
        switch self {
        case .pdf: "doc.richtext"
        case .print: "printer"
        case .csv: "tablecells"
        }
    }

    var color: Color {
        switch self {
        case .pdf: .red
        case .print: .blue
        case .csv: .green
        }
    }
}

// MARK: - CSV

enum ShiftCSV {
    static func make(groups: [DepartmentGroup], month: MonthKey, book: ShiftBook) -> String {
        let wd = ["日", "月", "火", "水", "木", "金", "土"]
        var rows = [(["部門", "番号", "氏名"] + month.days.map { "\($0.day)(\(wd[$0.weekday]))" } + ["勤務日数", "実働時間"])]
        for g in groups {
            for m in g.members {
                let s = MonthSummary.of(m, month: month, in: book)
                let cells = month.days.map { d in PublishedMonth.label(Schedule.resolve(m, on: d, in: book), member: m, book: book) }
                rows.append([g.department.name, "\(m.number)", m.name] + cells + ["\(s.workDays)", String(format: "%.1f", s.hours)])
            }
        }
        return rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    static func escape(_ v: String) -> String {
        guard v.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return v }
        return "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

// MARK: - 全ページのプレビュー

/// 作る PDF の全ページを、送る前に確かめる
struct PrintPreviewSheet: View {
    let pages: [PrintPageSpec]
    let book: ShiftBook
    let title: String
    let options: PrintOptions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GeometryReader { g in
                ScrollView {
                    LazyVStack(spacing: 18) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { i, spec in
                            page(spec, number: i + 1, width: g.size.width - 32)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("プレビュー（\(pages.count)枚）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
        }
    }

    private func page(_ spec: PrintPageSpec, number: Int, width: CGFloat) -> some View {
        let v = PrintPageView(spec: spec, book: book, title: title, options: options)
        let k = min(1, max(0.1, width) / v.size.width)
        return VStack(spacing: 6) {
            v.scaleEffect(k, anchor: .topLeading)
                .frame(width: v.size.width * k, height: v.size.height * k, alignment: .topLeading)
                .shadow(color: .black.opacity(0.15), radius: 4)
            Text("\(number) / \(pages.count)　\(spec.paper.title)\(spec.landscape ? "横" : "縦")")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}
