import SwiftUI

/// 日ごとのタイムライン（朝5:00〜翌10:00）。編集中はバーをドラッグして移動、両端で長さを変える（30分・15分刻み）
/// 横幅は画面に収める（横スクロールにするとドラッグとぶつかるため）。空いているところを押すと8時間のシフトを作る
struct DayTimelineView: View {
    let day: DayKey

    @Environment(ShiftStore.self) private var store
    @State private var drag: DragState?
    @State private var editing: Edit?
    @State private var shortage: ShortageTarget?
    @State private var error: String?
    /// 刻み（30分・15分。端末ごとに覚える）
    @AppStorage("timelineStep") private var stepMinutes = 30
    /// 希望休の日に勤務を作るときの確認
    @State private var pendingCreate: PendingCreate?

    private struct PendingCreate: Identifiable {
        let member: StaffMember
        let inM: Int
        let outM: Int
        var id: String { member.id }
    }

    private struct DragState: Equatable {
        let staffID: String
        let mode: TimelineMath.Mode
        let in0: Int
        let out0: Int
        var inM: Int
        var outM: Int
    }

    private struct Edit: Identifiable {
        let member: StaffMember
        var id: String { member.id }
    }

    private let nameWidth: CGFloat = 96
    private let rowHeight: CGFloat = 50
    private let hours = Array(TimelineMath.start / 60 ..< TimelineMath.end / 60)

    var body: some View {
        let book = store.book
        let groups = book.staffByDepartment(visibleIn: MonthKey(day))
            .map { g in DepartmentGroup(department: g.department, members: g.members.filter { !$0.hasLeft(on: day) }) }
            .filter { !$0.members.isEmpty }
        let resolved = Dictionary(groups.flatMap(\.members).map { ($0.id, Schedule.resolve($0, on: day, in: book)) },
                                  uniquingKeysWith: { a, _ in a })
        let firstBarID = groups.flatMap(\.members).first { TimelineMath.span(of: resolved[$0.id] ?? nil) != nil }?.id

        VStack(spacing: 0) {
        if !store.editing {
            // ロック中はドラッグできないので、すぐ編集に切り替えられるよう案内する（PC版と同じ）
            HStack(spacing: 10) {
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
                Text("ロック中のため、シフトは変更できません").font(.subheadline)
                Spacer(minLength: 0)
                Button("編集する") { store.editing = true }.buttonStyle(.borderedProminent).controlSize(.small)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.yellow.opacity(0.12))
            .overlay(alignment: .bottom) { Divider() }
        } else {
            HStack {
                UndoRedoButtons()
                Spacer()
                Picker("時間の刻み", selection: $stepMinutes) {
                    Text("30分").tag(30)
                    Text("15分").tag(15)
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
                .accessibilityLabel("ドラッグの時間の刻み")
                EditingChip()
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .overlay(alignment: .bottom) { Divider() }
        }
        GeometryReader { geo in
            let trackWidth = max(240, geo.size.width - nameWidth - 16)
            let perMinute = trackWidth / CGFloat(TimelineMath.end - TimelineMath.start)
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    hourHeader(trackWidth: trackWidth, perMinute: perMinute)
                    headcountRow(resolved: resolved, perMinute: perMinute)
                    ForEach(groups) { g in
                        HStack(spacing: 0) {
                            HStack(spacing: 6) {
                                Circle().fill(PaletteColor.fg(g.department.colorIndex)).frame(width: 8, height: 8)
                                Text(g.department.name).font(.caption.bold()).foregroundStyle(.secondary).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.leading, 10)
                            .frame(width: nameWidth)
                            if book.staffing.hasPlan(for: g.department.id) {
                                needRow(g, resolved: resolved, book: book, perMinute: perMinute)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(height: 26)
                        .background(Color(.secondarySystemBackground))
                        ForEach(g.members) { m in
                            row(m, resolved: resolved[m.id] ?? nil, book: book, trackWidth: trackWidth, perMinute: perMinute, firstBarID: firstBarID)
                        }
                    }
                }
                .padding(.trailing, 16)
            }
        }
        }
        .onAppear { if store.editing { CoachCenter.shared.show(.timeline("timelineBar")) } }
        .onChange(of: store.editing) { if store.editing { CoachCenter.shared.show(.timeline("timelineBar"), after: 0.6) } }
        .shiftSheet(item: $shortage) { t in CandidatesSheet(target: t).presentationDetents([.medium, .large]) }
        .shiftSheet(item: $editing) { e in
            CellEditorSheet(member: e.member, day: day).presentationDetents([.medium, .large])
        }
        .sensoryFeedback(.selection, trigger: drag.map { $0.inM * 10_000 + $0.outM })
        .confirmationDialog("希望休の日です", isPresented: Binding(get: { pendingCreate != nil }, set: { if !$0 { pendingCreate = nil } }),
                            titleVisibility: .visible, presenting: pendingCreate) { p in
            Button("勤務を入れる") { save(p.member, (p.inM, p.outM)) }
            Button("やめる", role: .cancel) {}
        } message: { p in
            Text("\(p.member.name)さんはこの日に希望休を出しています。勤務を入れますか？")
        }
        .alert("保存できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    // MARK: 行

    private func row(_ m: StaffMember, resolved r: ResolvedShift?, book: ShiftBook, trackWidth: CGFloat, perMinute: CGFloat,
                     firstBarID: String?) -> some View {
        let live = drag?.staffID == m.id ? drag.map { (inM: $0.inM, outM: $0.outM) } : TimelineMath.span(of: r)
        let block = book.block(r?.blockID, for: m)
        return HStack(spacing: 0) {
            Button { if store.editing { editing = Edit(member: m) } } label: {
                Text(m.name).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: nameWidth - 10, alignment: .leading)
                    .padding(.leading, 10)
            }
            .buttonStyle(.plain)
            .disabled(!store.editing)

            ZStack(alignment: .leading) {
                gridLines(perMinute: perMinute)
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { v in
                        guard store.editing, live == nil, r?.isOff != true, r?.elsewhere != true else { return }
                        let at = TimelineMath.start + TimelineMath.snap(Double(v.location.x / perMinute) - 15, step: stepMinutes)
                        guard let s = TimelineMath.newSpan(at: at) else { return }
                        // 希望休の日は、勤務を入れてよいか確かめる
                        if m.requestsOff(day) { pendingCreate = PendingCreate(member: m, inM: s.inM, outM: s.outM) } else { save(m, s) }
                    })

                if let r, r.isOff {
                    Text(block?.label ?? "休み").font(.caption.weight(.bold))
                        .foregroundStyle(PaletteColor.fg(block?.colorIndex ?? 8))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(PaletteColor.bg(block?.colorIndex ?? 8), in: Capsule())
                        .padding(.leading, 8)
                        .onTapGesture { if store.editing { editing = Edit(member: m) } }
                } else if let r, r.elsewhere, let s = TimelineMath.span(of: r) {
                    // ほかの店舗で勤務する日：薄く出すだけ（この店舗では動かさない）
                    elsewhereBar(r, span: s, book: book, perMinute: perMinute)
                        .onTapGesture { if store.editing { editing = Edit(member: m) } }
                } else if let s = live {
                    bar(m, span: s, resolved: r, block: block, perMinute: perMinute, firstBarID: firstBarID)
                }
            }
            .frame(width: trackWidth, height: rowHeight)
            .clipped()
        }
        .frame(height: rowHeight)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
    }

    private func bar(_ m: StaffMember, span s: (inM: Int, outM: Int), resolved r: ResolvedShift?, block: TimeBlock?, perMinute: CGFloat,
                     firstBarID: String?) -> some View {
        let x = CGFloat(s.inM - TimelineMath.start) * perMinute
        let w = max(CGFloat(s.outM - s.inM) * perMinute, 16)
        let color = block.map { PaletteColor.fg($0.colorIndex) } ?? Color.accentColor
        let dragging = drag?.staffID == m.id
        return ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(dragging ? 0.95 : (r?.isAuto == true ? 0.55 : 0.85)))
            HStack(spacing: 4) {
                Text("\(TimelineMath.label(s.inM))〜\(TimelineMath.label(s.outM))")
                    .font(.caption2.weight(.bold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                // メモがある日は印と最初の部分を出す
                if let note = r?.note, !note.isEmpty {
                    Image(systemName: "note.text").font(.caption2)
                    if w > 180 { Text(note).font(.caption2).lineLimit(1).truncationMode(.tail) }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            if store.editing {
                HStack {
                    handle(m, .left, s, perMinute: perMinute)
                    Spacer(minLength: 0)
                    handle(m, .right, s, perMinute: perMinute)
                }
            }
        }
        .frame(width: w, height: rowHeight - 14)
        .modifier(OptionalCoachTarget(id: m.id == firstBarID ? "timelineBar" : nil))
        .offset(x: x)
        .gesture(dragGesture(m, .move, s, perMinute: perMinute), including: store.editing ? .all : .subviews)
        .onTapGesture { if store.editing { editing = Edit(member: m) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(m.name)、\(TimelineMath.label(s.inM))から\(TimelineMath.label(s.outM))\(r?.note.map { "、メモ：\($0)" } ?? "")")
        .accessibilityHint(store.editing ? "ダブルタップで時刻を変えます" : "")
        .accessibilityAdjustableAction { dir in
            guard store.editing else { return }
            let n = TimelineMath.drag(.move, in0: s.inM, out0: s.outM, delta: dir == .increment ? stepMinutes : -stepMinutes,
                                      step: stepMinutes)
            save(m, n)
        }
    }

    private func elsewhereBar(_ r: ResolvedShift, span s: (inM: Int, outM: Int), book: ShiftBook, perMinute: CGFloat) -> some View {
        let x = CGFloat(s.inM - TimelineMath.start) * perMinute
        let w = max(CGFloat(s.outM - s.inM) * perMinute, 16)
        return HStack(spacing: 6) {
            if let st = book.store(r.storeID) { StoreTag(store: st, label: book.shortName(of: st), size: 10) }
            Text("\(TimelineMath.label(s.inM))〜\(TimelineMath.label(s.outM))")
                .font(.caption2).monospacedDigit().foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 8)
        .frame(width: w, height: rowHeight - 14, alignment: .leading)
        .background {
            ZStack {
                Color(.secondarySystemBackground)
                ElsewhereHatch().opacity(0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(.separator), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .offset(x: x)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(book.store(r.storeID)?.name ?? "ほかの店舗")で勤務、\(TimelineMath.label(s.inM))から\(TimelineMath.label(s.outM))")
    }

    /// 両端のつまみ（指で掴みやすいよう幅を取る）
    private func handle(_ m: StaffMember, _ mode: TimelineMath.Mode, _ s: (inM: Int, outM: Int), perMinute: CGFloat) -> some View {
        Capsule().fill(.white.opacity(0.9)).frame(width: 4, height: 20)
            .frame(width: 22, height: rowHeight - 14)
            .contentShape(Rectangle())
            .highPriorityGesture(dragGesture(m, mode, s, perMinute: perMinute))
    }

    private func dragGesture(_ m: StaffMember, _ mode: TimelineMath.Mode, _ s: (inM: Int, outM: Int), perMinute: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)   // バーが動いても基準がずれないよう画面全体で測る
            .onChanged { v in
                let delta = TimelineMath.snap(Double(v.translation.width / perMinute), step: stepMinutes)
                let start = drag?.staffID == m.id && drag?.mode == mode ? drag! : DragState(staffID: m.id, mode: mode, in0: s.inM, out0: s.outM, inM: s.inM, outM: s.outM)
                let n = TimelineMath.drag(mode, in0: start.in0, out0: start.out0, delta: delta, step: stepMinutes)
                var next = start
                next.inM = n.inM
                next.outM = n.outM
                if next != drag { drag = next }
            }
            .onEnded { _ in
                guard let d = drag else { return }
                drag = nil
                if d.inM != d.in0 || d.outM != d.out0 { save(m, (d.inM, d.outM)) }
            }
    }

    private func save(_ m: StaffMember, _ s: (inM: Int, outM: Int)) {
        do {
            try store.setCell(CellKey(staffID: m.id, day: day), to: TimelineMath.entry(inM: s.inM, outM: s.outM))
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: 目盛り

    private func hourHeader(trackWidth: CGFloat, perMinute: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: nameWidth)
            ZStack(alignment: .topLeading) {
                ForEach(hours, id: \.self) { h in
                    if h % 2 == 1 {
                        Text("\(h % 24)").font(.caption2.weight(h >= 24 ? .regular : .semibold)).monospacedDigit()
                            .foregroundStyle(h >= 24 ? .secondary : .primary)
                            .offset(x: CGFloat(h * 60 - TimelineMath.start) * perMinute - 4)
                    }
                }
            }
            .frame(width: trackWidth, height: 20, alignment: .topLeading)
        }
    }

    /// 部門の、時間ごとの 実際/必要（必要人数を決めている時間だけ。足りない＝赤）
    private func needRow(_ g: DepartmentGroup, resolved: [String: ResolvedShift?], book: ShiftBook, perMinute: CGFloat) -> some View {
        let spans = g.members.compactMap { m -> (inM: Int, outM: Int)? in
            guard let r = resolved[m.id] ?? nil, !r.elsewhere else { return nil }
            return TimelineMath.span(of: r)
        }
        return HStack(spacing: 0) {
            ForEach(hours, id: \.self) { h in
                let n = TimelineMath.headcount(spans, hour: h)
                let need = book.staffing.need(g.department.id, on: day, hour: h % 24)
                Group {
                    if let need, let c = StaffingStyle.color(n, need: need) {
                        Text("\(n)/\(need)").font(.system(size: 9, weight: .bold)).monospacedDigit()
                            .foregroundStyle(n < need ? .white : c)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(n < need ? c.opacity(0.85) : c.opacity(0.15))
                            .contentShape(Rectangle())
                            .onTapGesture { if n < need { shortage = ShortageTarget(department: g.department, day: day) } }
                            .accessibilityLabel("\(h % 24)時 \(n)人（必要\(need)人）")
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 60 * perMinute, height: 20)
            }
        }
    }

    /// 時間帯ごとの人数
    private func headcountRow(resolved: [String: ResolvedShift?], perMinute: CGFloat) -> some View {
        // ほかの店舗で勤務する人は数えない
        let spans = resolved.values.compactMap { r -> (inM: Int, outM: Int)? in
            guard let r, !r.elsewhere else { return nil }
            return TimelineMath.span(of: r)
        }
        return HStack(spacing: 0) {
            Text("人数").font(.caption2).foregroundStyle(.secondary).frame(width: nameWidth)
            HStack(spacing: 0) {
                ForEach(hours, id: \.self) { h in
                    let n = TimelineMath.headcount(spans, hour: h)
                    Text(n == 0 ? "" : "\(n)").font(.system(size: 10, weight: .bold)).monospacedDigit()
                        .frame(width: 60 * perMinute, height: 22)
                        .background(Color.accentColor.opacity(min(0.45, Double(n) * 0.08)))
                }
            }
        }
        .overlay(alignment: .bottom) { Divider() }
    }

    private func gridLines(perMinute: CGFloat) -> some View {
        Canvas { ctx, size in
            for h in hours {
                let x = CGFloat(h * 60 - TimelineMath.start) * perMinute
                var p = Path()
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(p, with: .color(Color(.separator).opacity(h == 24 ? 1 : 0.5)), lineWidth: h == 24 ? 1.5 : 0.5)
            }
        }
    }
}

/// 編集中の印（押すとロックに戻る）。コーチマークで明るく残す場所でもある
struct EditingChip: View {
    @Environment(ShiftStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            Label("編集中", systemImage: "pencil").font(.caption.weight(.bold)).foregroundStyle(Color.accentColor)
            Button("終える") { store.editing = false }
                .font(.caption.weight(.bold))
                .buttonStyle(.bordered).controlSize(.mini)
        }
        .padding(.leading, 10).padding(.trailing, 4).padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.1), in: Capsule())
        .coachTarget("editing")
    }
}

/// 編集する・見るだけ の切り替え
struct EditToggle: View {
    @Environment(ShiftStore.self) private var store

    var body: some View {
        Button {
            store.editing.toggle()
            if store.editing { CoachCenter.shared.show(.edit(), after: 0.2) }
        } label: {
            Label(store.editing ? "編集を終える" : "編集する", systemImage: store.editing ? "checkmark.circle.fill" : "pencil")
        }
        .accessibilityHint(store.editing ? "見るだけに戻します" : "マスを押して変えられるようにします")
    }
}
