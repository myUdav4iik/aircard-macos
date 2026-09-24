import SwiftUI

@main
struct AirCardMacApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("AirCard") {
            RootView(model: model)
                .environment(\.locale, AirCardL10n.locale)
        }
        .defaultSize(width: 1_320, height: 840)
        .windowToolbarStyle(.unified)
        .commands {
            AirCardCommands(model: model, studio: model.studio)
        }
    }
}

struct AirCardCommands: Commands {
    @ObservedObject var model: AppModel
    @ObservedObject var studio: StudioModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Design") { studio.newDocument() }
                .keyboardShortcut("n")
            Button("Open Design…") { studio.open() }
                .keyboardShortcut("o")
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save Design") { studio.save() }
                .keyboardShortcut("s")
            Button("Save Design As…") { studio.save(as: true) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Divider()
            Button("Download Assets…") { model.exportStudioAssets() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { studio.undo() }
                .keyboardShortcut("z")
                .disabled(!studio.canUndo)
            Button("Redo") { studio.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!studio.canRedo)
        }
        CommandMenu("Design") {
            Button("Add Image…") { studio.importPhoto() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Menu("Add Layer") {
                ForEach(SkinLayerKind.allCases) { kind in
                    Button(SkinLayerContent.defaultContent(for: kind).kindLabel) { studio.addLayer(kind) }
                }
            }
            Menu("Styles") {
                ForEach(SkinPresets.all) { preset in
                    Button(AirCardL10n.text(preset.name)) { studio.applyPreset(preset) }
                }
            }
            Divider()
            Button("Duplicate Layer") {
                if let id = studio.selectedLayerID { studio.duplicateLayer(id) }
            }
            .keyboardShortcut("d")
            .disabled(studio.selectedLayerID == nil)
            Button("Delete Layer") {
                if let id = studio.selectedLayerID { studio.removeLayer(id) }
            }
            .keyboardShortcut(.delete)
            .disabled(studio.selectedLayerID == nil)
            Divider()
            Button("Show Wallet Zones") { studio.showSafeZones.toggle() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Button("Show Inspector") { studio.showInspector.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
            Divider()
            Button("Apply to Card") { model.flashSkin() }
                .keyboardShortcut(.return)
                .disabled(model.isBusy || !model.isCardHashValid || model.selectedDeviceID.isEmpty)
        }
    }
}
