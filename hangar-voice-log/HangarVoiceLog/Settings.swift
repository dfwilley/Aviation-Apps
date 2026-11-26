import SwiftUI
import UniformTypeIdentifiers

/// The owner's own setup: aircraft, name, and standard jobs typed into the app.
/// Stored on the phone only. In demo mode (used for App Store screenshots)
/// nothing is read from or written to the phone.
@MainActor
final class AppSettings: ObservableObject {
    @Published var tailNumber: String { didSet { save() } }
    @Published var model: String { didSet { save() } }
    @Published var ownerName: String { didSet { save() } }
    @Published var customJobs: [HangarData.Job] { didSet { save() } }

    let isDemo: Bool
    private let defaults = UserDefaults.standard

    static let defaultTail = "N721NE"
    static let defaultModel = "RV-14"

    static let privacyURL = URL(string: "https://dfwilley.github.io/Aviation-Apps/hangar-voice-log/privacy.html")!
    static let supportURL = URL(string: "https://dfwilley.github.io/Aviation-Apps/hangar-voice-log/support.html")!

    private enum Key {
        static let tail = "settings.tailNumber"
        static let model = "settings.model"
        static let owner = "settings.ownerName"
        static let jobs = "settings.customJobs"
    }

    init(demo: Bool = DemoMode.isOn) {
        isDemo = demo
        if demo {
            tailNumber = DemoMode.tail
            model = DemoMode.model
            ownerName = DemoMode.owner
            customJobs = DemoMode.jobs
            return
        }
        // Personal (TestFlight / Sideloadly) build: starts set up for N721NE.
        tailNumber = defaults.string(forKey: Key.tail) ?? Self.defaultTail
        model = defaults.string(forKey: Key.model) ?? Self.defaultModel
        ownerName = defaults.string(forKey: Key.owner) ?? ""
        if let data = defaults.data(forKey: Key.jobs),
           let jobs = try? JSONDecoder().decode([HangarData.Job].self, from: data) {
            customJobs = jobs
        } else {
            customJobs = []
        }
    }

    var isSetUp: Bool { !tailNumber.trimmingCharacters(in: .whitespaces).isEmpty }

    /// "N123AB · RV-10", or just the tail number.
    var aircraftLine: String {
        let tail = tailNumber.trimmingCharacters(in: .whitespaces).uppercased()
        let make = model.trimmingCharacters(in: .whitespaces)
        return make.isEmpty ? tail : "\(tail) · \(make)"
    }

    var displayOwner: String {
        let name = ownerName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Owner" : name
    }

    func upsertJob(_ job: HangarData.Job) {
        if let index = customJobs.firstIndex(where: { $0.recurringId == job.recurringId }) {
            customJobs[index] = job
        } else {
            customJobs.append(job)
        }
    }

    func deleteJob(_ job: HangarData.Job) {
        customJobs.removeAll { $0.recurringId == job.recurringId }
    }

    /// Jobs typed into the app get negative IDs so they never collide with
    /// Recurring Maintenance IDs from an Access data file.
    nonisolated static func nextCustomId(after jobs: [HangarData.Job]) -> Int {
        min(jobs.map(\.recurringId).min() ?? 0, 0) - 1
    }

    private func save() {
        guard !isDemo else { return }
        defaults.set(tailNumber, forKey: Key.tail)
        defaults.set(model, forKey: Key.model)
        defaults.set(ownerName, forKey: Key.owner)
        if let data = try? JSONEncoder().encode(customJobs) {
            defaults.set(data, forKey: Key.jobs)
        }
    }
}

// MARK: - Settings screen

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: EntryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// First launch: explains the app and requires a tail number.
    let isFirstRun: Bool

    @State private var editingJob: HangarData.Job?
    @State private var choosingFolder = false
    @State private var forgetArmed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if isFirstRun { welcomeCard }
                    aircraftCard
                    jobsCard
                    accessCard
                    aboutCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .background(Theme.bg)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isFirstRun ? "Set up Hangar Log" : "Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isFirstRun ? "Start" : "Done") { dismiss() }
                        .disabled(!settings.isSetUp)
                }
            }
        }
        .interactiveDismissDisabled(!settings.isSetUp)
        .sheet(item: $editingJob) { job in
            JobEditor(job: job).environmentObject(settings)
        }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { store.chooseFolder(url) }
        }
    }

    private var welcomeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(text: "Welcome")
            Text("Hangar Log turns spoken notes and photos into maintenance logbook entries for your airplane. Everything stays on this iPhone. Start by entering your aircraft.")
                .font(Theme.body(15))
                .foregroundStyle(Theme.ink)
        }
        .card()
    }

    private var aircraftCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(text: "Your aircraft")
            labeled("Tail number") {
                TextField("e.g. N123AB", text: $settings.tailNumber)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(Theme.data())
                    .field()
            }
            labeled("Make and model") {
                TextField("e.g. Van's RV-10", text: $settings.model)
                    .autocorrectionDisabled()
                    .font(Theme.body())
                    .field()
            }
            labeled("Your name (for \"Performed by\")") {
                TextField("e.g. Pat Taylor, Owner", text: $settings.ownerName)
                    .textContentType(.name)
                    .font(Theme.body())
                    .field()
            }
        }
        .card()
    }

    private var jobsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(text: "Standard jobs")
            Text("Jobs you log often, like an oil change. Picking one fills in your usual wording, which you can change each time.")
                .font(Theme.body(15))
                .foregroundStyle(Theme.muted)
            if !settings.customJobs.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(settings.customJobs.enumerated()), id: \.element.id) { index, job in
                        if index > 0 { Divider().overlay(Theme.line) }
                        Button { editingJob = job } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(job.name).font(Theme.bodySemibold(17)).foregroundStyle(Theme.ink)
                                    Text(job.entry).font(Theme.body(14)).foregroundStyle(Theme.muted).lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            let fromFile = store.hangarData.jobs.count
            if fromFile > 0 {
                Text("\(fromFile) more come from your Access data file.")
                    .font(Theme.body(14, relativeTo: .footnote))
                    .foregroundStyle(Theme.muted)
            }
            Button {
                editingJob = HangarData.Job(recurringId: AppSettings.nextCustomId(after: settings.customJobs),
                                            name: "", entry: "", laborHours: nil, equipmentIds: nil)
            } label: {
                Label("Add standard job", systemImage: "plus")
            }
            .buttonStyle(HangarButtonStyle(kind: .primary))
        }
        .card()
    }

    private var accessCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(text: "Access database link")
            Text("Pick Dropbox › Dropbox Documents › N721NE › Maintenance Software. The app reads your standard jobs and last Hobbs from the newest Hangar Log Data file there, and adds finished entries to the import file for ImportClaudeLogbookEntries in Access.")
                .font(Theme.body(15))
                .foregroundStyle(Theme.muted)

            if let status = store.dataStatus {
                Text(status)
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.ink)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.warnSoft, in: RoundedRectangle(cornerRadius: 10))
            }

            if let folder = store.folderName {
                Text("Linked folder: \(folder)")
                    .font(Theme.data(13, relativeTo: .caption))
                    .foregroundStyle(Theme.ink)
                if let file = store.dataFileName {
                    Text("Standard jobs and Hobbs read from \(file), refreshed \(LogbookFormatter.longDate(store.hangarData.generatedAt)).")
                        .font(Theme.body(14, relativeTo: .footnote))
                        .foregroundStyle(Theme.muted)
                }
                HStack(spacing: 10) {
                    Button(store.isLoadingData ? "Reading…" : "Reload") { store.refreshData() }
                        .buttonStyle(HangarButtonStyle(kind: .primary))
                        .disabled(store.isLoadingData)
                    Button("Change") { choosingFolder = true }
                        .buttonStyle(HangarButtonStyle())
                    Button(forgetArmed ? "Tap again" : "Unlink") {
                        if forgetArmed { store.forgetFolder(); forgetArmed = false } else { forgetArmed = true }
                    }
                    .buttonStyle(HangarButtonStyle(kind: .danger))
                }
                Text("Finished entries are added to \(LogbookFormatter.importFileName) in that folder.")
                    .font(Theme.body(13, relativeTo: .footnote))
                    .foregroundStyle(Theme.muted)
            } else {
                Button("Choose Folder") { choosingFolder = true }
                    .buttonStyle(HangarButtonStyle())
            }
        }
        .card()
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(text: "About")
            HStack(spacing: 10) {
                Button("Privacy Policy") { openURL(AppSettings.privacyURL) }
                    .buttonStyle(HangarButtonStyle())
                Button("Help & Support") { openURL(AppSettings.supportURL) }
                    .buttonStyle(HangarButtonStyle())
            }
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                .font(Theme.data(13, relativeTo: .caption))
                .foregroundStyle(Theme.muted)
        }
        .card()
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            FieldLabel(text: title)
            content()
        }
    }
}

// MARK: - Standard job editor

struct JobEditor: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var job: HangarData.Job
    @State private var hours: String
    @State private var deleteArmed = false
    private let isNew: Bool

    init(job: HangarData.Job) {
        _job = State(initialValue: job)
        _hours = State(initialValue: job.laborHours.map { LogbookFormatter.hobbs($0) } ?? "")
        isNew = job.name.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    FieldLabel(text: "Name")
                    TextField("e.g. Oil change", text: $job.name)
                        .font(Theme.body())
                        .field()
                    FieldLabel(text: "Usual hours of work (optional)")
                    TextField("e.g. 1.0", text: $hours)
                        .keyboardType(.decimalPad)
                        .font(Theme.data())
                        .field()
                    FieldLabel(text: "Usual logbook wording")
                    TextEditor(text: $job.entry)
                        .font(Theme.data(15))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 180)
                        .background(Theme.field, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, lineWidth: 1))
                    Text("Tip: put [ ] where a number changes each time, like \"Filled with [ ] qts\". Hangar Log reminds you to fill those in.")
                        .font(Theme.body(13, relativeTo: .footnote))
                        .foregroundStyle(Theme.muted)
                    if !isNew {
                        Button(deleteArmed ? "Tap again to delete" : "Delete job") {
                            if deleteArmed { settings.deleteJob(job); dismiss() } else { deleteArmed = true }
                        }
                        .buttonStyle(HangarButtonStyle(kind: .danger))
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle(isNew ? "New standard job" : "Edit standard job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        job.name = job.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        job.laborHours = LogbookFormatter.number(hours)
                        settings.upsertJob(job)
                        dismiss()
                    }
                    .disabled(job.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
