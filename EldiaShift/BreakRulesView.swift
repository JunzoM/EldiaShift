import SwiftUI

/// 休憩の決まり（実働の計算に使う）。会社ごとに違うので選べるようにする
struct BreakRulesView: View {
    @Environment(\.shiftStore) private var store
    @State private var rules = BreakRules.pcDefault
    @State private var loaded = false
    @State private var error: String?
    /// 「自分で決める」を選んだ（例と同じ中身でも、段階を編集できるようにする）
    @State private var customMode = false

    private enum Preset: String, CaseIterable, Identifiable {
        case pc, labor, none, custom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .pc: "4.5時間以上は30分、6.5時間以上は60分"
            case .labor: "労働基準法の最低限（6時間を超えたら45分、8時間を超えたら60分）"
            case .none: "休憩を引かない"
            case .custom: "自分で決める"
            }
        }
        var rules: BreakRules? {
            switch self {
            case .pc: .pcDefault
            case .labor: .laborStandard
            case .none: BreakRules.none
            case .custom: nil
            }
        }
    }

    private var preset: Preset {
        customMode ? .custom : (Preset.allCases.first { $0.rules == rules } ?? .custom)
    }

    var body: some View {
        Form {
            Section {
                ForEach(Preset.allCases) { p in
                    Button {
                        if let r = p.rules {
                            rules = r
                            customMode = false
                        } else {
                            customMode = true
                            if rules.tiers.isEmpty { rules.tiers = [BreakRules.Tier(afterMinutes: 360, breakMinutes: 45)] }
                        }
                        save()
                    } label: {
                        HStack {
                            Text(p.title).foregroundStyle(.primary)
                            Spacer()
                            if preset == p { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                        }
                    }
                }
            } header: {
                Text("休憩の決まり")
            } footer: {
                Text("勤務の長さに応じて休憩を引き、残りを実働として集計・表の合計・印刷の「計」・有休の比例付与の判定に使います。ひな形ごとに休憩を決めた場合は、そちらが優先されます（設定 →「時間のひな形」、スタッフの「個人の時間」）。")
            }

            if preset == .custom {
                Section {
                    Picker("数え方", selection: Binding(get: { rules.inclusive }, set: { rules.inclusive = $0; save() })) {
                        Text("〜以上なら").tag(true)
                        Text("〜を超えたら").tag(false)
                    }
                    .pickerStyle(.segmented)
                    ForEach($rules.tiers) { $t in
                        HStack {
                            Text("勤務").foregroundStyle(.secondary)
                            Picker("勤務の長さ", selection: Binding(get: { t.afterMinutes }, set: { t.afterMinutes = $0; save() })) {
                                ForEach(Array(stride(from: 30, through: 24 * 60, by: 30)), id: \.self) {
                                    Text(BreakRules.duration($0)).tag($0)
                                }
                            }
                            .labelsHidden()
                            Text(rules.inclusive ? "以上" : "を超えたら").foregroundStyle(.secondary)
                            Spacer()
                            Picker("休憩", selection: Binding(get: { t.breakMinutes }, set: { t.breakMinutes = $0; save() })) {
                                ForEach(Array(stride(from: 0, through: 180, by: 5)), id: \.self) { Text("\($0)分").tag($0) }
                            }
                            .labelsHidden()
                        }
                    }
                    .onDelete { rules.tiers.remove(atOffsets: $0); save() }
                    Button {
                        let last = rules.tiers.map(\.afterMinutes).max() ?? 300
                        rules.tiers.append(BreakRules.Tier(afterMinutes: min(24 * 60, last + 120), breakMinutes: 60))
                        save()
                    } label: { Label("段階を追加", systemImage: "plus") }
                } header: {
                    Text("段階（左にスワイプで削除）")
                } footer: {
                    Text("いくつかの段階に当てはまるときは、休憩が一番長いものを使います。")
                }
            }

            Section("例（\(rules.summary)）") {
                ForEach([240, 270, 300, 360, 390, 420, 480, 540, 720], id: \.self) { m in
                    let b = rules.breakMinutes(forGross: m)
                    HStack {
                        Text("勤務 \(BreakRules.duration(m))").monospacedDigit()
                        Spacer()
                        Text(b == 0 ? "休憩なし" : "休憩 \(b)分").foregroundStyle(.secondary)
                        Text("実働 \(String(format: "%.2f", Double(m - b) / 60))h").monospacedDigit().frame(width: 96, alignment: .trailing)
                    }
                    .font(.subheadline)
                }
            }
        }
        .navigationTitle("休憩の決まり")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !loaded {
                rules = store.book.breakRules
                customMode = !Preset.allCases.contains { $0.rules == rules }
                loaded = true
            }
        }
        .errorAlert($error)
    }

    private func save() {
        do { try store.setBreakRules(rules) } catch { self.error = error.localizedDescription }
    }
}

/// ひな形の休憩（決まりに従う／このひな形だけ決める）
struct TemplateBreakSection: View {
    @Binding var block: TimeBlock
    let rules: BreakRules

    var body: some View {
        Section {
            Toggle("このひな形だけ休憩を決める", isOn: Binding(
                get: { block.breakMinutes != nil },
                set: { on in
                    if on {
                        let g = Int((ClockTime.hours(from: block.inMinutes ?? 0, to: block.outMinutes ?? 0) * 60).rounded())
                        block.breakMinutes = rules.breakMinutes(forGross: g)
                    } else {
                        block.breakMinutes = nil
                    }
                }))
            if let m = block.breakMinutes {
                Picker("休憩", selection: Binding(get: { m }, set: { block.breakMinutes = $0 })) {
                    ForEach(Array(stride(from: 0, through: 240, by: 5)), id: \.self) { Text("\($0)分").tag($0) }
                }
            }
            let gross = ClockTime.hours(from: block.inMinutes ?? 0, to: block.outMinutes ?? 0)
            LabeledContent("実働", value: String(format: "%.2f 時間", rules.netHours(gross: gross, override: block.breakMinutes)))
        } header: {
            Text("休憩")
        } footer: {
            Text(block.breakMinutes == nil
                 ? "休憩の決まり（\(rules.summary)）に従います。夜勤だけ休憩が長い、などのときは「このひな形だけ休憩を決める」をオンに。"
                 : "このひな形のまま入れた日は、この休憩を引きます。時刻を変えた日は、休憩の決まりに従います。")
        }
    }
}
