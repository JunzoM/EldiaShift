import TipKit
import SwiftUI

/// 1人×1日を変える画面（ひな形を押すとすぐ決まる。時刻を指定することもできる）
struct CellEditorSheet: View {
    let member: StaffMember
    let day: DayKey

    @Environment(ShiftStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var inM = 9 * 60
    @State private var outM = 18 * 60
    @State private var error: String?
    @State private var search = ""

    private var key: CellKey { CellKey(staffID: member.id, day: day) }

    var body: some View {
        let book = store.book
        let current = Schedule.resolve(member, on: day, in: book)
        let q = search.trimmingCharacters(in: .whitespaces)
        let match: (TimeBlock) -> Bool = { b in q.isEmpty || b.label.contains(q) || b.short.contains(q) }
        let personal = member.timeBlocks.filter(match)
        let common = book.templates.filter { !$0.isOff && match($0) }
        let off = book.templates.filter(\.isOff)
        let selectedID = current?.isAuto == false ? current?.blockID : nil

        NavigationStack {
            Form {
                // 初めて開いたときだけ
                TipView(CellPickerTip())
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                if !personal.isEmpty {
                    Section("\(member.name)の個人の時間") { blockGrid(personal, selectedID) }
                }
                if !common.isEmpty {
                    Section("共通の時間") { blockGrid(common, selectedID) }
                }
                if q.isEmpty {
                    Section("休日") { blockGrid(off, selectedID) }
                } else if personal.isEmpty && common.isEmpty {
                    Text("「\(q)」に合う時間がありません").foregroundStyle(.secondary)
                }

                if q.isEmpty {
                Section {
                    Picker("出勤", selection: $inM) {
                        ForEach(Array(stride(from: 0, to: 1440, by: 30)), id: \.self) { m in
                            Text(ClockTime.format(m)).tag(m)
                        }
                    }
                    Picker("退勤", selection: $outM) {
                        ForEach(Array(stride(from: 0, through: 1440, by: 30)), id: \.self) { m in
                            Text(ClockTime.format(m) + (m <= inM ? "（翌日）" : "")).tag(m)
                        }
                    }
                    LabeledContent("勤務時間", value: String(format: "%.1f 時間", ClockTime.hours(from: inM, to: outM)))
                    Button("この時刻にする") {
                        apply(CellEntry(inTime: ClockTime.format(inM), outTime: ClockTime.format(outM % 1440), blockID: nil, isOff: false))
                    }
                } header: {
                    Text("この日だけ時刻を直接入力")
                }

                }

                Section {
                    Button("クリア（パターンの自動入力に戻す）", role: .destructive) { apply(nil) }
                        .disabled(current?.isAuto != false)
                } footer: {
                    Text("この日だけ入れた内容を消して、週間パターン・期間限定パターンで決まる内容に戻します。")
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "時間を検索")
            .navigationTitle("\(day.month)月\(day.day)日（\(["日", "月", "火", "水", "木", "金", "土"][day.weekday])）\(member.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
            }
            .onAppear {
                if let span = TimelineMath.span(of: current) {
                    inM = span.inM
                    outM = span.outM % 1440 == 0 && span.outM > 0 ? 1440 : span.outM % 1440
                }
            }
            .alert("保存できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private func blockGrid(_ blocks: [TimeBlock], _ selectedID: String?) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
            ForEach(blocks) { b in blockButton(b, selected: selectedID == b.id) }
        }
        .padding(.vertical, 4)
    }

    private func blockButton(_ b: TimeBlock, selected: Bool) -> some View {
        Button {
            apply(b.isOff
                  ? CellEntry(inTime: "", outTime: "", blockID: b.id, isOff: true)
                  : CellEntry(inTime: b.inTime, outTime: b.outTime, blockID: b.id, isOff: false))
        } label: {
            VStack(spacing: 2) {
                Text(b.short.isEmpty ? b.label : b.short).font(.headline)
                Text(b.isOff ? b.label : "\(b.inTime)〜\(b.outTime)")
                    .font(.caption2).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(PaletteColor.fg(b.colorIndex))
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(PaletteColor.bg(b.colorIndex), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(PaletteColor.fg(b.colorIndex), lineWidth: selected ? 2.5 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(b.isOff ? b.label : "\(b.label)、\(b.inTime)から\(b.outTime)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func apply(_ entry: CellEntry?) {
        CellPickerTip().invalidate(reason: .actionPerformed)
        do {
            try store.setCell(key, to: entry)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
