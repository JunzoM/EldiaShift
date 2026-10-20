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

    private var key: CellKey { CellKey(staffID: member.id, day: day) }

    var body: some View {
        let book = store.book
        let current = Schedule.resolve(member, on: day, in: book)
        let work = member.timeBlocks.filter { !$0.isOff } + book.templates.filter { !$0.isOff }
        let off = book.templates.filter(\.isOff) + member.timeBlocks.filter(\.isOff)

        NavigationStack {
            Form {
                Section("勤務") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                        ForEach(work) { b in
                            blockButton(b, selected: current?.blockID == b.id && current?.isAuto == false)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("休み") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                        ForEach(off) { b in
                            blockButton(b, selected: current?.blockID == b.id && current?.isAuto == false)
                        }
                    }
                    .padding(.vertical, 4)
                }

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
                    Text("時刻を指定")
                }

                if current?.isAuto == false {
                    Section {
                        Button("手入力を消して自動に戻す", role: .destructive) { apply(nil) }
                    } footer: {
                        Text("週のくり返し・期間の予定で決まる内容に戻ります。")
                    }
                }
            }
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
        do {
            try store.setCell(key, to: entry)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
