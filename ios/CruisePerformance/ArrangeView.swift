import SwiftUI

/// Drag the handles to reorder the page sections and the tiles inside the finder and calculator.
struct ArrangeView: View {
    @ObservedObject var layout: LayoutStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(layout.sections) { Text($0.title) }
                        .onMove { layout.sections.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    Text("Page sections, top to bottom")
                }
                Section {
                    ForEach(layout.finderTiles) { Text($0.title) }
                        .onMove { layout.finderTiles.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    Text("Cruise finder tiles")
                }
                Section {
                    ForEach(layout.readoutTiles) { Text($0.title) }
                        .onMove { layout.readoutTiles.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    Text("Calculator tiles")
                }
                Section {
                    Button("Reset to the original layout", role: .destructive) { confirmReset = true }
                } footer: {
                    Text("You can also hold the ≡ handle on any tile or section on the main screen and drag it into place. Your layout is saved on this phone.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Arrange")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(Theme.gold)
                }
            }
            .confirmationDialog("Put every section and tile back in its original order?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset layout", role: .destructive) { layout.reset() }
            }
        }
        .preferredColorScheme(.dark)
    }
}
