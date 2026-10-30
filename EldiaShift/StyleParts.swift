import SwiftUI

// MARK: - 見本デザインに寄せた共通の部品

/// 名前の頭文字の丸（顔写真の代わり）
/// 顔写真があれば写真を丸く出す
struct InitialAvatar: View {
    let name: String
    let colorIndex: Int
    var size: CGFloat = 30
    var photo: Data? = nil

    var body: some View {
        Group {
            if let photo, let img = StaffPhoto.image(photo) {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)))
                    .appFont(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(PaletteColor.fg(colorIndex))
                    .frame(width: size, height: size)
                    .background(PaletteColor.bg(colorIndex), in: Circle())
            }
        }
        .accessibilityHidden(true)
    }
}

/// スタッフの顔写真（縮める・表示用に読み込んだ画像を使い回す）
@MainActor
enum StaffPhoto {
    /// 一覧・表で何度も描くので、読み込んだ画像を覚えておく（同じ写真を毎回読み込まない）
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 300
        return c
    }()

    static func image(_ data: Data) -> UIImage? {
        // 写真の中身で見分ける（大きさ＋末尾。JPEG の先頭はどれも似ているので末尾を使う）
        var h = Hasher()
        h.combine(data.count)
        data.suffix(512).withUnsafeBytes { h.combine(bytes: $0) }
        let key = String(h.finalize()) as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let img = UIImage(data: data) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }

    /// 選んだ写真を真ん中で正方形に切り抜き、240px の JPEG に縮める（十数KB）
    nonisolated static func shrink(_ data: Data) -> Data? {
        guard let img = UIImage(data: data), img.size.width > 0, img.size.height > 0 else { return nil }
        let side: CGFloat = 240
        let k = side / min(img.size.width, img.size.height)
        let drawn = CGSize(width: img.size.width * k, height: img.size.height * k)
        let origin = CGPoint(x: (side - drawn.width) / 2, y: (side - drawn.height) / 2)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        let out = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: fmt).image { ctx in
            // 透明な背景（ミー文字など）は白にする（JPEG は透明を持てない）
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            img.draw(in: CGRect(origin: origin, size: drawn))
        }
        return out.jpegData(compressionQuality: 0.7)
    }
}

/// シフトの種類の色付きチップ（早番・遅番・休みなど）
struct ShiftChip: View {
    let text: String
    let colorIndex: Int
    var height: CGFloat = 22
    var fontSize: CGFloat = 11

    var body: some View {
        Text(text)
            .appFont(.system(size: fontSize, weight: .bold))
            .lineLimit(1).minimumScaleFactor(0.6)
            .foregroundStyle(PaletteColor.fg(colorIndex))
            .padding(.horizontal, 5)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(PaletteColor.bg(colorIndex), in: RoundedRectangle(cornerRadius: DS.chipRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.chipRadius, style: .continuous)
                .strokeBorder(PaletteColor.fg(colorIndex).opacity(0.22), lineWidth: 1))
    }

    /// チップに出す名前（3文字までは名前、長ければ略称）
    static func label(_ b: TimeBlock) -> String {
        if b.label.count <= 3 { return b.label }
        return b.short.isEmpty ? String(b.label.prefix(2)) : b.short
    }
}

/// 状態の小さな札（在籍・承認済みなど）
struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .appFont(.caption.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(color.opacity(0.13), in: Capsule())
    }
}

enum ShortTime {
    /// "09:00" → "9"、"13:30" → "13:30"
    static func compact(_ s: String) -> String {
        guard let m = ClockTime.parse(s) else { return s }
        return m % 60 == 0 ? "\(m / 60)" : "\(m / 60):\(String(format: "%02d", m % 60))"
    }
}

extension BrandColor {
    /// サイドバーの色（会社の色を暗くしたもの。未設定は紺）
    static func sidebar(_ hex: UInt32?) -> Color {
        let h = hex ?? 0x1E3A8A
        func d(_ v: UInt32) -> Double { Double(v) / 255 * 0.5 }
        return Color(.sRGB, red: d((h >> 16) & 0xFF), green: d((h >> 8) & 0xFF), blue: d(h & 0xFF))
    }
}

// MARK: - iPad のサイドバー（会社の色の濃い帯）

// MARK: - デザインの決まり（大きさ・余白・角の丸み）
// 画面ごとにばらばらにしないため、数字はここから使う。HOTEL-SHIFT の Mac 版（角丸 14・外側の余白 16）に合わせる。
// 印刷の中身・QR ポスター・似顔絵の絵は紙や画像の決まりがあるので使わない

enum DS {
    /// 画面の外側の余白
    static let page: CGFloat = 16
    /// カード同士・部品同士の間
    static let gap: CGFloat = 12
    /// 見出しのまとまり同士の間
    static let section: CGFloat = 20
    /// カードの内側の余白
    static let cardPadding: CGFloat = 16
    /// カード・面の角の丸み
    static let cardRadius: CGFloat = 14
    /// ボタン・入力・選ぶ部品の角の丸み
    static let controlRadius: CGFloat = 10
    /// 小さな印（勤務の記号・日付のマス）の角の丸み
    static let chipRadius: CGFloat = 8
    /// 切り替え（セグメント）の1つあたりの最小の幅。広い場所では幅いっぱいに伸びる
    static let segmentMin: CGFloat = 88
}

/// 切り替え（セグメント）：1つあたりの最小の幅を決め、それより広い場所では伸びる（文字の倍率に合わせる）
private struct SegmentWidth: ViewModifier {
    let count: Int
    @Environment(\.appZoom) private var zoom

    func body(content: Content) -> some View {
        content
            .pickerStyle(.segmented)
            .frame(minWidth: CGFloat(max(count, 1)) * DS.segmentMin * zoom)
    }
}

extension View {
    /// count：選べるものの数
    func segmented(_ count: Int) -> some View {
        modifier(SegmentWidth(count: count))
    }
}

struct AppSidebar: View {
    @Binding var tab: AppTab
    @Environment(\.shiftStore) private var store
    /// アイコンだけの細いサイドバーにする（端末ごとに覚える）
    @AppStorage("sidebarCompact") private var compact = false
    @Environment(\.appZoom) private var zoom

    static let main: [AppTab] = [.home, .schedule, .requests, .staff, .summary, .print, .stores]
    static let fullWidth: CGFloat = 240
    static let compactWidth: CGFloat = 76

    var body: some View {
        VStack(alignment: compact ? .center : .leading, spacing: 0) {
            HStack(spacing: 10) {
                // 会社のロゴ（無ければ建物の印）
                if let data = store.book.company.logo, let img = StaffPhoto.image(data) {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: DS.chipRadius, style: .continuous))
                } else {
                    Image(systemName: "building.columns.fill").appFont(.title2)
                }
                if !compact {
                    VStack(alignment: .leading, spacing: -2) {
                        // 〇〇 は店舗ごと（店舗管理の「アプリの表示名」）
                        Text(store.currentStore.displayPrefix).appFont(.caption.weight(.heavy))
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text("SHIFT").appFont(.headline.weight(.heavy))
                        if !store.book.company.name.isEmpty {
                            Text(store.book.company.name).appFont(.caption2).opacity(0.75)
                                .lineLimit(1).minimumScaleFactor(0.7).padding(.top, 2)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 0 : 20).padding(.top, 18).padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)

            StoreSwitcher(iconOnly: compact)
                .tint(.white)
                .foregroundStyle(.white)
                .padding(.horizontal, compact ? 0 : 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
                .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous))
                .padding(.horizontal, compact ? 10 : 12).padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Self.main) { item($0) }
                }
                .padding(.horizontal, compact ? 10 : 12)
            }
            Spacer(minLength: 0)
            VStack(spacing: 4) {
                item(.settings)
                collapseButton
            }
            .padding(.horizontal, compact ? 10 : 12).padding(.bottom, 16)
        }
        // 文字を大きくしたら幅も広げる（Mac の 表示 → 拡大）
        .frame(width: (compact ? Self.compactWidth : Self.fullWidth) * zoom)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(BrandColor.sidebar(store.book.brandColor).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    /// たたむ・広げる
    private var collapseButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { compact.toggle() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: compact ? "sidebar.right" : "sidebar.left").frame(width: 22)
                if !compact {
                    Text("サイドバーをたたむ")
                    Spacer(minLength: 0)
                }
            }
            .appFont(compact ? .title3 : .body.weight(.medium))
            .foregroundStyle(Color.white.opacity(0.6))
            .padding(.horizontal, compact ? 0 : 14).padding(.vertical, compact ? 12 : 11)
            .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(compact ? "サイドバーを広げる" : "サイドバーをたたむ")
    }

    private func item(_ t: AppTab) -> some View {
        let on = t == tab
        return Button { tab = t } label: {
            HStack(spacing: 12) {
                Image(systemName: t.systemImage).frame(width: 22)
                if !compact {
                    Text(t.title)
                    Spacer(minLength: 0)
                }
            }
            .appFont(compact ? .title3.weight(on ? .bold : .regular) : .body.weight(on ? .bold : .medium))
            .foregroundStyle(on ? Color.white : Color.white.opacity(0.72))
            .padding(.horizontal, compact ? 0 : 14).padding(.vertical, compact ? 12 : 11)
            .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
            .background(on ? Color.white.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t.title)
        .accessibilityAddTraits(on ? .isSelected : [])
        .help(t.title)
    }
}

// MARK: - 希望休の一覧

struct OffRequestListView: View {
    @Environment(\.shiftStore) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var month = MonthKey.current
    @State private var filter = 0
    @State private var adding = false
    @State private var receiving = false
    @State private var registering = false
    @State private var showingQR = false
    /// 部門で絞り込む（nil はすべて）
    @State private var departmentID: String?
    @State private var reply: LeaveReply?
    @State private var requestError: String?

    private enum State3 { case done, conflict, open }

    private struct Row: Identifiable {
        let member: StaffMember
        let department: Department?
        let day: DayKey
        let state: State3
        var id: String { "\(member.id)|\(day)" }
    }

    var body: some View {
        let book = store.book
        let deptOf = Dictionary(book.departments.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let groups = book.staffByDepartment(visibleIn: month)
        // 店舗を切り替えて、選んでいた部門が無くなったら「すべて」
        let dept = groups.contains { $0.department.id == departmentID } ? departmentID : nil
        let rows: [Row] = groups.filter { dept == nil || $0.department.id == dept }.flatMap(\.members).flatMap { m in
            m.offRequests.compactMap { DayKey($0) }.filter { MonthKey($0) == month }.map { d in
                Row(member: m, department: deptOf[m.departmentID], day: d, state: Self.state(m, d, book))
            }
        }
        .sorted { ($0.day, $0.member.name) < ($1.day, $1.member.name) }
        let conflicts = rows.filter { $0.state == .conflict }.count
        let shown = rows.filter { filter == 0 || (filter == 1 ? $0.state == .conflict : $0.state != .conflict) }

        let deptPicker = Group {
            if groups.count > 1 {
                Section {
                    Picker(selection: Binding(get: { dept }, set: { departmentID = $0 })) {
                        Text("すべての部門").tag(String?.none)
                        ForEach(groups) { g in Text(g.department.name).tag(Optional(g.department.id)) }
                    } label: {
                        Label("部門", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        let monthSections = Group {
            Section {
                Picker("表示", selection: $filter) {
                    Text("すべて \(rows.count)").tag(0)
                    Text("勤務と重なる \(conflicts)").tag(1)
                    Text("問題なし \(rows.count - conflicts)").tag(2)
                }
                .segmented(3)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } header: {
                Text("\(month.month)月の希望休（\(rows.count)日）")
            }
            Section {
                if shown.isEmpty {
                    Text(rows.isEmpty ? "\(month.month)月の希望休はまだありません" : "当てはまる希望休はありません")
                        .foregroundStyle(.secondary)
                }
                ForEach(shown) { r in
                    HStack(spacing: 12) {
                        InitialAvatar(name: r.member.name, colorIndex: r.department?.colorIndex ?? 8, size: 34, photo: r.member.photo)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.member.name).appFont(.body.weight(.semibold))
                            Text(r.department?.name ?? "").appFont(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("希望休").appFont(.subheadline).foregroundStyle(.secondary)
                        Text(HomeView.dayLabel(r.day)).appFont(.subheadline.weight(.semibold)).monospacedDigit()
                            .frame(minWidth: 86, alignment: .trailing)
                        switch r.state {
                        case .done: StatusPill(text: "休み済み", color: .green)
                        case .conflict: StatusPill(text: "勤務あり", color: .red)
                        case .open: StatusPill(text: "未入力", color: .orange)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } footer: {
                Text("「勤務あり」は希望休の日に勤務が入っています。シフト表のマスで休みに変えてください。")
            }
        }

        Group {
            if sizeClass == .compact {
                List {
                    LeaveRequestGuide(showQR: { showingQR = true }, receive: { receiving = true })
                    deptPicker
                    LeaveRequestSections(month: month, departmentID: dept, reply: $reply, error: $requestError)
                    monthSections
                }
            } else {
                // iPad・Mac：左に承認待ち（すぐ決めるもの）、右にその月の希望休と申請の結果
                HStack(spacing: 0) {
                    List {
                        LeaveRequestGuide(showQR: { showingQR = true }, receive: { receiving = true })
                        deptPicker
                        LeaveRequestSections(month: month, departmentID: dept, parts: .pending, reply: $reply, error: $requestError)
                    }
                    .frame(maxWidth: .infinity)
                    Divider()
                    List {
                        monthSections
                        LeaveRequestSections(month: month, departmentID: dept, parts: .decided, reply: $reply, error: $requestError)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("希望休 \(month.description)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button { month = month.adding(months: -1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("前の月")
                Button { month = month.adding(months: 1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("次の月")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showingQR = true } label: { Label("申請用QRコード", systemImage: "qrcode") }
                    .accessibilityLabel("壁に貼る申請用のQRコード")
                Menu {
                    Button { receiving = true } label: { Label("届いた文章を受け取る", systemImage: "doc.on.clipboard") }
                    Button { registering = true } label: { Label("代わりに申請を登録", systemImage: "person.badge.plus") }
                } label: {
                    Label("申請を受け取る", systemImage: "tray.and.arrow.down")
                }
                .accessibilityLabel("申請を受け取る・代わりに登録する")
                Button { adding = true } label: { Label("希望休を入れる", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
            }
        }
        .shiftSheet(isPresented: $adding) { OffRequestSheet(month: month) }
        .shiftSheet(isPresented: $receiving) { LeaveRequestImportSheet(month: month) }
        .shiftSheet(isPresented: $registering) { LeaveRequestProxySheet(month: month) }
        .shiftSheet(isPresented: $showingQR) { RequestQRSheet() }
        .shiftSheet(item: $reply) { LeaveReplySheet(reply: $0) }
        .errorAlert($requestError)
    }

    private static func state(_ m: StaffMember, _ d: DayKey, _ book: ShiftBook) -> State3 {
        guard let r = Schedule.resolve(m, on: d, in: book) else { return .open }
        return r.isOff ? .done : .conflict
    }
}

// MARK: - バックアップ・復元

struct BackupView: View {
    @Environment(\.shiftStore) private var store
    @State private var tab = 0
    @State private var importing = false
    @State private var restoreFile: URL?
    @State private var exportFile: ExportFile?
    @State private var error: String?
    @State private var autoFiles: [URL] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 28) {
                underlineTab("バックアップ", 0)
                underlineTab("復元", 1)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 8)
            .background(Color(.systemGroupedBackground))
            .overlay(alignment: .bottom) { Divider() }

            ScrollView {
                VStack(spacing: 14) {
                    if tab == 0 {
                        card(icon: "doc.badge.arrow.up", title: "バックアップを作成",
                             detail: "今のデータ（すべての店舗・スタッフ・シフト・設定）を1つのファイルに保存します。",
                             button: "バックアップを作成", disabled: store.book.isEmpty) { export() }
                        card(icon: "square.and.arrow.down", title: "ファイルに書き出す・読み込む",
                             detail: "ファイルアプリや iCloud Drive に保存したバックアップ、PC版シフト表のバックアップを読み込みます。",
                             button: "ファイルを選択", disabled: false) { importing = true }
                        notice("アプリを削除すると、データが失われる可能性があります。定期的にバックアップを作成してください。",
                               color: .orange, icon: "exclamationmark.circle")
                    } else {
                        card(icon: "arrow.down.doc", title: "ファイルから復元",
                             detail: "書き出したファイルや、PC版シフト表のバックアップを読み込みます。",
                             button: "ファイルを選択", disabled: false) { importing = true }
                        autoBackups
                        notice("復元すると、今のデータは上書きされます。復元の前に、今のデータを自動でバックアップします。",
                               color: .red, icon: "exclamationmark.triangle")
                    }
                }
                .padding(DS.page)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("バックアップ・復元")
        .navigationBarTitleDisplayMode(.inline)
        .backupImporter(isPresented: $importing, file: $restoreFile)
        .shiftSheet(item: $exportFile) { f in ShareSheet(items: [f.url]) }
        .errorAlert($error)
        .onAppear { loadAutoFiles() }
        .onChange(of: tab) { loadAutoFiles() }
    }

    // MARK: 自動バックアップ

    private var autoBackups: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("自動バックアップ").appFont(.headline)
                Spacer()
                Text("新しい30件まで").appFont(.caption).foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)
            if autoFiles.isEmpty {
                Text("まだありません。消去・取り込みの前に自動で作られます。").appFont(.subheadline).foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            ForEach(autoFiles.prefix(10), id: \.self) { url in
                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.title(of: url)).appFont(.subheadline.weight(.semibold)).monospacedDigit()
                        Text(Self.reason(of: url)).appFont(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("復元") { restoreFile = url }.buttonStyle(.bordered)
                }
                .padding(.vertical, 8)
                if url != autoFiles.prefix(10).last { Divider() }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous))
    }

    private func loadAutoFiles() {
        let dir = ShiftStore.autoBackupFolder
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        autoFiles = files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// "shift-20261022-213000-消去前.json" → "2026/10/22 21:30"
    static func title(of url: URL) -> String {
        let parts = url.deletingPathExtension().lastPathComponent.split(separator: "-")
        guard parts.count >= 3, parts[1].count == 8, parts[2].count == 6 else { return url.lastPathComponent }
        let d = Array(parts[1]), t = Array(parts[2])
        return "\(String(d[0..<4]))/\(String(d[4..<6]))/\(String(d[6..<8])) \(String(t[0..<2])):\(String(t[2..<4]))"
    }

    static func reason(of url: URL) -> String {
        let parts = url.deletingPathExtension().lastPathComponent.split(separator: "-")
        return parts.count >= 4 ? "\(parts[3...].joined(separator: "-"))に自動で保存" : "自動で保存"
    }

    // MARK: 部品

    private func underlineTab(_ title: String, _ tag: Int) -> some View {
        let on = tab == tag
        return Button { tab = tag } label: {
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

    private func notice(_ text: String, color: Color, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).appFont(.title3).foregroundStyle(color)
            Text(text).appFont(.subheadline).foregroundStyle(color)
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous).strokeBorder(color.opacity(0.25), lineWidth: 1))
    }

    private func card(icon: String, title: String, detail: String, button: String?, disabled: Bool,
                      action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon).appFont(.title2).foregroundStyle(Color.accentColor)
                .frame(width: 48, height: 48)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).appFont(.headline)
                Text(detail).appFont(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let button {
                Button(button, action: action).buttonStyle(.borderedProminent).disabled(disabled)
            }
        }
        .padding(DS.cardPadding)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous))
    }

    /// 人件費を隠している端末では、給与も入るバックアップを書き出す前に本人の確認をする
    private func export() {
        Task { @MainActor in
            let lock = LaborCostLock.shared
            if !lock.canView {
                await lock.unlock()
                guard lock.canView else { return }
            }
            writeBackup()
        }
    }

    private func writeBackup() {
        do {
            let data = try store.exportData()
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyyMMdd-HHmm"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("shift-\(f.string(from: Date())).json")
            try data.write(to: url, options: .atomic)
            BackupReminder.record()
            exportFile = ExportFile(url: url)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - 保存していない変更の確認（HOTEL SHIFT から移植）

/// 変更があるとき：下へのスワイプで閉じない・「やめる」で破棄してよいか確かめる
struct DiscardGuard: ViewModifier {
    let dirty: Bool
    @Binding var asking: Bool
    let discard: () -> Void

    func body(content: Content) -> some View {
        content
            .interactiveDismissDisabled(dirty)
            .confirmationDialog("変更を破棄しますか？", isPresented: $asking, titleVisibility: .visible) {
                Button("変更を破棄", role: .destructive) { discard() }
                Button("編集を続ける", role: .cancel) {}
            } message: {
                Text("保存していない変更があります。")
            }
    }
}

extension View {
    /// 保存していない変更があるときの確認を付ける（「やめる」は dirty なら asking を true にする）
    func discardGuard(dirty: Bool, asking: Binding<Bool>, discard: @escaping () -> Void) -> some View {
        modifier(DiscardGuard(dirty: dirty, asking: asking, discard: discard))
    }
}
