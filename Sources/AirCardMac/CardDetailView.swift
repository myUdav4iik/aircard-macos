import AppKit
import SwiftUI

struct CardDetailView: View {
    @ObservedObject var model: AppModel
    let card: WalletCard
    let openStudio: () -> Void
    @State private var entries: [CardHistoryEntry] = []
    @State private var renameText = ""
    @State private var isRenaming = false
    @State private var showColorWarning = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                historySection
                cardTextColorSection
                limitsNote
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(AirCardL10n.cardName(card.name))
        .navigationSubtitle(card.shortHash)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    renameText = card.name
                    isRenaming = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(card.hash, forType: .string)
                    model.status = AirCardL10n.text("Hash copied.")
                } label: {
                    Label("Copy Hash", systemImage: "doc.on.doc")
                }
                Button {
                    openStudio()
                } label: {
                    Label("Design", systemImage: "paintpalette")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .onAppear(perform: reload)
        .onChange(of: card.hash) { _, _ in reload() }
        .onChange(of: model.historyRevision) { _, _ in reload() }
        .alert("Rename Card", isPresented: $isRenaming) {
            TextField("Name", text: $renameText)
            Button("Save") { model.renameCard(card, to: renameText) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Change Number Color",
            isPresented: $showColorWarning,
            titleVisibility: .visible
        ) {
            Button("Apply Color") {
                model.selectCard(card)
                model.flashCardTextColor()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The app will try to change foregroundColor in pass.json. iOS may reject or ignore it.")
        }
    }

    private func reload() {
        entries = model.history(for: card)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 24) {
            CardThumbnail(image: model.cardThumbnails[card.hash], width: 340)
                .shadow(color: .black.opacity(0.3), radius: 16, y: 10)
            VStack(alignment: .leading, spacing: 10) {
                Text(AirCardL10n.cardName(card.name))
                    .font(.largeTitle.weight(.semibold))
                Label {
                    Text(card.hash).font(.callout.monospaced()).textSelection(.enabled)
                } icon: {
                    Image(systemName: "number")
                }
                .foregroundStyle(.secondary)
                Label(
                    AirCardL10n.format(
                        "Viewed %d times · last %@",
                        card.hits,
                        card.lastSeen.formatted(.relative(presentation: .named).locale(AirCardL10n.locale))
                    ),
                    systemImage: "clock"
                )
                    .foregroundStyle(.secondary)
                if model.selectedCard?.hash == card.hash {
                    Label("Target card for "Apply"", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
                if let latest = entries.first {
                    HStack {
                        Button {
                            model.exportBackup(latest, card: card)
                        } label: {
                            Label("Save Backup…", systemImage: "externaldrive.badge.plus")
                        }
                        .controlSize(.large)
                        Button {
                            model.openInStudio(latest)
                            openStudio()
                        } label: {
                            Label("Open in Studio", systemImage: "paintpalette")
                        }
                        .controlSize(.large)
                    }
                    .padding(.top, 6)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Applied Skin History")
                .font(.title3.weight(.semibold))
            if entries.isEmpty {
                Text(AirCardL10n.format("You have not applied a design to this card from AirCard yet. Each time you do, a copy with thumbnail, 11 files, and the .%@ file will be saved here.", SkinDocument.fileExtension))
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 16)], spacing: 16) {
                    ForEach(entries) { entry in
                        HistoryTile(entry: entry) {
                            model.exportBackup(entry, card: card)
                        } open: {
                            model.openInStudio(entry)
                            openStudio()
                        }
                    }
                }
            }
        }
    }

    private var limitsNote: some View {
        Label {
            Text("AirCard cannot read the original Apple or bank design from the iPhone; backups contain only what you applied with the app. To return to the original, remove the card from Wallet and add it again.")
        } icon: {
            Image(systemName: "info.circle")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var cardTextColorSection: some View {
        GroupBox("Number Text") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Experimental text-color control for this card. It does not use .passthm files or modify the background design.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        colorPicker
                        readColorButton
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        colorPicker
                        readColorButton
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        applyColorButton
                        clearCacheButton
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        applyColorButton
                        clearCacheButton
                    }
                }

                Text(model.cardTextColorStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var colorPicker: some View {
        ColorPicker("Text Color", selection: $model.cardTextColor, supportsOpacity: false)
            .frame(maxWidth: 260, alignment: .leading)
    }

    private var readColorButton: some View {
        Button("Read Color") {
            model.selectCard(card)
            model.readCardTextColor()
        }
        .disabled(model.isBusy || model.selectedDevice == nil)
    }

    private var applyColorButton: some View {
        Button("Try Color Change") {
            model.selectCard(card)
            showColorWarning = true
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.isBusy || model.selectedDevice == nil)
    }

    private var clearCacheButton: some View {
        Button("Regenerate Cache") {
            model.selectCard(card)
            model.clearWalletCardCache()
        }
        .help("Removes cached renders for this card so Wallet generates them again.")
        .disabled(model.isBusy || model.selectedDevice == nil)
    }
}

private struct HistoryTile: View {
    let entry: CardHistoryEntry
    let backup: () -> Void
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardThumbnail(image: NSImage(contentsOf: entry.thumbnailURL), width: 200)
            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption.weight(.medium))
            HStack {
                Button("Open", action: open)
                Button("Backup…", action: backup)
            }
            .controlSize(.small)
        }
        .contextMenu {
            Button("Open in Studio", action: open)
            Button("Save Backup…", action: backup)
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
        }
    }
}

struct ActivityView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(model.logs.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                }
                .padding(20)
            }
            .onChange(of: model.logs.count) { _, count in
                proxy.scrollTo(count - 1, anchor: .bottom)
            }
        }
        .navigationTitle("Activity")
        .toolbar {
            ToolbarItem {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.logs.joined(separator: "\n"), forType: .string)
                } label: {
                    Label("Copy Log", systemImage: "doc.on.doc")
                }
            }
        }
        .overlay {
            if model.logs.isEmpty {
                ContentUnavailableView("No Activity", systemImage: "list.bullet.rectangle", description: Text("You will see what the app does with the iPhone here."))
            }
        }
    }
}
