import SwiftUI
import UniformTypeIdentifiers

/// One scrolling page like the web Hangar Log: entry card and logbook queue.
/// Aircraft, standard jobs and the optional Access link are in Settings.
struct ContentView: View {
    @EnvironmentObject private var store: EntryStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.scenePhase) private var scenePhase

    @State private var composing = ComposerRequest(entry: nil)
    @State private var queueTab: QueueTab = .open
    @State private var banner: String?
    @State private var showingSettings = false

    struct ComposerRequest: Equatable {
        let id = UUID()
        let entry: LogEntry?
    }

    enum QueueTab: String, CaseIterable, Identifiable {
        case open, sent
        var id: String { rawValue }
    }

    private var linked: Bool { store.folderName != nil }

    private func title(for tab: QueueTab) -> String {
        switch tab {
        case .open: return "In progress"
        case .sent: return linked ? "Sent to Access" : "Logged"
        }
    }

    /// The Performed-by name a new entry starts with.
    private var defaultPerformer: String {
        store.hangarData.maintainers.first { $0.id == HangarData.ownerId }?.name ?? settings.displayOwner
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 18) {
                        if let status = store.dataStatus {
                            Button { showingSettings = true } label: {
                                Text(status + " Tap to open Settings.")
                                    .font(Theme.body(15))
                                    .foregroundStyle(Theme.ink)
                                    .multilineTextAlignment(.leading)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Theme.warnSoft, in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                        if let banner {
                            Text(banner)
                                .font(Theme.body(15))
                                .foregroundStyle(Theme.accentInk)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10))
                        }
                        ComposerView(existing: composing.entry, defaultPerformer: defaultPerformer) { message in
                            banner = message.isEmpty ? nil : message
                            composing = ComposerRequest(entry: nil)
                            withAnimation { proxy.scrollTo("top", anchor: .top) }
                        }
                        .id(composing.id)

                        queueCard { entry in
                            banner = nil
                            composing = ComposerRequest(entry: entry)
                            withAnimation { proxy.scrollTo("top", anchor: .top) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 48)
                    .id("top")
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(Theme.bg)
        }
        .background(Theme.bg)
        .sheet(isPresented: $showingSettings) {
            SettingsView(isFirstRun: !settings.isSetUp)
                .environmentObject(settings)
                .environmentObject(store)
        }
        .onAppear {
            store.refreshData()
            if !settings.isSetUp { showingSettings = true }
            switch DemoMode.screen {
            case "entry": composing = ComposerRequest(entry: store.entries.first)
            case "settings": showingSettings = true
            default: break
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refreshData() }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            (Text("HANGAR ").foregroundStyle(Theme.onSteel) + Text("LOG").foregroundStyle(Theme.accent))
                .font(Theme.display(28))
                .tracking(1)
                .accessibilityLabel("Hangar Log")
            Spacer()
            Text(settings.aircraftLine)
                .font(Theme.data(13, relativeTo: .caption))
                .tracking(1.3)
                .foregroundStyle(Theme.onSteel.opacity(0.85))
                .lineLimit(1)
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(Theme.onSteel)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Settings")
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .background(Theme.steel.ignoresSafeArea(edges: .top))
    }

    // MARK: Queue

    private func queueCard(open: @escaping (LogEntry) -> Void) -> some View {
        let list = store.entries.filter { queueTab == .sent ? $0.status == .sent : $0.status != .sent }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardTitle(text: "Logbook queue")
                Spacer()
            }
            HStack(spacing: 6) {
                ForEach(QueueTab.allCases) { tab in
                    Chip(title: title(for: tab), selected: queueTab == tab) { queueTab = tab }
                }
            }
            if list.isEmpty {
                VStack(spacing: 6) {
                    Text(queueTab == .sent ? (linked ? "Nothing sent yet" : "Nothing logged yet") : (store.entries.isEmpty ? "No entries yet" : "All caught up"))
                        .font(Theme.bodySemibold(18))
                        .foregroundStyle(Theme.ink)
                    Text(queueTab == .sent
                         ? (linked ? "Entries move here once they're added to your Access import file."
                                   : "Entries move here when you tap Mark as logged.")
                         : (linked ? "Pick a job above, add the details and photos, and tap Send to Access."
                                   : "Pick a job above, talk or type the details, add photos, then Share it to your logbook."))
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Divider().overlay(Theme.line) }
                        Button { open(entry) } label: { QueueRow(entry: entry) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .card()
    }
}

private struct QueueRow: View {
    let entry: LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.title)
                    .font(Theme.bodySemibold(17))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(entry.status == .sent ? "SENT" : "DRAFT")
                    .font(Theme.bodySemibold(12, relativeTo: .caption))
                    .tracking(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 2)
                    .foregroundStyle(entry.status == .sent ? Theme.onSteel : Theme.muted)
                    .background(entry.status == .sent ? Theme.steel : Theme.field, in: Capsule())
                    .overlay(Capsule().stroke(entry.status == .sent ? Color.clear : Theme.line, lineWidth: 1))
            }
            Text(meta)
                .font(Theme.data(13, relativeTo: .caption))
                .foregroundStyle(Theme.muted)
            Text(entry.summaryLine)
                .font(Theme.body(15))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }

    private var meta: String {
        var parts = [LogbookFormatter.longDate(entry.workDate)]
        if !entry.hobbs.isEmpty { parts.append("Hobbs \(entry.hobbs)") }
        if !entry.photoFileNames.isEmpty {
            parts.append("\(entry.photoFileNames.count) photo\(entry.photoFileNames.count == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }
}
