import SwiftUI

/// Colors used across the app. The app always uses a dark look so it is easy on the eyes in the cockpit.
enum Theme {
    static let background = Color(red: 0.05, green: 0.07, blue: 0.10)
    static let card = Color(red: 0.11, green: 0.14, blue: 0.19)
    static let cardEdge = Color(red: 0.22, green: 0.27, blue: 0.34)
    static let dim = Color(red: 0.62, green: 0.68, blue: 0.76)

    static let alt = Color(red: 0.30, green: 0.85, blue: 0.47)        // alternator power
    static let battery = Color(red: 1.00, green: 0.72, blue: 0.20)    // battery power
    static let off = Color(red: 0.36, green: 0.40, blue: 0.46)        // no current
    static let fail = Color(red: 1.00, green: 0.33, blue: 0.30)       // failed or dead
    static let emergency = Color(red: 0.40, green: 0.75, blue: 1.00)  // Emergency Power selected
}
