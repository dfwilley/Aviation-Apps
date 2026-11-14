import SwiftUI

/// The data boxes below the diagram. Their order and size are the owner's to arrange.
enum DataBox: String, CaseIterable, Identifiable {
    case load, mainBus, essentialBus, batteries, notes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .load: return "Main bus load"
        case .mainBus: return "Main bus"
        case .essentialBus: return "Essential bus"
        case .batteries: return "Batteries"
        case .notes: return "Notes"
        }
    }

    /// What the small size leaves out.
    var smallSizeNote: String {
        switch self {
        case .load: return "Small hides the hint line."
        case .mainBus, .essentialBus: return "Small shows the time left only."
        case .batteries: return "Small shows one or two lines per battery."
        case .notes: return "Small shows warnings and cautions only."
        }
    }

    static let defaultOrderRaw = raw(allCases)

    static func raw(_ boxes: [DataBox]) -> String {
        boxes.map(\.rawValue).joined(separator: ",")
    }

    /// The saved order, with any box missing from it added at the end.
    static func order(from raw: String) -> [DataBox] {
        var result: [DataBox] = []
        for name in raw.split(separator: ",") {
            if let box = DataBox(rawValue: String(name)), !result.contains(box) { result.append(box) }
        }
        for box in allCases where !result.contains(box) { result.append(box) }
        return result
    }

    static func compactSet(from raw: String) -> Set<DataBox> {
        Set(raw.split(separator: ",").compactMap { DataBox(rawValue: String($0)) })
    }
}

/// Reorder the data boxes and choose a size for each.
struct ArrangeView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("boxOrder") private var boxOrderRaw = DataBox.defaultOrderRaw
    @AppStorage("boxesCompact") private var boxesCompactRaw = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(DataBox.order(from: boxOrderRaw)) { box in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(box.title).font(.headline)
                            Picker("Size of \(box.title)", selection: sizeBinding(box)) {
                                Text("Full").tag(false)
                                Text("Small").tag(true)
                            }
                            .pickerStyle(.segmented)
                            Text(box.smallSizeNote).font(.caption).foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove { from, to in
                        var order = DataBox.order(from: boxOrderRaw)
                        order.move(fromOffsets: from, toOffset: to)
                        boxOrderRaw = DataBox.raw(order)
                    }
                } footer: {
                    Text("Drag the handle on the right to move a box up or down. The diagram and the timer always stay at the top.")
                }
                Section {
                    Button("Put everything back") {
                        boxOrderRaw = DataBox.defaultOrderRaw
                        boxesCompactRaw = ""
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Arrange boxes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func sizeBinding(_ box: DataBox) -> Binding<Bool> {
        Binding(
            get: { DataBox.compactSet(from: boxesCompactRaw).contains(box) },
            set: { small in
                var set = DataBox.compactSet(from: boxesCompactRaw)
                if small { set.insert(box) } else { set.remove(box) }
                boxesCompactRaw = DataBox.allCases.filter { set.contains($0) }.map(\.rawValue).joined(separator: ",")
            }
        )
    }
}
