import SwiftUI
import PhotosUI

// MARK: - 会社（店舗の親）：ホームの見出し・店舗の並び・会社の情報の画面

/// ホームのいちばん上：会社の写真・ロゴ・名前・ひとこと
struct CompanyBanner: View {
    let company: CompanyInfo
    let brandHex: UInt32?
    let storeCount: Int
    var compact = false
    /// iPad・Mac のホーム：帯の右に店舗の切り替えを入れる（押すとその店舗に切り替わる）
    var stats: [String: StoreTodayStat]? = nil
    var manageStores: () -> Void = {}
    var edit: () -> Void

    @Environment(\.shiftStore) private var store

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let data = company.cover, let img = StaffPhoto.image(data) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [BrandColor.sidebar(brandHex), BrandColor.sidebar(brandHex).opacity(0.75)],
                                   startPoint: .leading, endPoint: .trailing)
                        .overlay(alignment: .trailing) {
                            Image(systemName: "building.2.fill").appFont(.system(size: compact ? 70 : 100))
                                .foregroundStyle(.white.opacity(0.10)).padding(.trailing, 28)
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            LinearGradient(colors: [.black.opacity(0.62), .black.opacity(0.05)], startPoint: .leading, endPoint: .trailing)

            HStack(alignment: .center, spacing: 14) {
                Group {
                    if let data = company.logo, let img = StaffPhoto.image(data) {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else {
                        Image(systemName: "building.columns.fill").appFont(.title2).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.white.opacity(0.18))
                    }
                }
                .frame(width: compact || stats != nil ? 44 : 56, height: compact || stats != nil ? 44 : 56)
                .clipShape(RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(company.name.isEmpty ? "会社名を設定" : company.name)
                        .appFont(compact ? .title3.weight(.bold) : .title2.weight(.bold))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    if !company.tagline.isEmpty && stats == nil {
                        Text(company.tagline).appFont(.footnote.weight(.medium)).lineLimit(2).opacity(0.92)
                    }
                    Text("\(storeCount)店舗のシフト管理").appFont(.caption2.weight(.semibold)).opacity(0.8)
                }
                .foregroundStyle(.white)
                Spacer(minLength: 0)
                if let stats { storeChips(stats) }
            }
            .padding(.leading, compact ? 16 : 22).padding(.trailing, stats != nil ? 52 : (compact ? 16 : 22)).padding(.vertical, 14)
        }
        // 店舗を帯に入れるときは低くする（画面の上を広く使う）
        .frame(height: stats != nil ? 84 : (compact ? 124 : 150))
        .clipShape(RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button(action: edit) {
                Image(systemName: "pencil").appFont(.subheadline.weight(.semibold))
                    .padding(8).background(.ultraThinMaterial, in: Circle())
            }
            .padding(10)
            .accessibilityLabel("会社の情報を変える")
        }
        .accessibilityElement(children: .contain)
    }

    /// 帯の右の店舗の切り替え（略称・今日の出勤・承認待ち）
    private func storeChips(_ stats: [String: StoreTodayStat]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.book.allStores) { st in
                    let on = st.id == store.currentStore.id
                    let s = stats[st.id] ?? StoreTodayStat()
                    Button { store.currentStoreID = st.id } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(store.book.shortName(of: st)).appFont(.subheadline.weight(.bold)).lineLimit(1)
                            HStack(spacing: 4) {
                                Text("出勤 \(s.working)人").monospacedDigit()
                                if s.pending > 0 { Text("申請 \(s.pending)").foregroundStyle(.orange) }
                            }
                            .appFont(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.white.opacity(on ? 0.28 : 0.12), in: RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous)
                            .strokeBorder(.white.opacity(on ? 0.9 : 0), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(st.name)。今日の出勤\(s.working)人\(on ? "、表示中" : "")")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
                Button(action: manageStores) {
                    Image(systemName: "ellipsis").appFont(.subheadline.weight(.bold)).foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("店舗を管理")
            }
        }
        .frame(maxWidth: 560)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 店舗ごとの今日の数字
struct StoreTodayStat: Equatable {
    var working = 0
    var pending = 0

    /// 店舗 ID ごと（勤務はその日に入る店舗で数える。承認待ちの申請はその人の店舗で数える）
    static func all(_ book: ShiftBook, today: DayKey) -> [String: StoreTodayStat] {
        var out: [String: StoreTodayStat] = [:]
        for m in book.staff where m.isVisible(in: MonthKey(today)) {
            if let r = Schedule.resolve(m, on: today, in: book), !r.isOff, let sid = r.storeID {
                out[sid, default: StoreTodayStat()].working += 1
            }
            let pending = m.leaveRequests.filter { $0.status == .pending }.count
            if pending > 0 { out[book.homeStoreID(of: m), default: StoreTodayStat()].pending += pending }
        }
        return out
    }
}

/// 会社の下にぶら下がる店舗の並び（押すとその店舗に切り替わる）
struct StoreStrip: View {
    let stats: [String: StoreTodayStat]
    var compact = false
    var manage: () -> Void

    @Environment(\.shiftStore) private var store

    var body: some View {
        let stores = store.book.allStores
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("店舗", systemImage: "arrow.turn.down.right").appFont(.headline)
                Spacer()
                Button("店舗を管理", action: manage).appFont(.subheadline)
            }
            if compact {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(stores) { card($0).frame(width: 250) }
                    }
                    .padding(.vertical, 2)
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(stores) { card($0) }
                }
            }
        }
    }

    private func card(_ st: Store) -> some View {
        let selected = st.id == store.currentStore.id
        let s = stats[st.id] ?? StoreTodayStat()
        return Button {
            store.currentStoreID = st.id
        } label: {
            HStack(spacing: 12) {
                StorePhoto(store: st, label: store.book.shortName(of: st), size: CGSize(width: 52, height: 52), corner: 10)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Circle().fill(PaletteColor.fg(st.colorIndex)).frame(width: 7, height: 7)
                        Text(st.name.isEmpty ? "店舗" : st.name).appFont(.subheadline.weight(.semibold))
                            .lineLimit(2).minimumScaleFactor(0.85).fixedSize(horizontal: false, vertical: true)
                    }
                    Text("今日の出勤 \(s.working)人").appFont(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                    if s.pending > 0 {
                        Text("承認待ち \(s.pending)件").appFont(.caption2.weight(.bold)).foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: DS.cardRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(st.name)。今日の出勤\(s.working)人\(s.pending > 0 ? "、承認待ち\(s.pending)件" : "")\(selected ? "、表示中" : "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 設定 → 会社の情報（名前・ひとこと・ロゴ・ホームの写真）
struct CompanyInfoView: View {
    var inSheet = false
    @Environment(\.shiftStore) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var info = CompanyInfo()
    @State private var initial: CompanyInfo?
    @State private var askDiscard = false
    @State private var pickedLogo: PhotosPickerItem?
    @State private var pickedCover: PhotosPickerItem?
    @State private var error: String?

    private var dirty: Bool { initial.map { $0 != info } ?? false }

    var body: some View {
        Form {
            Section {
                CompanyBanner(company: info, brandHex: store.book.brandColor, storeCount: store.book.allStores.count,
                              compact: true, edit: {})
                    .allowsHitTesting(false)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            } footer: {
                Text("ホーム画面のいちばん上に、この見出しの下に店舗が並びます。")
            }
            Section("会社") {
                TextField("会社名（例：株式会社〇〇）", text: $info.name)
                TextField("ひとこと（なくても大丈夫）", text: $info.tagline, axis: .vertical).lineLimit(1...3)
            }
            Section {
                photoRow(title: "ロゴ", has: info.logo != nil, picker: $pickedLogo) { info.logo = nil }
                photoRow(title: "ホームの写真", has: info.cover != nil, picker: $pickedCover) { info.cover = nil }
            } header: {
                Text("画像")
            } footer: {
                Text("ロゴは正方形に、写真は横長に切り抜いて小さく縮めます。写真が無いときは会社の色になります。")
            }
        }
        .navigationTitle("会社の情報")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    info.name = info.name.trimmingCharacters(in: .whitespaces)
                    info.tagline = info.tagline.trimmingCharacters(in: .whitespacesAndNewlines)
                    do { try store.setCompany(info); initial = info; if inSheet { dismiss() } }
                    catch { self.error = error.localizedDescription }
                }
                .disabled(!dirty)
            }
            if inSheet {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { if dirty { askDiscard = true } else { dismiss() } }
                }
            }
        }
        .navigationBarBackButtonHidden(dirty && !inSheet)
        .toolbar {
            if dirty && !inSheet {
                ToolbarItem(placement: .topBarLeading) {
                    Button { askDiscard = true } label: { Label("戻る", systemImage: "chevron.backward") }.labelStyle(.titleAndIcon)
                }
            }
        }
        .discardGuard(dirty: dirty, asking: $askDiscard) { dismiss() }
        .onAppear { if initial == nil { info = store.book.company; initial = info } }
        .onChange(of: pickedLogo) { load(pickedLogo, square: true) }
        .onChange(of: pickedCover) { load(pickedCover, square: false) }
        .errorAlert($error)
    }

    private func photoRow(title: String, has: Bool, picker: Binding<PhotosPickerItem?>, remove: @escaping () -> Void) -> some View {
        // PhotosPicker の見出しは別スレッドから呼ばれることがあるので、先に文字を決めておく
        let pickTitle = has ? "\(title)を変える" : "\(title)を選ぶ"
        return HStack {
            PhotosPicker(selection: picker, matching: .images) { Label(pickTitle, systemImage: "photo") }
            Spacer()
            if has { Button("外す", role: .destructive, action: remove) }
        }
        .buttonStyle(.borderless)
    }

    private func load(_ item: PhotosPickerItem?, square: Bool) {
        guard let item else { return }
        Task { @MainActor in
            if let data = try? await item.loadTransferable(type: Data.self),
               let small = square ? StaffPhoto.shrink(data) : Self.shrinkCover(data) {
                if square { info.logo = small } else { info.cover = small }
            } else {
                error = "画像を読み込めませんでした"
            }
            if square { pickedLogo = nil } else { pickedCover = nil }
        }
    }

    /// 横長（3:1）に真ん中で切り抜き、幅 1200px の JPEG に縮める
    nonisolated static func shrinkCover(_ data: Data) -> Data? {
        let out = CGSize(width: 1200, height: 400)
        // 3:1 を埋める大きさまでだけ展開する（元の写真をそのまま展開しない）
        guard let img = StaffPhoto.source(data, longSide: { s in max(s.width, s.height) * max(out.width / s.width, out.height / s.height) }),
              img.size.width > 0, img.size.height > 0 else { return nil }
        let k = max(out.width / img.size.width, out.height / img.size.height)
        let drawn = CGSize(width: img.size.width * k, height: img.size.height * k)
        let origin = CGPoint(x: (out.width - drawn.width) / 2, y: (out.height - drawn.height) / 2)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: out, format: fmt).image { _ in
            img.draw(in: CGRect(origin: origin, size: drawn))
        }.jpegData(compressionQuality: 0.6)
    }
}
