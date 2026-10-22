import SwiftUI

// MARK: - 見本デザインに寄せた共通の部品

/// 名前の頭文字の丸（顔写真の代わり）
struct InitialAvatar: View {
    let name: String
    let colorIndex: Int
    var size: CGFloat = 30

    var body: some View {
        Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)))
            .font(.system(size: size * 0.45, weight: .bold))
            .foregroundStyle(PaletteColor.fg(colorIndex))
            .frame(width: size, height: size)
            .background(PaletteColor.bg(colorIndex), in: Circle())
            .accessibilityHidden(true)
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
            .font(.system(size: fontSize, weight: .bold))
            .lineLimit(1).minimumScaleFactor(0.6)
            .foregroundStyle(PaletteColor.fg(colorIndex))
            .padding(.horizontal, 5)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(PaletteColor.bg(colorIndex), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
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
            .font(.caption.weight(.bold))
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

struct AppSidebar: View {
    @Binding var tab: AppTab
    @Environment(ShiftStore.self) private var store

    static let main: [AppTab] = [.home, .schedule, .requests, .staff, .summary, .stores]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "building.columns.fill").font(.title2)
                VStack(alignment: .leading, spacing: -2) {
                    Text("HOTEL").font(.caption.weight(.heavy))
                    Text("SHIFT").font(.headline.weight(.heavy))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 16)

            StoreSwitcher()
                .tint(.white)
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 12).padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Self.main) { item($0) }
                }
                .padding(.horizontal, 12)
            }
            Spacer(minLength: 0)
            item(.settings).padding(.horizontal, 12).padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(BrandColor.sidebar(store.book.brandColor).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func item(_ t: AppTab) -> some View {
        let on = t == tab
        return Button { tab = t } label: {
            HStack(spacing: 12) {
                Image(systemName: t.systemImage).frame(width: 22)
                Text(t.title)
                Spacer(minLength: 0)
            }
            .font(.body.weight(on ? .bold : .medium))
            .foregroundStyle(on ? Color.white : Color.white.opacity(0.72))
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(on ? Color.white.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - 希望休の一覧

struct OffRequestListView: View {
    @Environment(ShiftStore.self) private var store
    @State private var month = MonthKey.current
    @State private var filter = 0
    @State private var adding = false

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
        let rows: [Row] = book.staffByDepartment(visibleIn: month).flatMap(\.members).flatMap { m in
            m.offRequests.compactMap { DayKey($0) }.filter { MonthKey($0) == month }.map { d in
                Row(member: m, department: deptOf[m.departmentID], day: d, state: Self.state(m, d, book))
            }
        }
        .sorted { ($0.day, $0.member.name) < ($1.day, $1.member.name) }
        let conflicts = rows.filter { $0.state == .conflict }.count
        let shown = rows.filter { filter == 0 || (filter == 1 ? $0.state == .conflict : $0.state != .conflict) }

        List {
            Section {
                Picker("表示", selection: $filter) {
                    Text("すべて \(rows.count)").tag(0)
                    Text("勤務と重なる \(conflicts)").tag(1)
                    Text("問題なし \(rows.count - conflicts)").tag(2)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section {
                if shown.isEmpty {
                    Text(rows.isEmpty ? "\(month.month)月の希望休はまだありません" : "当てはまる希望休はありません")
                        .foregroundStyle(.secondary)
                }
                ForEach(shown) { r in
                    HStack(spacing: 12) {
                        InitialAvatar(name: r.member.name, colorIndex: r.department?.colorIndex ?? 8, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.member.name).font(.body.weight(.semibold))
                            Text(r.department?.name ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("希望休").font(.subheadline).foregroundStyle(.secondary)
                        Text(HomeView.dayLabel(r.day)).font(.subheadline.weight(.semibold)).monospacedDigit()
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
        .navigationTitle("希望休 \(month.description)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button { month = month.adding(months: -1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("前の月")
                Button { month = month.adding(months: 1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("次の月")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Label("希望休を入れる", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
            }
        }
        .sheet(isPresented: $adding) { OffRequestSheet(month: month) }
    }

    private static func state(_ m: StaffMember, _ d: DayKey, _ book: ShiftBook) -> State3 {
        guard let r = Schedule.resolve(m, on: d, in: book) else { return .open }
        return r.isOff ? .done : .conflict
    }
}

// MARK: - バックアップ・復元

struct BackupView: View {
    @Environment(ShiftStore.self) private var store
    @State private var tab = 0
    @State private var importing = false
    @State private var exportFile: ExportFile?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("", selection: $tab) {
                    Text("バックアップ").tag(0)
                    Text("復元").tag(1)
                }
                .pickerStyle(.segmented)

                if tab == 0 {
                    card(icon: "doc.badge.arrow.up", title: "バックアップを作成",
                         detail: "今のシフト表（すべての店舗・スタッフ・シフト・設定）を1つのファイル（.json）に書き出します。",
                         button: "作成する", disabled: store.book.isEmpty) { export() }
                    card(icon: "clock.arrow.circlepath", title: "自動バックアップ",
                         detail: "消去・取り込みの前に、自動でバックアップを残しています（新しい30件）。「ファイル」アプリ →「このiPad内」→「シフト表」→「自動バックアップ」で見られます。",
                         button: nil, disabled: false) {}
                } else {
                    card(icon: "arrow.down.doc", title: "データを復元",
                         detail: "書き出したファイルや、PC版シフト表のバックアップを読み込みます。",
                         button: "ファイルを選ぶ", disabled: false) { importing = true }
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.circle").font(.title3).foregroundStyle(.red)
                        Text("復元すると、今のデータは上書きされます。復元の前に、自動でバックアップを残します。")
                            .font(.subheadline).foregroundStyle(.red)
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(16)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("バックアップ・復元")
        .navigationBarTitleDisplayMode(.inline)
        .backupImporter(isPresented: $importing)
        .sheet(item: $exportFile) { f in ShareSheet(items: [f.url]) }
        .errorAlert($error)
    }

    private func card(icon: String, title: String, detail: String, button: String?, disabled: Bool,
                      action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let button {
                Button(button, action: action).buttonStyle(.borderedProminent).disabled(disabled)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func export() {
        do {
            let data = try store.exportData()
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyyMMdd-HHmm"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("shift-\(f.string(from: Date())).json")
            try data.write(to: url, options: .atomic)
            exportFile = ExportFile(url: url)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
