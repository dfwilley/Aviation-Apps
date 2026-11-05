import Foundation

/// Fictional aircraft and entries used only when the app is launched with
/// "-demo" (for App Store screenshots). Never shown in normal use.
enum DemoMode {
    static var isOn: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    /// "-demoScreen entry" opens a filled-in entry; "-demoScreen settings" opens Settings.
    static var screen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demoScreen"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static let tail = "N512PT"
    static let model = "Van's RV-10"
    static let owner = "Pat Taylor, Owner"

    static let jobs: [HangarData.Job] = [
        .init(recurringId: -1, name: "Oil change",
              entry: "Changed oil and filter. Filled with [ ] qts 20W-50. Cut open filter, no metal found. Ground run, no leaks.",
              laborHours: 1.0, equipmentIds: nil),
        .init(recurringId: -2, name: "Condition inspection",
              entry: "Performed condition inspection IAW the aircraft maintenance manual and found the aircraft in condition for safe operation.",
              laborHours: 8.0, equipmentIds: nil),
        .init(recurringId: -3, name: "Prop lube",
              entry: "Lubricated propeller hub per the propeller manual. Test flown, no issues.",
              laborHours: 0.5, equipmentIds: nil),
        .init(recurringId: -4, name: "ELT check",
              entry: "Performed ELT inspection and test IAW 14 CFR 91.207(d).",
              laborHours: 1.0, equipmentIds: nil),
        .init(recurringId: -5, name: "Brake pads", entry: "Replaced brake linings, left and right main. Conditioned linings per manufacturer instructions.",
              laborHours: 2.0, equipmentIds: nil)
    ]

    static var entries: [LogEntry] {
        let cal = Calendar.current
        func daysAgo(_ n: Int) -> Date { cal.date(byAdding: .day, value: -n, to: Date()) ?? Date() }

        var oil = LogEntry()
        oil.workDate = daysAgo(1)
        oil.hobbs = "412.7"
        oil.laborHours = "1.0"
        oil.job = "Oil change"
        oil.recurringId = -1
        oil.performedByName = owner
        oil.text = "Changed oil and filter. Filled with 8 qts 20W-50. Cut open filter, no metal found. Ground run, no leaks. Safety-wired the drain plug."

        var squawk = LogEntry()
        squawk.workDate = daysAgo(9)
        squawk.hobbs = "405.2"
        squawk.laborHours = "0.5"
        squawk.job = "Squawk repair"
        squawk.performedByName = owner
        squawk.text = "Replaced left nav light bulb. Operational check good."
        squawk.status = .sent
        squawk.sentAt = daysAgo(9)

        var elt = LogEntry()
        elt.workDate = daysAgo(30)
        elt.hobbs = "398.4"
        elt.laborHours = "1.0"
        elt.job = "ELT check"
        elt.recurringId = -4
        elt.performedByName = owner
        elt.text = "Performed ELT inspection and test IAW 14 CFR 91.207(d). Battery due 06/2029."
        elt.status = .sent
        elt.sentAt = daysAgo(30)

        return [oil, squawk, elt]
    }
}
