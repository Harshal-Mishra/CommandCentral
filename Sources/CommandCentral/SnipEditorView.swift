import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import Vision

// MARK: - Annotation model (geometry in image-pixel coordinates, top-left origin)

enum SnipTool: String, CaseIterable, Identifiable {
    case pen, highlighter, arrow, rect, ellipse, text, eraser, crop

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .arrow: return "arrow.up.right"
        case .rect: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .eraser: return "eraser"
        case .crop: return "crop"
        }
    }

    var help: String {
        switch self {
        case .pen: return "Pen — draw freehand"
        case .highlighter: return "Highlighter — translucent marker"
        case .arrow: return "Arrow — drag from tail to tip"
        case .rect: return "Rectangle outline"
        case .ellipse: return "Ellipse outline"
        case .text: return "Text — click where the label should go"
        case .eraser: return "Eraser — click a mark to remove it"
        case .crop: return "Crop — drag the area to keep"
        }
    }
}

struct SnipAnnotation: Identifiable {
    enum Kind {
        case stroke(points: [CGPoint], highlighter: Bool)
        case arrow(from: CGPoint, to: CGPoint)
        case rect(CGRect)
        case ellipse(CGRect)
        case text(String, at: CGPoint)
    }

    let id = UUID()
    var kind: Kind
    var color: Color
    var width: CGFloat
}

// MARK: - Shared drawing (editor canvas + flatten/export use the same path)

func drawSnipAnnotations(_ annotations: [SnipAnnotation],
                         in context: inout GraphicsContext,
                         scale: CGFloat) {
    for annotation in annotations {
        let lineWidth = annotation.width * scale
        switch annotation.kind {
        case .stroke(let points, let highlighter):
            guard points.count > 1 else {
                if let point = points.first {
                    let radius = (highlighter ? lineWidth * 3 : lineWidth) / 2
                    let dot = CGRect(x: point.x * scale - radius, y: point.y * scale - radius,
                                     width: radius * 2, height: radius * 2)
                    context.fill(Path(ellipseIn: dot),
                                 with: .color(annotation.color.opacity(highlighter ? 0.35 : 1)))
                }
                continue
            }
            var path = Path()
            path.move(to: CGPoint(x: points[0].x * scale, y: points[0].y * scale))
            for point in points.dropFirst() {
                path.addLine(to: CGPoint(x: point.x * scale, y: point.y * scale))
            }
            context.stroke(path,
                           with: .color(annotation.color.opacity(highlighter ? 0.35 : 1)),
                           style: StrokeStyle(lineWidth: highlighter ? lineWidth * 3 : lineWidth,
                                              lineCap: .round, lineJoin: .round))
        case .arrow(let from, let to):
            let start = CGPoint(x: from.x * scale, y: from.y * scale)
            let end = CGPoint(x: to.x * scale, y: to.y * scale)
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            let angle = atan2(end.y - start.y, end.x - start.x)
            let headLength = max(10, lineWidth * 3.5)
            for offset in [CGFloat.pi * 0.85, -CGFloat.pi * 0.85] {
                path.move(to: end)
                path.addLine(to: CGPoint(x: end.x + cos(angle + offset) * headLength,
                                         y: end.y + sin(angle + offset) * headLength))
            }
            context.stroke(path, with: .color(annotation.color),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        case .rect(let rect):
            context.stroke(Path(roundedRect: rect.scaled(by: scale), cornerRadius: 2),
                           with: .color(annotation.color),
                           style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
        case .ellipse(let rect):
            context.stroke(Path(ellipseIn: rect.scaled(by: scale)),
                           with: .color(annotation.color),
                           style: StrokeStyle(lineWidth: lineWidth))
        case .text(let string, let point):
            let fontSize = (10 + annotation.width * 4) * scale
            context.draw(Text(string)
                            .font(.system(size: fontSize, weight: .semibold))
                            .foregroundStyle(annotation.color),
                         at: CGPoint(x: point.x * scale, y: point.y * scale),
                         anchor: .topLeading)
        }
    }
}

private extension CGRect {
    func scaled(by scale: CGFloat) -> CGRect {
        CGRect(x: minX * scale, y: minY * scale, width: width * scale, height: height * scale)
    }
}

/// Renders `annotations` (pixel coordinates) into `image`. Shared by the
/// editor's save/copy and the capture overlay's Quick Markup baking.
@MainActor
func flattenSnip(image: CGImage, annotations: [SnipAnnotation]) -> CGImage? {
    if annotations.isEmpty { return image }
    let renderer = ImageRenderer(content: SnipFlattenView(image: image, annotations: annotations))
    renderer.scale = 1
    return renderer.cgImage
}

/// Exact-pixel composition of the image plus annotations, used by
/// ImageRenderer to export what the editor shows.
private struct SnipFlattenView: View {
    let image: CGImage
    let annotations: [SnipAnnotation]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: image, scale: 1)
                .resizable()
            Canvas { context, _ in
                drawSnipAnnotations(annotations, in: &context, scale: 1)
            }
        }
        .frame(width: CGFloat(image.width), height: CGFloat(image.height))
    }
}

// MARK: - Editor

struct SnipEditorView: View {
    let item: SnipItem
    @EnvironmentObject private var snips: SnipStore
    @Environment(\.dismiss) private var dismiss

    @State private var baseImage: CGImage?
    @State private var annotations: [SnipAnnotation] = []
    @State private var undoStack: [[SnipAnnotation]] = []
    @State private var redoStack: [[SnipAnnotation]] = []
    @State private var tool: SnipTool = .pen
    @State private var color: Color = .red
    @State private var lineWidth: CGFloat = 4
    @State private var current: SnipAnnotation?
    @State private var cropRect: CGRect?
    @State private var pendingTextPoint: CGPoint?
    @State private var pendingText = ""
    @State private var erasedThisDrag = false
    @State private var dirty = false
    @State private var status: String?
    @FocusState private var textFieldFocused: Bool

    private let colors: [Color] = [.red, .orange, .yellow, .green,
                                   Color(red: 0.38, green: 0.65, blue: 1.0), .white, .black]
    private let widths: [CGFloat] = [2, 4, 7]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            canvasArea
            if pendingTextPoint != nil {
                textInputRow
            }
            Divider()
            footer
        }
        .frame(width: 980, height: 680)
        .background(Theme.gradient)
        .task {
            baseImage = Self.load(item.url)
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(SnipTool.allCases) { candidate in
                    Button {
                        tool = candidate
                        if candidate != .crop { cropRect = nil }
                    } label: {
                        Image(systemName: candidate.icon)
                            .font(.system(size: 13))
                            .frame(width: 30, height: 26)
                            .background(tool == candidate ? Theme.accent.opacity(0.35) : .clear,
                                        in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help(candidate.help)
                }
            }
            Divider().frame(height: 18)
            HStack(spacing: 5) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, candidate in
                    Button {
                        color = candidate
                    } label: {
                        Circle()
                            .fill(candidate)
                            .frame(width: 16, height: 16)
                            .overlay(Circle().strokeBorder(
                                .white.opacity(color == candidate ? 0.95 : 0.25),
                                lineWidth: color == candidate ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider().frame(height: 18)
            HStack(spacing: 6) {
                ForEach(widths, id: \.self) { candidate in
                    Button {
                        lineWidth = candidate
                    } label: {
                        Circle()
                            .fill(.white.opacity(lineWidth == candidate ? 1 : 0.45))
                            .frame(width: candidate + 5, height: candidate + 5)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help("Line width \(Int(candidate))")
                }
            }
            Divider().frame(height: 18)
            Button { undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(undoStack.isEmpty)
                .keyboardShortcut("z", modifiers: .command)
                .help("Undo")
            Button { redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(redoStack.isEmpty)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .help("Redo")
            if cropRect != nil {
                Button("Apply Crop") { applyCrop() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Cancel") { cropRect = nil }
                    .controlSize(.small)
            }
            Spacer()
            if let status {
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: Canvas

    @ViewBuilder
    private var canvasArea: some View {
        if let image = baseImage {
            GeometryReader { geo in
                let pixelSize = CGSize(width: image.width, height: image.height)
                let scale = min((geo.size.width - 24) / pixelSize.width,
                                (geo.size.height - 24) / pixelSize.height)
                let displaySize = CGSize(width: pixelSize.width * scale,
                                         height: pixelSize.height * scale)
                ZStack(alignment: .topLeading) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .frame(width: displaySize.width, height: displaySize.height)
                    Canvas { context, _ in
                        drawSnipAnnotations(annotations, in: &context, scale: scale)
                        if let current {
                            drawSnipAnnotations([current], in: &context, scale: scale)
                        }
                        if let cropRect {
                            drawCropOverlay(cropRect, in: &context,
                                            scale: scale, displaySize: displaySize)
                        }
                    }
                    .frame(width: displaySize.width, height: displaySize.height)
                }
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.cardStroke))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            handleDrag(value, scale: scale, pixelSize: pixelSize)
                        }
                        .onEnded { value in
                            handleEnd(value, scale: scale, pixelSize: pixelSize)
                        }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(6)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func drawCropOverlay(_ rect: CGRect, in context: inout GraphicsContext,
                                 scale: CGFloat, displaySize: CGSize) {
        let display = CGRect(x: rect.minX * scale, y: rect.minY * scale,
                             width: rect.width * scale, height: rect.height * scale)
        var dimmed = Path(CGRect(origin: .zero, size: displaySize))
        dimmed.addRect(display)
        context.fill(dimmed, with: .color(.black.opacity(0.45)), style: FillStyle(eoFill: true))
        context.stroke(Path(display), with: .color(.white),
                       style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
    }

    // MARK: Text input row

    private var textInputRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "textformat")
                .foregroundStyle(.secondary)
            TextField("Type the label, then press ⏎ to place it", text: $pendingText)
                .textFieldStyle(.roundedBorder)
                .focused($textFieldFocused)
                .onSubmit(commitText)
            Button("Add", action: commitText)
                .disabled(pendingText.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel") {
                pendingTextPoint = nil
                pendingText = ""
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.url.lastPathComponent)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                if let image = baseImage {
                    Text("\(image.width) × \(image.height) px\(dirty ? " · edited" : "")")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            Button { snips.revealInFinder(item) } label: {
                Image(systemName: "folder")
            }
            .help("Reveal in Finder")
            Button {
                snips.delete(item)
                dismiss()
            } label: {
                Image(systemName: "trash")
            }
            .help("Move to Trash")
            Spacer()
            Button("Copy Text") { extractText() }
                .help("OCR — copies all recognized text")
            Button("Copy Image") { copyImage() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Save") { save() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!dirty && annotations.isEmpty)
            Button("Done") {
                if dirty || !annotations.isEmpty { save() }
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: Gestures

    private func imagePoint(_ location: CGPoint, scale: CGFloat, pixelSize: CGSize) -> CGPoint {
        CGPoint(x: min(max(0, location.x / scale), pixelSize.width),
                y: min(max(0, location.y / scale), pixelSize.height))
    }

    private func handleDrag(_ value: DragGesture.Value, scale: CGFloat, pixelSize: CGSize) {
        let point = imagePoint(value.location, scale: scale, pixelSize: pixelSize)
        let start = imagePoint(value.startLocation, scale: scale, pixelSize: pixelSize)
        switch tool {
        case .pen, .highlighter:
            if var existing = current, case .stroke(var points, let highlighter) = existing.kind {
                points.append(point)
                existing.kind = .stroke(points: points, highlighter: highlighter)
                current = existing
            } else {
                current = SnipAnnotation(kind: .stroke(points: [point],
                                                       highlighter: tool == .highlighter),
                                         color: color, width: lineWidth)
            }
        case .arrow:
            current = SnipAnnotation(kind: .arrow(from: start, to: point),
                                     color: color, width: lineWidth)
        case .rect:
            current = SnipAnnotation(kind: .rect(rect(from: start, to: point)),
                                     color: color, width: lineWidth)
        case .ellipse:
            current = SnipAnnotation(kind: .ellipse(rect(from: start, to: point)),
                                     color: color, width: lineWidth)
        case .crop:
            cropRect = rect(from: start, to: point)
        case .eraser:
            erase(at: point, scale: scale)
        case .text:
            break
        }
    }

    private func handleEnd(_ value: DragGesture.Value, scale: CGFloat, pixelSize: CGSize) {
        switch tool {
        case .pen, .highlighter, .arrow, .rect, .ellipse:
            if let finished = current {
                commit { annotations.append(finished) }
                current = nil
            }
        case .text:
            let travel = hypot(value.translation.width, value.translation.height)
            if travel < 5 {
                pendingTextPoint = imagePoint(value.location, scale: scale, pixelSize: pixelSize)
                textFieldFocused = true
            }
        case .eraser:
            erasedThisDrag = false
        case .crop:
            break
        }
    }

    private func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    // MARK: Editing operations

    private func commit(_ change: () -> Void) {
        undoStack.append(annotations)
        redoStack = []
        change()
        dirty = true
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
    }

    private func commitText() {
        let text = pendingText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let point = pendingTextPoint else { return }
        commit {
            annotations.append(SnipAnnotation(kind: .text(text, at: point),
                                              color: color, width: lineWidth))
        }
        pendingText = ""
        pendingTextPoint = nil
    }

    private func erase(at point: CGPoint, scale: CGFloat) {
        let threshold = 10 / scale
        guard let index = annotations.lastIndex(where: { hits($0, point: point, threshold: threshold) })
        else { return }
        if !erasedThisDrag {
            undoStack.append(annotations)
            redoStack = []
            erasedThisDrag = true
        }
        annotations.remove(at: index)
        dirty = true
    }

    private func hits(_ annotation: SnipAnnotation, point: CGPoint, threshold: CGFloat) -> Bool {
        let reach = threshold + annotation.width
        switch annotation.kind {
        case .stroke(let points, _):
            return points.contains { hypot($0.x - point.x, $0.y - point.y) < reach * 2 }
        case .arrow(let from, let to):
            return distance(from: point, toSegment: (from, to)) < reach * 2
        case .rect(let rect), .ellipse(let rect):
            let outer = rect.insetBy(dx: -reach, dy: -reach)
            let inner = rect.insetBy(dx: reach, dy: reach)
            return outer.contains(point) && !(inner.width > 0 && inner.height > 0 && inner.contains(point))
        case .text(let string, let at):
            let size = 10 + annotation.width * 4
            let box = CGRect(x: at.x, y: at.y,
                             width: CGFloat(string.count) * size * 0.62 + 8,
                             height: size * 1.35)
            return box.insetBy(dx: -threshold, dy: -threshold).contains(point)
        }
    }

    private func distance(from p: CGPoint, toSegment segment: (CGPoint, CGPoint)) -> CGFloat {
        let (a, b) = segment
        let abx = b.x - a.x, aby = b.y - a.y
        let lengthSquared = abx * abx + aby * aby
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = min(max(((p.x - a.x) * abx + (p.y - a.y) * aby) / lengthSquared, 0), 1)
        return hypot(p.x - (a.x + t * abx), p.y - (a.y + t * aby))
    }

    private func applyCrop() {
        guard let rect = cropRect, rect.width > 4, rect.height > 4,
              let flattened = flatten() else { return }
        let bounds = CGRect(x: 0, y: 0, width: flattened.width, height: flattened.height)
        guard let cropped = flattened.cropping(to: rect.integral.intersection(bounds)) else { return }
        baseImage = cropped
        annotations = []
        undoStack = []
        redoStack = []
        cropRect = nil
        dirty = true
        flash("Cropped — press Save to keep it")
    }

    // MARK: Output

    private func flatten() -> CGImage? {
        guard let image = baseImage else { return nil }
        if annotations.isEmpty { return image }
        let renderer = ImageRenderer(content: SnipFlattenView(image: image, annotations: annotations))
        renderer.scale = 1
        return renderer.cgImage
    }

    private func save() {
        guard let output = flatten(),
              let destination = CGImageDestinationCreateWithURL(item.url as CFURL,
                                                                UTType.png.identifier as CFString,
                                                                1, nil) else { return }
        CGImageDestinationAddImage(destination, output, nil)
        CGImageDestinationFinalize(destination)
        baseImage = Self.load(item.url)
        annotations = []
        undoStack = []
        redoStack = []
        dirty = false
        snips.reload()
        flash("Saved ✓")
    }

    private func copyImage() {
        guard let output = flatten() else { return }
        let image = NSImage(cgImage: output, size: NSSize(width: output.width, height: output.height))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        flash("Copied image ✓")
    }

    private func extractText() {
        guard let image = flatten() else { return }
        flash("Reading text…")
        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try? handler.perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            DispatchQueue.main.async {
                if lines.isEmpty {
                    flash("No text found")
                } else {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
                    flash("Copied \(lines.count) line\(lines.count == 1 ? "" : "s") of text ✓")
                }
            }
        }
    }

    private func flash(_ message: String) {
        status = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if status == message { status = nil }
        }
    }

    static func load(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
