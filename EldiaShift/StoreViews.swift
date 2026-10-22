import SwiftUI
import PhotosUI

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
    /// サイドバーをたたんだとき：店舗の略称だけ
    var iconOnly = false

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
            if iconOnly {
                VStack(spacing: 2) {
                    Circle().fill(PaletteColor.fg(current.colorIndex)).frame(width: 7, height: 7)
                    Text(store.book.shortName(of: current)).lineLimit(1).minimumScaleFactor(0.6)
                }
                .font(.caption.weight(.bold))
                .frame(width: 48)
            } else {
                HStack(spacing: 5) {
                    Circle().fill(PaletteColor.fg(current.colorIndex)).frame(width: 7, height: 7)
                    Text(current.name).lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .accessibilityLabel("店舗：\(current.name)。押すと切り替え")
        .sheet(isPresented: $managing) { NavigationStack { StoreListView(inSheet: true) } }
    }
}

// MARK: - 店舗の写真

/// 店舗の写真（無ければ店舗の色の面に略称）
struct StorePhoto: View {
    let store: Store
    let label: String
    var size: CGSize = CGSize(width: 64, height: 64)
    var corner: CGFloat = 12

    var body: some View {
        Group {
            if let data = store.photo, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [PaletteColor.bg(store.colorIndex), PaletteColor.fg(store.colorIndex).opacity(0.35)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    VStack(spacing: 2) {
                        Image(systemName: "building.2.fill").font(.system(size: min(size.width, size.height) * 0.28))
                        if size.height >= 60 {
                            Text(label).font(.system(size: min(size.width, size.height) * 0.16, weight: .heavy)).lineLimit(1)
                        }
                    }
                    .foregroundStyle(PaletteColor.fg(store.colorIndex))
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .accessibilityHidden(true)
    }

    /// 選んだ写真を小さく縮める（長い辺 640px・JPEG）
    static func shrink(_ data: Data) -> Data? {
        guard let img = UIImage(data: data) else { return nil }
        let k = min(1, 640 / max(img.size.width, img.size.height))
        let size = CGSize(width: (img.size.width * k).rounded(), height: (img.size.height * k).rounded())
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        let out = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        return out.jpegData(compressionQuality: 0.7)
    }
}

// MARK: - 店舗の一覧（iPad は左に一覧・右に店舗の情報）

struct StoreListView: View {
    var inSheet = false

    @Environment(ShiftStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var editing: Store?
    @State private var shownID: String?
    @State private var error: String?

    var body: some View {
        let book = store.book
        let stores = book.allStores
        Group {
            if sizeClass == .regular && !inSheet {
                let shown = stores.first { $0.id == (shownID ?? store.currentStoreID) } ?? stores[0]
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("店舗一覧").font(.headline)
                            Spacer()
                            Button { editing = store.newStore() } label: { Label("新規登録", systemImage: "plus") }
                                .buttonStyle(.borderedProminent).controlSize(.small)
                        }
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(stores) { st in
                                    Button { shownID = st.id } label: { card(st, book: book, highlighted: st.id == shown.id) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .frame(width: 360)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    ScrollView {
                        StoreDetailPanel(storeInfo: shown, onEdit: { editing = shown })
                    }
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(16)
                .background(Color(.systemGroupedBackground))
            } else {
                List {
                    Section {
                        ForEach(stores) { st in
                            NavigationLink {
                                ScrollView { StoreDetailPanel(storeInfo: st, onEdit: { editing = st }) }
                                    .background(Color(.systemGroupedBackground))
                                    .navigationTitle(st.name)
                                    .navigationBarTitleDisplayMode(.inline)
                            } label: {
                                card(st, book: book, highlighted: false)
                            }
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
            }
        }
        .navigationTitle("店舗管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if inSheet {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
            }
            if sizeClass != .regular || inSheet {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    EditButton()
                    Button { editing = store.newStore() } label: { Image(systemName: "plus") }
                        .accessibilityLabel("店舗を追加")
                }
            }
        }
        .sheet(item: $editing) { st in StoreEditView(storeInfo: st) }
        .errorAlert($error)
    }

    /// 一覧の1店舗（写真・名前・住所・表示中の印）
    private func card(_ st: Store, book: ShiftBook, highlighted: Bool) -> some View {
        let staff = book.staff.filter { $0.active && $0.leaveDate.isEmpty && book.homeStoreID(of: $0) == st.id }.count
        let current = st.id == store.currentStoreID
        return HStack(spacing: 12) {
            StorePhoto(store: st, label: book.shortName(of: st), size: CGSize(width: 72, height: 56), corner: 10)
            VStack(alignment: .leading, spacing: 3) {
                Text(st.name.isEmpty ? "（名前なし）" : st.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                Text(st.address.isEmpty ? "住所未登録" : st.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text("部門 \(book.departments(in: st.id).count)・スタッフ \(staff)人").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if current {
                Text("選択中").font(.caption2.weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.accentColor, in: Capsule())
            }
        }
        .padding(10)
        .background(highlighted ? Color.accentColor.opacity(0.08) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(highlighted ? Color.accentColor : Color.clear, lineWidth: 1.5))
        .contentShape(Rectangle())
    }
}

/// 1店舗の情報（写真・店舗情報・部門）
struct StoreDetailPanel: View {
    let storeInfo: Store
    let onEdit: () -> Void

    @Environment(ShiftStore.self) private var store

    var body: some View {
        let book = store.book
        let st = book.store(storeInfo.id) ?? storeInfo
        let depts = book.departments(in: st.id)
        let staff = book.staff.filter { $0.active && $0.leaveDate.isEmpty && book.homeStoreID(of: $0) == st.id }
        let helpers = book.staff.filter { $0.active && $0.extraStoreIDs.contains(st.id) && book.homeStoreID(of: $0) != st.id }
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(st.name.isEmpty ? "（名前なし）" : st.name).font(.title2.weight(.bold))
                Spacer()
                Button("編集", action: onEdit).buttonStyle(.bordered)
            }
            GeometryReader { g in
                StorePhoto(store: st, label: book.shortName(of: st), size: CGSize(width: g.size.width, height: 200), corner: 14)
            }
            .frame(height: 200)

            VStack(alignment: .leading, spacing: 0) {
                Text("店舗情報").font(.headline).padding(.bottom, 8)
                info("店舗名", st.name)
                info("略称", book.shortName(of: st))
                info("住所", st.address)
                info("電話番号", st.phone)
                info("営業時間", st.hours)
                info("部門数", "\(depts.count)")
                info("スタッフ数", "\(staff.count)人" + (helpers.isEmpty ? "" : "（ほかに掛け持ち \(helpers.count)人）"))
                info("備考", st.note)
            }

            if !depts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("部門").font(.headline)
                    FlowChips(items: depts.map { d in (d.name + " \(book.staff.filter { $0.departmentID == d.id && $0.active }.count)人", d.colorIndex) })
                }
            }

            if store.currentStoreID != st.id {
                Button { store.currentStoreID = st.id } label: {
                    Label("この店舗に切り替える", systemImage: "arrow.left.arrow.right").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
            } else {
                Label("いま表示している店舗です", systemImage: "checkmark.circle.fill")
                    .font(.subheadline).foregroundStyle(Color.accentColor)
            }
        }
        .padding(20)
    }

    private func info(_ label: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Text(label).font(.subheadline).foregroundStyle(.secondary).frame(width: 96, alignment: .leading)
                Text(value.isEmpty ? "—" : value).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 10)
            Divider()
        }
    }
}

/// 折り返して並ぶ小さな札
struct FlowChips: View {
    let items: [(String, Int)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                Text(it.0).font(.caption.weight(.semibold))
                    .foregroundStyle(PaletteColor.fg(it.1))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(PaletteColor.bg(it.1), in: Capsule())
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
    @State private var pickedPhoto: PhotosPickerItem?

    private var isNew: Bool { !store.book.stores.contains { $0.id == storeInfo.id } && storeInfo.id != Store.defaultID }

    var body: some View {
        let book = store.book
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        StorePhoto(store: storeInfo, label: book.shortName(of: storeInfo), size: CGSize(width: 120, height: 84), corner: 12)
                        VStack(alignment: .leading, spacing: 10) {
                            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                                Label(storeInfo.photo == nil ? "写真を選ぶ" : "写真を変える", systemImage: "photo")
                            }
                            if storeInfo.photo != nil {
                                Button("写真を外す", role: .destructive) { storeInfo.photo = nil }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("店舗の写真")
                } footer: {
                    Text("店舗の一覧に出します。小さく縮めて保存します。")
                }
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
                    Text("写真が無いときの面の色と、掛け持ちの人がほかの店舗で勤務する日にマスへ出す印の色です。アプリ全体の色は設定の「会社の色」で決めます。")
                }
                Section("備考") {
                    TextField("備考", text: $storeInfo.note, axis: .vertical).lineLimit(2...5)
                }
                if !isNew {
                    Section {
                        Button("この店舗を削除", role: .destructive) { confirmDelete = true }
                            .disabled(book.allStores.count <= 1)
                    } footer: {
                        Text("部門がある店舗は消せません。")
                    }
                }
            }
            .navigationTitle(isNew ? "店舗を追加" : "店舗を編集")
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
            .onChange(of: pickedPhoto) {
                guard let item = pickedPhoto else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let small = StorePhoto.shrink(data) {
                        storeInfo.photo = small
                    } else {
                        error = "写真を読み込めませんでした"
                    }
                    pickedPhoto = nil
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
