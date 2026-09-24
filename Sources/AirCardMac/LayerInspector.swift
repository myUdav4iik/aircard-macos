import SwiftUI

struct StudioInspector: View {
    @ObservedObject var studio: StudioModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $studio.inspectorTab) {
                ForEach(InspectorTab.allCases) { tab in
                    Text(tab.label).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            switch studio.inspectorTab {
            case .layers:
                LayerListView(studio: studio)
                Divider()
                if let id = studio.selectedLayerID, let binding = studio.layerBinding(id) {
                    LayerEditor(layer: binding)
                        .id(id)
                } else {
                    ContentUnavailableView("No Layer", systemImage: "square.3.layers.3d", description: Text("Select or add a layer."))
                        .frame(maxHeight: .infinity)
                }
            case .adjustments:
                AdjustmentsEditor(adjustments: $studio.document.adjustments, tilt: $studio.document.tilt)
            }
        }
        .frame(minWidth: 300)
    }
}

struct LayerListView: View {
    @ObservedObject var studio: StudioModel

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $studio.selectedLayerID) {
                ForEach(studio.document.layers.reversed()) { layer in
                    LayerRow(layer: layer) { studio.toggleVisibility(layer.id) }
                        .tag(layer.id)
                        .contextMenu {
                            Button("Duplicate") { studio.duplicateLayer(layer.id) }
                            Button(AirCardL10n.text(layer.isVisible ? "Hide" : "Show")) { studio.toggleVisibility(layer.id) }
                            Divider()
                            Button("Delete", role: .destructive) { studio.removeLayer(layer.id) }
                        }
                }
                .onMove { studio.moveLayers(fromDisplay: $0, toDisplay: $1) }
            }
            .listStyle(.inset)
            .frame(height: 210)

            HStack(spacing: 2) {
                Menu {
                    Button {
                        studio.importPhoto()
                    } label: {
                        Label("Image…", systemImage: "photo")
                    }
                    Divider()
                    ForEach(SkinLayerKind.allCases) { kind in
                        let content = SkinLayerContent.defaultContent(for: kind)
                        Button {
                            studio.addLayer(kind)
                        } label: {
                            Label(content.kindLabel, systemImage: content.symbol)
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuIndicator(.hidden)
                .help("Add Layer")

                Button {
                    if let id = studio.selectedLayerID { studio.removeLayer(id) }
                } label: {
                    Image(systemName: "minus")
                }
                .help("Delete Layer")
                .disabled(studio.selectedLayerID == nil)

                Button {
                    if let id = studio.selectedLayerID { studio.duplicateLayer(id) }
                } label: {
                    Image(systemName: "plus.square.on.square")
                }
                .help("Duplicate Layer")
                .disabled(studio.selectedLayerID == nil)

                Spacer()

                Button { studio.moveSelected(up: true) } label: { Image(systemName: "arrow.up") }
                    .help("Move Layer Up")
                Button { studio.moveSelected(up: false) } label: { Image(systemName: "arrow.down") }
                    .help("Move Layer Down")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}

private struct LayerRow: View {
    let layer: SkinLayer
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: layer.content.symbol)
                .frame(width: 18)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(AirCardL10n.text(layer.name)).lineLimit(1)
                Text("\(layer.content.kindLabel) · \(layer.blend.label) · \(PercentFormat.percent(layer.opacity))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: toggle) {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .foregroundStyle(layer.isVisible ? .secondary : .tertiary)
            }
            .buttonStyle(.borderless)
        }
        .opacity(layer.isVisible ? 1 : 0.55)
    }
}

struct LayerEditor: View {
    @Binding var layer: SkinLayer

    var body: some View {
        Form {
            Section("Layer") {
                TextField("Name", text: $layer.name)
                SliderRow(title: "Opacity", value: $layer.opacity, range: 0...1, format: PercentFormat.percent)
                Picker("Blend", selection: $layer.blend) {
                    ForEach(SkinBlendMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            }
            contentSections
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var contentSections: some View {
        switch layer.content {
        case .solid:
            Section("Color") {
                ColorRow(title: "Color", color: binding(\.solid, SkinLayerContent.solid, default: .black))
            }
        case .image:
            ImageSection(style: binding(\.image, SkinLayerContent.image, default: ImageLayerStyle(assetID: UUID())))
        case .linearGradient:
            let style = binding(\.linear, SkinLayerContent.linearGradient, default: LinearGradientStyle(stops: []))
            Section("Linear Gradient") {
                GradientStopsEditor(stops: style.stops)
                SliderRow(title: "Angle", value: style.angle, range: 0...360, format: PercentFormat.degrees)
            }
        case .radialGradient:
            let style = binding(\.radial, SkinLayerContent.radialGradient, default: RadialGradientStyle(stops: []))
            Section("Radial Gradient") {
                GradientStopsEditor(stops: style.stops)
                SliderRow(title: "Center X", value: style.centerX, range: -0.5...1.5, format: PercentFormat.percent)
                SliderRow(title: "Center Y", value: style.centerY, range: -0.5...1.5, format: PercentFormat.percent)
                SliderRow(title: "Radius", value: style.radius, range: 0.05...2, format: PercentFormat.percent)
            }
        case .conicGradient:
            let style = binding(\.conic, SkinLayerContent.conicGradient, default: ConicGradientStyle(stops: []))
            Section("Conic Gradient") {
                GradientStopsEditor(stops: style.stops)
                SliderRow(title: "Center X", value: style.centerX, range: 0...1, format: PercentFormat.percent)
                SliderRow(title: "Center Y", value: style.centerY, range: 0...1, format: PercentFormat.percent)
                SliderRow(title: "Rotation", value: style.angle, range: 0...360, format: PercentFormat.degrees)
            }
        case .meshGradient:
            MeshSection(style: binding(\.mesh, SkinLayerContent.meshGradient, default: MeshGradientStyle(colors: SkinPalette.aurora)))
        case .holographic:
            let style = binding(\.holo, SkinLayerContent.holographic, default: HolographicStyle())
            Section("Holographic") {
                SliderRow(title: "Scale", value: style.scale, range: 0.2...4)
                SliderRow(title: "Angle", value: style.angle, range: 0...360, format: PercentFormat.degrees)
                SliderRow(title: "Turbulence", value: style.turbulence, range: 0...2)
                SliderRow(title: "Sparkle", value: style.sparkle, range: 0...1, format: PercentFormat.percent)
                SeedRow(seed: style.seed)
            }
        case .brushedMetal:
            let style = binding(\.metal, SkinLayerContent.brushedMetal, default: MetalStyle(tint: .white))
            Section("Brushed Metal") {
                ColorRow(title: "Hue", color: style.tint)
                SliderRow(title: "Direction", value: style.angle, range: 0...180, format: PercentFormat.degrees)
                SliderRow(title: "Brushed Effect", value: style.grain, range: 0...1, format: PercentFormat.percent)
                SliderRow(title: "Reflection", value: style.sheen, range: 0...1, format: PercentFormat.percent)
            }
        case .sheen:
            let style = binding(\.sheen, SkinLayerContent.sheen, default: SheenStyle())
            Section("Sheen") {
                ColorRow(title: "Color", color: style.color)
                SliderRow(title: "Angle", value: style.angle, range: 0...360, format: PercentFormat.degrees)
                SliderRow(title: "Position", value: style.position, range: 0...1, format: PercentFormat.percent)
                SliderRow(title: "Width", value: style.width, range: 0.02...1, format: PercentFormat.percent)
            }
        case .grain:
            let style = binding(\.grain, SkinLayerContent.grain, default: GrainStyle())
            Section("Grain") {
                SliderRow(title: "Size", value: style.size, range: 0.5...6)
                Toggle("Monochrome", isOn: style.monochrome)
                SeedRow(seed: style.seed)
            }
        case .pattern:
            let style = binding(\.pattern, SkinLayerContent.pattern, default: PatternLayerStyle(style: .lines, color: .white))
            Section("Pattern") {
                Picker("Style", selection: style.style) {
                    ForEach(PatternStyle.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }
                ColorRow(title: "Color", color: style.color)
                SliderRow(title: "Spacing", value: style.spacing, range: 4...120, format: PercentFormat.points)
                SliderRow(title: "Thickness", value: style.thickness, range: 0.02...0.9, format: PercentFormat.percent)
                SliderRow(title: "Angle", value: style.angle, range: 0...180, format: PercentFormat.degrees)
            }
        case .text:
            TextSection(style: binding(\.text, SkinLayerContent.text, default: TextLayerStyle(text: "")))
        }
    }

    private func binding<T>(
        _ extract: KeyPath<SkinLayerContent, T?>,
        _ embed: @escaping (T) -> SkinLayerContent,
        default fallback: T
    ) -> Binding<T> {
        Binding(
            get: { layer.content[keyPath: extract] ?? fallback },
            set: { layer.content = embed($0) }
        )
    }
}

private struct SeedRow: View {
    @Binding var seed: Double

    var body: some View {
        LabeledContent("Variation") {
            Button {
                seed = Double.random(in: 0...100)
            } label: {
                Label("Random", systemImage: "dice")
            }
        }
    }
}

private struct ImageSection: View {
    @Binding var style: ImageLayerStyle

    var body: some View {
        Section("Image") {
            Picker("Fit", selection: $style.fit) {
                ForEach(ImageFit.allCases) { fit in
                    Text(fit.label).tag(fit)
                }
            }
            SliderRow(title: "Scale", value: $style.scale, range: 0.2...3, format: PercentFormat.percent)
            SliderRow(title: "Offset X", value: $style.offsetX, range: -0.6...0.6, format: PercentFormat.percent)
            SliderRow(title: "Offset Y", value: $style.offsetY, range: -0.6...0.6, format: PercentFormat.percent)
            SliderRow(title: "Blur", value: $style.blur, range: 0...80, format: PercentFormat.points)
            Button("Reset Position") {
                style.scale = 1
                style.offsetX = 0
                style.offsetY = 0
            }
        }
    }
}

private struct MeshSection: View {
    @Binding var style: MeshGradientStyle

    var body: some View {
        Section("Mesh gradient") {
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                ForEach(0..<3, id: \.self) { row in
                    GridRow {
                        ForEach(0..<3, id: \.self) { column in
                            let index = row * 3 + column
                            ColorPicker("", selection: Binding(
                                get: { style.colors.indices.contains(index) ? style.colors[index].swiftUIColor : .black },
                                set: { value in
                                    while style.colors.count < 9 { style.colors.append(.black) }
                                    style.colors[index] = SkinColor(value)
                                }
                            ), supportsOpacity: true)
                            .labelsHidden()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            SliderRow(title: "Warp", value: $style.warp, range: 0...1.2)
            LabeledContent("Variation") {
                HStack {
                    Button {
                        style.seed = Double.random(in: 0...100)
                    } label: {
                        Label("Shape", systemImage: "dice")
                    }
                    Button {
                        style.colors.shuffle()
                    } label: {
                        Label("Colors", systemImage: "shuffle")
                    }
                }
            }
        }
    }
}

private struct TextSection: View {
    @Binding var style: TextLayerStyle

    private static let fonts: [(String, String)] = [
        ("SF Pro Display Semibold", "SFProDisplay-Semibold"),
        ("SF Pro Display Bold", "SFProDisplay-Bold"),
        ("SF Pro Rounded", "SFProRounded-Semibold"),
        ("New York", "NewYorkMedium-Semibold"),
        ("Avenir Next", "AvenirNext-DemiBold"),
        ("Futura", "Futura-Medium"),
        ("Didot", "Didot-Bold"),
        ("Menlo", "Menlo-Bold")
    ]

    var body: some View {
        Section("Text") {
            TextField("Text", text: $style.text)
            Picker("Font", selection: $style.fontName) {
                ForEach(Self.fonts, id: \.1) { font in
                    Text(font.0).tag(font.1)
                }
            }
            ColorRow(title: "Color", color: $style.color)
            SliderRow(title: "Size", value: $style.size, range: 12...220, format: PercentFormat.points)
            SliderRow(title: "Tracking", value: $style.tracking, range: -4...30, format: PercentFormat.points)
            SliderRow(title: "Position X", value: $style.x, range: 0...1, format: PercentFormat.percent)
            SliderRow(title: "Position Y", value: $style.y, range: 0...1, format: PercentFormat.percent)
        }
    }
}

struct AdjustmentsEditor: View {
    @Binding var adjustments: SkinAdjustments
    @Binding var tilt: Double

    var body: some View {
        Form {
            Section("Color") {
                SliderRow(title: "Brightness", value: $adjustments.brightness, range: -0.5...0.5)
                SliderRow(title: "Contrast", value: $adjustments.contrast, range: 0.5...1.8)
                SliderRow(title: "Saturation", value: $adjustments.saturation, range: 0...2)
                SliderRow(title: "Hue", value: $adjustments.hue, range: -180...180, format: PercentFormat.degrees)
            }
            Section("Effects") {
                SliderRow(title: "Vignette", value: $adjustments.vignette, range: 0...1, format: PercentFormat.percent)
                SliderRow(title: "Bloom", value: $adjustments.bloom, range: 0...1.5)
                SliderRow(title: "Blur", value: $adjustments.blur, range: 0...40, format: PercentFormat.points)
                SliderRow(title: "Sharpness", value: $adjustments.sharpen, range: 0...2)
            }
            Section {
                SliderRow(title: "Tilt", value: $tilt, range: 0...1, format: PercentFormat.percent)
            } header: {
                Text("Exported Reflection")
            } footer: {
                Text("Wallet receives a static image: choose the angle where sheen, metal, and holographic effects are frozen.")
            }
            Section {
                Button("Reset Adjustments") { adjustments = SkinAdjustments() }
            }
        }
        .formStyle(.grouped)
    }
}

extension SkinLayerContent {
    var solid: SkinColor? { if case .solid(let v) = self { return v } else { return nil } }
    var image: ImageLayerStyle? { if case .image(let v) = self { return v } else { return nil } }
    var linear: LinearGradientStyle? { if case .linearGradient(let v) = self { return v } else { return nil } }
    var radial: RadialGradientStyle? { if case .radialGradient(let v) = self { return v } else { return nil } }
    var conic: ConicGradientStyle? { if case .conicGradient(let v) = self { return v } else { return nil } }
    var mesh: MeshGradientStyle? { if case .meshGradient(let v) = self { return v } else { return nil } }
    var holo: HolographicStyle? { if case .holographic(let v) = self { return v } else { return nil } }
    var metal: MetalStyle? { if case .brushedMetal(let v) = self { return v } else { return nil } }
    var sheen: SheenStyle? { if case .sheen(let v) = self { return v } else { return nil } }
    var grain: GrainStyle? { if case .grain(let v) = self { return v } else { return nil } }
    var pattern: PatternLayerStyle? { if case .pattern(let v) = self { return v } else { return nil } }
    var text: TextLayerStyle? { if case .text(let v) = self { return v } else { return nil } }
}
