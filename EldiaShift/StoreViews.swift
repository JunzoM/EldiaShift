import SwiftUI

// MARK: - 店舗の印（色の点＋名前）

struct StoreBadgeLabel: View {
    let store: Store

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(PaletteColor.fg(store.colorIndex)).frame(width: 8, height: 8)
            Text(store.name.isEmpty ? "（名前なし）" : store.name)
        }
    }
}

/// 表のマスに出す、ほかの店舗の小さな印（例：「大阪」）
struct StoreTag: View {
    let store: Store
    /// 略称（ShiftBook.shortName(of:)）
    let label: String
    var size: CGFloat = 9

    var body: some View {
        Text(label)
            .font(.system(size: size, weight: .heavy))
            .foregroundStyle(PaletteColor.fg(store.colorIndex))
            .padding(.horizontal, 3).padding(.vertical, 1)
            .background(PaletteColor.bg(store.colorIndex), in: RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - 店舗の切替（ツールバー）

struct StoreSwitcher: View {
    @Environment(ShiftStore.self) private var store
    @State private var managing = false

    var body: some View {
        let stores = store.book.allStores
        let current = store.currentStore
        Menu {
            Section("表示する店舗") {
                ForEach(stores) { st in
                    Button {
                        store.currentStoreID = st.id
                    } label: {
                        if st.id == current.id { Label(st.name, systemImage: "checkmark") } else { Text(st.name) }
                    }
                }
            }
            Button { managing = true } label: { Label("店舗を管理", systemImage: "building.2") }
        } label: {
            HStack(spacing: 5) {
                Circle().fill(PaletteColor.fg(current.colorIndex)).frame(width: 7, height: 7)
                Text(current.name).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
            }
            .font(.subheadline.weight(.semibold))
        }
        .accessibilityLabel("店舗：\(current.name)。押すと切り替え")
        .sheet(isPresented: $managing) { NavigationStack { StoreListView(inSheet: true) } }
    }
}

// MARK: - 店舗の一覧

struct StoreListView: View {
    var inSheet = false

    @Environment(ShiftStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Store?
    @State private var error: String?

    var body: some View {
        let book = store.book
        let stores = book.allStores
        List {
            Section {
                ForEach(stores) { st in
                    Button { editing = st } label: { row(st, book: book) }
                }
                .onMove { from, to in
                    var list = stores
                    list.move(fromOffsets: from, toOffset: to)
                    do { try store.reorderStores(list) } catch { self.error = error.localizedDescription }
                }
            } footer: {
                Text("部門は店舗ごとに作ります。掛け持ちのスタッフは、スタッフの設定の「掛け持ち」で入れる店舗を選びます。")
            }
        }
        .navigationTitle("店舗")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if inSheet {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                EditButton()
                Button { editing = store.newStore() } label: { Image(systemName: "plus") }
                    .accessibilityLabel("店舗を追加")
            }
        }
        .sheet(item: $editing) { st in StoreEditView(storeInfo: st) }
        .errorAlert($error)
    }

    private func row(_ st: Store, book: ShiftBook) -> some View {
        let depts = book.departments(in: st.id)
        let staff = book.staff.filter { $0.active && $0.leaveDate.isEmpty && book.homeStoreID(of: $0) == st.id }.count
        let helpers = book.staff.filter { $0.active && $0.extraStoreIDs.contains(st.id) && book.homeStoreID(of: $0) != st.id }.count
        return HStack(spacing: 12) {
            Text(book.shortName(of: st))
                .font(.headline)
                .foregroundStyle(PaletteColor.fg(st.colorIndex))
                .frame(width: 44, height: 44)
                .background(PaletteColor.bg(st.colorIndex), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(st.name.isEmpty ? "（名前なし）" : st.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                Text([st.address.isEmpty ? nil : st.address,
                      "部門 \(depts.count)・スタッフ \(staff)人" + (helpers > 0 ? "（掛け持ち \(helpers)人）" : "")]
                    .compactMap { $0 }.joined(separator: "\n"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if st.id == store.currentStoreID {
                Text("表示中").font(.caption.weight(.bold)).foregroundStyle(Color.accentColor)
            }
        }
    }
}

// MARK: - 店舗1つの設定

struct StoreEditView: View {
    @State var storeInfo: Store

    @Environment(ShiftStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var confirmDelete = false

    private var isNew: Bool { !store.book.stores.contains { $0.id == storeInfo.id } && storeInfo.id != Store.defaultID }

    var body: some View {
        let book = store.book
        NavigationStack {
            Form {
                Section("店舗") {
                    TextField("店舗名（例：神戸本店）", text: $storeInfo.name)
                    TextField("住所", text: $storeInfo.address)
                    TextField("電話番号", text: $storeInfo.phone).keyboardType(.phonePad)
                    TextField("営業時間（例：24時間）", text: $storeInfo.hours)
                }
                Section {
                    TextField("略称（例：本館）", text: $storeInfo.short)
                } footer: {
                    Text("掛け持ちの人がこの店舗で勤務する日に、ほかの店舗の表のマスへ小さく出します。空なら店舗名から自動で作ります（いまは「\(book.shortName(of: storeInfo))」）。")
                }
                Section {
                    ColorChoice(index: $storeInfo.colorIndex)
                } header: {
                    Text("印の色")
                } footer: {
                    Text("掛け持ちの人がほかの店舗で勤務する日に、マスへ小さく出す印の色です。アプリ全体の色は設定の「会社の色」で決めます。")
                }
                Section("メモ") {
                    TextField("メモ", text: $storeInfo.note, axis: .vertical).lineLimit(2...5)
                }
                if !isNew {
                    let depts = book.departments(in: storeInfo.id)
                    Section("部門") {
                        if depts.isEmpty {
                            Text("部門がありません").foregroundStyle(.secondary)
                        }
                        ForEach(depts) { d in
                            LabeledContent(d.name, value: "\(book.staff.filter { $0.departmentID == d.id }.count)人")
                        }
                    }
                    Section {
                        Button("この店舗を表示する") {
                            store.currentStoreID = storeInfo.id
                            dismiss()
                        }
                        .disabled(store.currentStoreID == storeInfo.id)
                        Button("この店舗を削除", role: .destructive) { confirmDelete = true }
                            .disabled(book.allStores.count <= 1)
                    } footer: {
                        Text("部門がある店舗は消せません。")
                    }
                }
            }
            .navigationTitle(isNew ? "店舗を追加" : "店舗")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("やめる") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        storeInfo.name = storeInfo.name.trimmingCharacters(in: .whitespaces)
                        do { try store.save(storeInfo); dismiss() } catch { self.error = error.localizedDescription }
                    }
                    .disabled(storeInfo.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("「\(storeInfo.name)」を削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("削除する", role: .destructive) {
                    do { try store.deleteStore(storeInfo); dismiss() } catch { self.error = error.localizedDescription }
                }
            } message: {
                Text("掛け持ちのスタッフの入れる店舗からも外れます。")
            }
            .errorAlert($error)
        }
    }
}

// MARK: - 会社の色

enum BrandColor {
    struct Preset: Identifiable {
        let name: String
        let hex: UInt32
        var id: UInt32 { hex }
    }

    static let presets: [Preset] = [
        Preset(name: "ネイビー", hex: 0x1E3A8A),
        Preset(name: "ブルー", hex: 0x0277BD),
        Preset(name: "ティール", hex: 0x0F766E),
        Preset(name: "グリーン", hex: 0x15803D),
        Preset(name: "ゴールド", hex: 0xB8860B),
        Preset(name: "ボルドー", hex: 0x9F1239),
        Preset(name: "パープル", hex: 0x6D28D9),
        Preset(name: "グラファイト", hex: 0x334155)
    ]

    /// 白に対するコントラスト比（ボタンの白い文字の読みやすさ。3 未満は読みにくい）
    static func contrastWithWhite(_ hex: UInt32) -> Double {
        func lin(_ c: UInt32) -> Double {
            let v = Double(c) / 255
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let l = 0.2126 * lin((hex >> 16) & 0xFF) + 0.7152 * lin((hex >> 8) & 0xFF) + 0.0722 * lin(hex & 0xFF)
        return 1.05 / (l + 0.05)
    }

    static func hex(of color: Color) -> UInt32 {
        let c = color.resolve(in: EnvironmentValues())
        func b(_ v: Float) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
        return (b(c.red) << 16) | (b(c.green) << 8) | b(c.blue)
    }
}

/// アプリ全体に会社の色を当てる（ボタン・選択中の表示・ガラスの色味）
struct BrandTint: ViewModifier {
    let hex: UInt32?

    func body(content: Content) -> some View {
        if let hex {
            content.tint(Color(hex: hex)).accentColor(Color(hex: hex))
        } else {
            content
        }
    }
}

struct BrandColorView: View {
    @Environment(ShiftStore.self) private var store
    @State private var custom: Color = .blue
    @State private var error: String?

    var body: some View {
        let current = store.book.brandColor
        Form {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 12)], spacing: 12) {
                    ForEach(BrandColor.presets) { p in
                        Button { set(p.hex) } label: {
                            VStack(spacing: 6) {
                                Circle().fill(Color(hex: p.hex)).frame(width: 40, height: 40)
                                    .overlay {
                                        if current == p.hex { Image(systemName: "checkmark").font(.headline).foregroundStyle(.white) }
                                    }
                                Text(p.name).font(.caption).foregroundStyle(.primary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(p.name)
                        .accessibilityAddTraits(current == p.hex ? .isSelected : [])
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Text("よく使う色")
            }

            Section {
                ColorPicker("自由に選ぶ", selection: $custom, supportsOpacity: false)
                    .onChange(of: custom) { set(BrandColor.hex(of: custom)) }
                Button("標準の色に戻す") { set(nil) }.disabled(current == nil)
            } footer: {
                Text("会社の色は、ボタン・選択中のタブ・今日の印などアプリ全体に使います。iCloud で同期している端末と、書き出したバックアップにも入ります。シフトの種類（早番・遅番など）の色は、時間のひな形でそれぞれ決めます。")
            }

            if let current {
                Section("見え方") {
                    HStack(spacing: 12) {
                        Text("保存").font(.headline).foregroundStyle(.white)
                            .padding(.horizontal, 18).padding(.vertical, 8)
                            .background(Color(hex: current), in: Capsule())
                        Text("選択中").font(.subheadline.weight(.semibold)).foregroundStyle(Color(hex: current))
                        Spacer()
                    }
                    if BrandColor.contrastWithWhite(current) < 3 {
                        Label("明るすぎて、白い文字が読みにくい色です。もう少し濃い色をおすすめします。",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
            }
        }
        .navigationTitle("会社の色")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if let c = current { custom = Color(hex: c) } }
        .errorAlert($error)
    }

    private func set(_ hex: UInt32?) {
        guard hex != store.book.brandColor else { return }
        do { try store.setBrandColor(hex) } catch { self.error = error.localizedDescription }
    }
}
