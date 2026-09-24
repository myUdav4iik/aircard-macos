import AppKit
import SwiftUI

enum SidebarItem: Hashable {
    case studio, passcode, activity
    case card(String)
}

struct RootView: View {
    @ObservedObject var model: AppModel
    @State private var selection: SidebarItem? = .studio
    @State private var showManualEntry = false
    @State private var renaming: WalletCard?
    @State private var renameText = ""

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 340)
        } detail: {
            detail
                .safeAreaInset(edge: .bottom, spacing: 0) { StatusBar(model: model) }
        }
        .frame(minWidth: 1_080, minHeight: 700)
        .onChange(of: selection) { _, item in
            if case .card(let hash) = item, let card = model.cards.first(where: { $0.hash == hash }) {
                model.selectCard(card)
            }
        }
        .sheet(isPresented: $showManualEntry) {
            ManualCardSheet(model: model)
        }
        .alert("Rename Card", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let card = renaming { model.renameCard(card, to: renameText) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private var sortedCards: [WalletCard] {
        model.cards.sorted { $0.lastSeen > $1.lastSeen }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section("iPhone") {
                DeviceRow(model: model)
            }

            Section("Customize") {
                Label("Card Studio", systemImage: "paintpalette.fill")
                    .tag(SidebarItem.studio)
                Label("Passcode Keyboard", systemImage: "circle.grid.3x3.fill")
                    .tag(SidebarItem.passcode)
            }

            Section {
                if model.isScanning {
                    ScanStatusRow(model: model)
                }
                if sortedCards.isEmpty && !model.isScanning {
                    Text("Press "Detect from Wallet" and open the card on your iPhone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(sortedCards) { card in
                    CardSidebarRow(
                        card: card,
                        thumbnail: model.cardThumbnails[card.hash],
                        isTarget: model.selectedCard?.hash == card.hash,
                        isFresh: model.isScanning && model.lastDetectedHash == card.hash
                    )
                    .tag(SidebarItem.card(card.hash))
                    .contextMenu {
                        Button("Use as Target") { model.selectCard(card) }
                        Button("Design for This Card") {
                            model.selectCard(card)
                            selection = .studio
                        }
                        Button("Rename…") {
                            renameText = card.name
                            renaming = card
                        }
                        Button("Copy Hash") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(card.hash, forType: .string)
                        }
                        Divider()
                        Button("Forget", role: .destructive) {
                            if selection == .card(card.hash) { selection = .studio }
                            model.forgetCard(card)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Cards")
                    Spacer()
                    Button {
                        showManualEntry = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("Paste a hash manually")
                }
            }

            Section {
                Label("Activity", systemImage: "list.bullet.rectangle.portrait")
                    .tag(SidebarItem.activity)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                Button {
                    model.toggleScan()
                } label: {
                    Label(
                        model.isScanning ? "Stop Detection" : "Detect from Wallet",
                        systemImage: model.isScanning ? "stop.circle.fill" : "wave.3.right.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(model.isScanning ? .red : .accentColor)
                .controlSize(.large)
                .disabled(model.devices.isEmpty || model.isBusy)
                Toggle("Follow the last card I open", isOn: $model.followLatestCard)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.caption)
            }
            .padding(12)
            .background(.bar)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .passcode:
            PasscodeView(model: model)
        case .activity:
            ActivityView(model: model)
        case .card(let hash):
            if let card = model.cards.first(where: { $0.hash == hash }) {
                CardDetailView(model: model, card: card) { selection = .studio }
            } else {
                StudioView(model: model, studio: model.studio)
            }
        case .studio, .none:
            StudioView(model: model, studio: model.studio)
        }
    }
}

private struct DeviceRow: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.selectedDevice == nil ? "iphone.slash" : "iphone")
                .font(.title2)
                .foregroundStyle(model.selectedDevice == nil ? Color.secondary : Color.accentColor)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                if model.devices.count > 1 {
                    Picker("", selection: $model.selectedDeviceID) {
                        ForEach(model.devices) { device in
                            Text(device.name).tag(device.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .onChange(of: model.selectedDeviceID) { _, _ in model.recolorPasscodePreview() }
                } else {
                    Text(AirCardL10n.text(model.selectedDevice?.name ?? "No iPhone"))
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                if let device = model.selectedDevice {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(device.isDetectionTested ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        Text("\(device.product) · iOS \(device.version)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .help(device.compatibilityNote)
                } else {
                    Text("Connect it via USB and tap "Trust"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Button {
                model.refreshDevices()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh devices")
            .disabled(model.isBusy)
        }
        .padding(.vertical, 2)
    }
}

private struct ScanStatusRow: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text("Listening to iPhone…")
                    .font(.callout.weight(.semibold))
                Text("Open Wallet and tap the card")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(AirCardL10n.format("%d events · %d lines", model.walletEventCount, model.scanLineCount))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CardSidebarRow: View {
    let card: WalletCard
    let thumbnail: NSImage?
    let isTarget: Bool
    let isFresh: Bool

    var body: some View {
        HStack(spacing: 10) {
            CardThumbnail(image: thumbnail, width: 44)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(AirCardL10n.cardName(card.name))
                        .lineLimit(1)
                    if isFresh {
                        Circle().fill(.green).frame(width: 6, height: 6)
                    }
                }
                Text(card.shortHash)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if isTarget {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .help("Target card")
            }
        }
        .padding(.vertical, 2)
        .help(card.hash)
    }
}

private struct StatusBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            if model.isBusy {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(model.selectedDevice == nil ? Color.secondary : Color.green)
            }
            Text(model.status)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if model.isBusy {
                Button("Cancel") { model.cancel() }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct ManualCardSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var hash = ""

    private var isValid: Bool { WalletSkinService().validateCardHash(hash) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Card by Hash")
                .font(.title3.weight(.semibold))
            Text("Paste the card Base64 identifier (SHA-1 or SHA-256).")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                TextField("Card hash", text: $hash)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                if !hash.isEmpty {
                    Image(systemName: isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(isValid ? .green : .red)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    model.cardHash = hash
                    model.saveManualCard()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(22)
        .frame(width: 460)
    }
}
