import Foundation

// MARK: - Data from the Access database

/// The "Hangar Log Data" file that Claude writes to Dropbox from
/// Maintenance Record_be.accdb (read-only). The app reads the newest one.
struct HangarData: Codable, Equatable {
    struct LastHobbs: Codable, Equatable {
        var value: Double
        /// yyyy-MM-dd
        var date: String
        var logId: Int?
    }

    struct Maintainer: Codable, Equatable, Identifiable, Hashable {
        var id: Int
        var name: String
        var ap: Bool?
    }

    /// One row of the Recurring Maintenance table.
    struct Job: Codable, Equatable, Identifiable, Hashable {
        var recurringId: Int
        var name: String
        var entry: String
        var laborHours: Double?
        var equipmentIds: [Int]?
        var id: Int { recurringId }
    }

    var schema: Int
    var generatedAt: Date
    var source: String?
    var lastHobbs: LastHobbs?
    var maintainers: [Maintainer]
    var jobs: [Job]
}

extension HangarData {
    /// Performed-by ID for the owner when no Access data file supplies maintainers.
    static let ownerId = 1

    /// Shorter button names for the jobs you use most, like the web Hangar Log.
    static let friendlyNames: [Int: String] = [
        3: "Oil change",
        5: "Prop lube",
        6: "Condition inspection",
        14: "Transponder check",
        15: "ELT check",
        16: "Propeller overhaul",
        18: "Spark plug rotation",
        20: "Pitot-static check"
    ]

    /// Jobs without standard wording, always offered.
    static let extraJobs = ["Squawk repair", "Modification", "Other"]

    static func chipName(for job: Job) -> String {
        friendlyNames[job.recurringId] ?? job.name
    }

    /// Empty starting point: no standard jobs, no Hobbs, until the owner adds
    /// their own jobs in Settings or links an Access data file.
    static let builtIn = HangarData(
        schema: 1,
        generatedAt: Date(timeIntervalSince1970: 0),
        source: nil,
        lastHobbs: nil,
        maintainers: [],
        jobs: []
    )

    static func decode(_ data: Data) throws -> HangarData {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(HangarData.self, from: data)
    }
}

// MARK: - Entries made on the phone

enum EntryStatus: String, Codable {
    case draft
    case sent      // added to Claude Logbook Import.txt
}

struct LogEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var created = Date()
    var updated = Date()
    var workDate = Date()
    var hobbs = ""
    var laborHours = ""
    var performedById: Int = HangarData.ownerId
    var performedByName: String = ""
    /// The job button picked: a Recurring Maintenance name, or Squawk repair / Modification / Other.
    var job = ""
    var recurringId: Int = 0
    var equipmentIds: [Int] = []
    /// The logbook entry text (body only; the label prints date, time and signature).
    var text = ""
    var audioFileName: String?
    var photoFileNames: [String] = []
    var status: EntryStatus = .draft
    var sentAt: Date?

    var title: String { job.isEmpty ? "Entry" : job }

    var summaryLine: String {
        let first = text.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return first.isEmpty ? "(no entry text yet)" : first
    }
}
