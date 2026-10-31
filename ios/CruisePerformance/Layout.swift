import SwiftUI

/// Screen sections (cards) that can be moved up and down the page.
enum PageSection: String, CaseIterable, Identifiable, Codable {
    case finder, conditions, readouts, drag, table, planning, sources, method
    var id: String { rawValue }
    var title: String {
        switch self {
        case .finder: return "Efficient cruise finder"
        case .conditions: return "Flight conditions"
        case .readouts: return "Calculator results"
        case .drag: return "Where the drag goes"
        case .table: return "Cruise table"
        case .planning: return "200 KTAS at 9 gal/hr check"
        case .sources: return "Sources"
        case .method: return "Method and assumptions"
        }
    }
}

/// Result tiles in the cruise finder.
enum FinderTile: String, CaseIterable, Identifiable, Codable {
    case pwr, rpm, gph, mpg, fa, trim, kias, mode
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pwr: return "Power"
        case .rpm: return "RPM / MP"
        case .gph: return "Fuel flow"
        case .mpg: return "Mileage"
        case .fa: return "Fuel/air ratio"
        case .trim: return "EFII fuel trim"
        case .kias: return "Indicated airspeed"
        case .mode: return "Mixture"
        }
    }
}

/// Readout tiles in the calculator.
enum ReadoutTile: String, CaseIterable, Identifiable, Codable {
    case rKtas, rGph, rMpg, rBhp, rKias, rRange
    var id: String { rawValue }
    var title: String {
        switch self {
        case .rKtas: return "True airspeed"
        case .rGph: return "Fuel flow"
        case .rMpg: return "Fuel mileage"
        case .rBhp: return "Engine power"
        case .rKias: return "Indicated airspeed"
        case .rRange: return "Range, 50 gal, 45 min reserve"
        }
    }
}

/// Keeps the user's arrangement of sections and tiles, saved on the phone.
final class LayoutStore: ObservableObject {
    @Published var sections: [PageSection] { didSet { save(sections, Self.kSections) } }
    @Published var finderTiles: [FinderTile] { didSet { save(finderTiles, Self.kFinder) } }
    @Published var readoutTiles: [ReadoutTile] { didSet { save(readoutTiles, Self.kReadout) } }

    private static let kSections = "n721ne.sections"
    private static let kFinder = "n721ne.tiles.finder"
    private static let kReadout = "n721ne.tiles.readout"

    init() {
        sections = Self.load(Self.kSections)
        finderTiles = Self.load(Self.kFinder)
        readoutTiles = Self.load(Self.kReadout)
    }

    func reset() {
        withAnimation(.spring(duration: 0.3)) {
            sections = PageSection.allCases
            finderTiles = FinderTile.allCases
            readoutTiles = ReadoutTile.allCases
        }
    }

    /// Tiles only, like the web app's "Reset tile layout".
    func resetTiles() {
        withAnimation(.spring(duration: 0.3)) {
            finderTiles = FinderTile.allCases
            readoutTiles = ReadoutTile.allCases
        }
    }

    /// Move `source` into the place of `target` (drag and drop).
    static func move<T: Equatable>(_ list: inout [T], _ source: T, onto target: T) {
        guard source != target, let from = list.firstIndex(of: source), let to = list.firstIndex(of: target) else { return }
        list.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }

    /// Move one step up (-1) or down (+1).
    static func step<T: Equatable>(_ list: inout [T], _ item: T, _ delta: Int) {
        guard let i = list.firstIndex(of: item) else { return }
        let j = i + delta
        guard j >= 0, j < list.count else { return }
        list.swapAt(i, j)
    }

    private func save<T: RawRepresentable>(_ list: [T], _ key: String) where T.RawValue == String {
        UserDefaults.standard.set(list.map(\.rawValue), forKey: key)
    }

    /// Saved order first, then anything new in default order.
    private static func load<T: CaseIterable & RawRepresentable & Equatable>(_ key: String) -> [T] where T.RawValue == String {
        let saved = (UserDefaults.standard.stringArray(forKey: key) ?? []).compactMap(T.init(rawValue:))
        var seen: [T] = []
        for s in saved where !seen.contains(s) { seen.append(s) }
        return seen + T.allCases.filter { !seen.contains($0) }
    }
}
