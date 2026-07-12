import AppKit
import ScreenCaptureKit
import SwiftUI
import Vision

// MARK: - Outcome

enum CaptureOutcome {
    case image(CGImage, openEditor: Bool)
    case text(String?)
    case color(String)
    case cancelled
}

// MARK: - Session

/// Windows 11 (2025) Snipping-Tool-style capture: screens freeze and dim,
/// a mode bar floats top-center (Rectangle / Freeform / Window / Full ·
/// Text Extract / Color Picker · delay · ✕). Rectangle selections enter
/// Quick Markup — draw on the frozen selection, then ⏎ copies & saves
/// without ever opening the editor. Esc cancels.
@MainActor
final class SnipCaptureSession {
    static private(set) var current: SnipCaptureSession?

    final class ScreenContext {
        let screen: NSScreen
        let cgBounds: CGRect        // global, top-left origin
        let scale: CGFloat
        let image: CGImage          // frozen shot, pixel-exact

        init(screen: NSScreen, cgBounds: CGRect, scale: CGFloat, image: CGImage) {
            self.screen = screen
            self.cgBounds = cgBounds
            self.scale = scale
            self.image = image
        }
    }

    struct WindowPick: Identifiable {
        let window: SCWindow
        let globalFrame: CGRect     // top-left origin
        var id: CGWindowID { window.windowID }
    }

    enum Action {
        case rectCapture(rect: CGRect, annotations: [SnipAnnotation],
                         context: ScreenContext, openEditor: Bool)   // view points
        case freeform([CGPoint], ScreenContext)
        case window(WindowPick)
        case fullScreen(ScreenContext)
        case textExtract(CGRect, ScreenContext)
        case colorPicked(String)
        case delay(TimeInterval)
        case cancel
    }

    private var overlays: [NSWindow] = []
    private var keyMonitor: Any?
    private let completion: (CaptureOutcome) -> Void
    private let model: CaptureOverlayModel
    private var finished = false

    /// Freezes all screens and shows the capture overlay.
    static func begin(mode: SnipStore.Mode, completion: @escaping (CaptureOutcome) -> Void) {
        begin(barMode: CaptureOverlayModel.BarMode(mode), completion: completion)
    }

    private static func begin(barMode: CaptureOverlayModel.BarMode,
                              completion: @escaping (CaptureOutcome) -> Void) {
        guard current == nil else {
            completion(.cancelled)
            return
        }
        Task { @MainActor in
            do {
                let content = try await SCShareableContent
                    .excludingDesktopWindows(false, onScreenWindowsOnly: true)
                var contexts: [ScreenContext] = []
                for screen in NSScreen.screens {
                    if let context = try? await captureContext(for: screen, content: content) {
                        contexts.append(context)
                    }
                }
                guard !contexts.isEmpty else {
                    completion(.cancelled)
                    return
                }
                current = SnipCaptureSession(contexts: contexts,
                                             windows: windowPicks(from: content),
                                             barMode: barMode,
                                             completion: completion)
            } catch {
                completion(.cancelled)
            }
        }
    }

    /// One-shot capture of the display under the mouse (no overlay) —
    /// used for the Full Screen / timed modes.
    static func captureMouseDisplay() async -> CGImage? {
        guard let screen = screenUnderMouse() else { return nil }
        guard let content = try? await SCShareableContent
            .excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return nil }
        return (try? await captureContext(for: screen, content: content))?.image
    }

    private static func captureContext(for screen: NSScreen,
                                       content: SCShareableContent) async throws -> ScreenContext? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let display = content.displays.first(where: { $0.displayID == number.uint32Value })
        else { return nil }
        let scale = screen.backingScaleFactor
        let configuration = SCStreamConfiguration()
        configuration.width = Int(screen.frame.width * scale)
        configuration.height = Int(screen.frame.height * scale)
        configuration.showsCursor = false
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                               configuration: configuration)
        return ScreenContext(screen: screen,
                             cgBounds: CGDisplayBounds(number.uint32Value),
                             scale: scale,
                             image: image)
    }

    /// Window-mode targets, front-to-back so hover picks the topmost.
    private static func windowPicks(from content: SCShareableContent) -> [WindowPick] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ordered = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
                       as? [[String: Any]])?
            .compactMap { $0[kCGWindowNumber as String] as? CGWindowID } ?? []
        let rank = Dictionary(ordered.enumerated().map { ($1, $0) },
                              uniquingKeysWith: { first, _ in first })
        return content.windows
            .filter { window in
                window.isOnScreen
                    && window.windowLayer == 0
                    && window.frame.width > 60 && window.frame.height > 60
                    && window.owningApplication?.processID != ownPID
            }
            .map { WindowPick(window: $0, globalFrame: $0.frame) }
            .sorted { (rank[$0.id] ?? .max) < (rank[$1.id] ?? .max) }
    }

    private static func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    // MARK: Instance

    private init(contexts: [ScreenContext], windows: [WindowPick],
                 barMode: CaptureOverlayModel.BarMode,
                 completion: @escaping (CaptureOutcome) -> Void) {
        self.completion = completion
        self.model = CaptureOverlayModel(mode: barMode)
        model.act = { [weak self] action in self?.handle(action) }

        let toolbarScreen = Self.screenUnderMouse()
        for context in contexts {
            let picks = windows.filter { $0.globalFrame.intersects(context.cgBounds) }
            let view = CaptureOverlayView(context: context,
                                          windowPicks: picks,
                                          model: model,
                                          showToolbar: context.screen == toolbarScreen)
            let window = OverlayWindow(contentRect: context.screen.frame)
            window.contentView = NSHostingView(rootView: view)
            window.onEsc = { [weak self] in self?.model.act(.cancel) }
            window.makeKeyAndOrderFront(nil)
            overlays.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {                                    // Esc
                self.model.act(.cancel)
                return nil
            }
            if event.keyCode == 36, self.model.returnHandler?() == true {   // ⏎
                return nil
            }
            return event
        }
    }

    private func handle(_ action: Action) {
        switch action {
        case .cancel:
            finish(.cancelled)
        case .fullScreen(let context):
            finish(.image(context.image, openEditor: true))
        case .rectCapture(let rect, let annotations, let context, let openEditor):
            let pixelRect = pixelAligned(rect, in: context)
            guard let cropped = context.image.cropping(to: pixelRect) else {
                finish(.cancelled)
                return
            }
            let shifted = annotations.map {
                transformed($0, scale: context.scale, origin: pixelRect.origin)
            }
            let baked = flattenSnip(image: cropped, annotations: shifted) ?? cropped
            finish(.image(baked, openEditor: openEditor))
        case .freeform(let points, let context):
            let pixelPoints = points.map { CGPoint(x: $0.x * context.scale, y: $0.y * context.scale) }
            if let image = Self.maskCrop(context.image, points: pixelPoints) {
                finish(.image(image, openEditor: true))
            } else {
                finish(.cancelled)
            }
        case .window(let pick):
            // Fresh per-window shot: clean edges, no overlap from other windows.
            Task { @MainActor in
                let configuration = SCStreamConfiguration()
                let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
                configuration.width = Int(pick.globalFrame.width * scale)
                configuration.height = Int(pick.globalFrame.height * scale)
                configuration.showsCursor = false
                let filter = SCContentFilter(desktopIndependentWindow: pick.window)
                if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                           configuration: configuration) {
                    self.finish(.image(image, openEditor: true))
                } else {
                    self.finish(.cancelled)
                }
            }
        case .textExtract(let rect, let context):
            guard let cropped = context.image.cropping(to: pixelAligned(rect, in: context)) else {
                finish(.cancelled)
                return
            }
            teardown()
            DispatchQueue.global(qos: .userInitiated).async { [completion] in
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                try? VNImageRequestHandler(cgImage: cropped, options: [:]).perform([request])
                let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                DispatchQueue.main.async {
                    completion(.text(lines.isEmpty ? nil : lines.joined(separator: "\n")))
                }
            }
        case .colorPicked(let hex):
            finish(.color(hex))
        case .delay(let seconds):
            // Re-freeze after the delay so the shot shows what's on screen then.
            let barMode = model.mode
            let completion = self.completion
            teardown()
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                Self.begin(barMode: barMode, completion: completion)
            }
        }
    }

    private func pixelAligned(_ rect: CGRect, in context: ScreenContext) -> CGRect {
        CGRect(x: rect.minX * context.scale,
               y: rect.minY * context.scale,
               width: rect.width * context.scale,
               height: rect.height * context.scale).integral
    }

    /// Shifts a view-point annotation into cropped-pixel coordinates.
    private func transformed(_ annotation: SnipAnnotation, scale: CGFloat,
                             origin: CGPoint) -> SnipAnnotation {
        var result = annotation
        result.width = annotation.width * scale
        func map(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x * scale - origin.x, y: p.y * scale - origin.y)
        }
        switch annotation.kind {
        case .stroke(let points, let highlighter):
            result.kind = .stroke(points: points.map(map), highlighter: highlighter)
        case .arrow(let from, let to):
            result.kind = .arrow(from: map(from), to: map(to))
        case .rect(let r):
            result.kind = .rect(CGRect(origin: map(r.origin),
                                       size: CGSize(width: r.width * scale, height: r.height * scale)))
        case .ellipse(let r):
            result.kind = .ellipse(CGRect(origin: map(r.origin),
                                          size: CGSize(width: r.width * scale, height: r.height * scale)))
        case .text(let string, let at):
            result.kind = .text(string, at: map(at))
        }
        return result
    }

    private func teardown() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        overlays.forEach { $0.orderOut(nil) }
        overlays = []
        Self.current = nil
    }

    private func finish(_ outcome: CaptureOutcome) {
        guard !finished else { return }
        finished = true
        teardown()
        completion(outcome)
    }

    /// Crops to the freeform path's bounding box with everything outside
    /// the path transparent. Points arrive in top-left pixel coordinates.
    private static func maskCrop(_ image: CGImage, points: [CGPoint]) -> CGImage? {
        guard points.count > 2 else { return nil }
        let height = CGFloat(image.height)
        let flipped = points.map { CGPoint(x: $0.x, y: height - $0.y) }
        let path = CGMutablePath()
        path.addLines(between: flipped)
        path.closeSubpath()
        let bounds = path.boundingBoxOfPath.integral
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard bounds.width > 4, bounds.height > 4,
              let context = CGContext(data: nil,
                                      width: Int(bounds.width), height: Int(bounds.height),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        context.addPath(path)
        context.clip()
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }
}

// MARK: - Overlay window

private final class OverlayWindow: NSWindow {
    var onEsc: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless],
                   backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = true
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEsc?()
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: - Overlay model

final class CaptureOverlayModel: ObservableObject {
    enum BarMode {
        case rect, freeform, window, textExtract, colorPick

        init(_ mode: SnipStore.Mode) {
            switch mode {
            case .freeform: self = .freeform
            case .window: self = .window
            default: self = .rect
            }
        }
    }

    @Published var mode: BarMode
    var act: (SnipCaptureSession.Action) -> Void = { _ in }
    /// The view owning an active Quick Markup selection registers here;
    /// returning true consumes the ⏎ press.
    var returnHandler: (() -> Bool)?

    init(mode: BarMode) {
        self.mode = mode
    }
}

// MARK: - Overlay view

struct CaptureOverlayView: View {
    let context: SnipCaptureSession.ScreenContext
    let windowPicks: [SnipCaptureSession.WindowPick]
    @ObservedObject var model: CaptureOverlayModel
    let showToolbar: Bool

    // selection / quick markup
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var selectedRect: CGRect?
    @State private var quickAnnotations: [SnipAnnotation] = []
    @State private var currentStroke: SnipAnnotation?
    @State private var markupTool: QuickTool = .pen
    @State private var markupColor: Color = .red
    // freeform
    @State private var freeformPoints: [CGPoint] = []
    // hover (window highlight + color loupe)
    @State private var hoverPoint: CGPoint?

    enum QuickTool {
        case pen, highlighter, eraser
    }

    private let markupColors: [Color] = [.red, .yellow,
                                         Color(red: 0.38, green: 0.65, blue: 1.0), .white]

    var body: some View {
        ZStack(alignment: .topLeading) {
            captureLayer
            if showToolbar, selectedRect == nil {
                topBar
                    .frame(maxWidth: .infinity)
            }
            if let rect = selectedRect {
                markupBar(for: rect)
            }
            if model.mode == .colorPick, let point = hoverPoint {
                ColorLoupe(context: context, viewPoint: point)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            NSCursor.crosshair.set()
            model.returnHandler = { [weak model] in
                guard selectedRect != nil else { return false }
                commitSelection(openEditor: false)
                _ = model
                return true
            }
        }
        .onChange(of: model.mode) {
            resetSelection()
        }
    }

    private func resetSelection() {
        selectedRect = nil
        quickAnnotations = []
        currentStroke = nil
        dragStart = nil
        dragCurrent = nil
        freeformPoints = []
    }

    private func commitSelection(openEditor: Bool) {
        guard let rect = selectedRect else { return }
        model.act(.rectCapture(rect: rect,
                               annotations: quickAnnotations,
                               context: context,
                               openEditor: openEditor))
    }

    // MARK: capture layer

    private var liveRect: CGRect? {
        guard let dragStart, let dragCurrent else { return nil }
        return CGRect(x: min(dragStart.x, dragCurrent.x),
                      y: min(dragStart.y, dragCurrent.y),
                      width: abs(dragStart.x - dragCurrent.x),
                      height: abs(dragStart.y - dragCurrent.y))
    }

    private var hoveredPick: SnipCaptureSession.WindowPick? {
        guard model.mode == .window, let hoverPoint else { return nil }
        return windowPicks.first { localFrame($0).contains(hoverPoint) }
    }

    private func localFrame(_ pick: SnipCaptureSession.WindowPick) -> CGRect {
        pick.globalFrame.offsetBy(dx: -context.cgBounds.minX, dy: -context.cgBounds.minY)
    }

    private var captureLayer: some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: context.image, scale: context.scale)
                .resizable()
            Canvas { canvas, size in
                var dimmed = Path(CGRect(origin: .zero, size: size))
                var cutout: Path?
                switch model.mode {
                case .rect, .textExtract:
                    if let rect = selectedRect ?? liveRect, rect.width > 2 {
                        cutout = Path(rect)
                    }
                case .freeform:
                    if freeformPoints.count > 1 {
                        var path = Path()
                        path.addLines(freeformPoints)
                        path.closeSubpath()
                        cutout = path
                    }
                case .window:
                    if let pick = hoveredPick { cutout = Path(localFrame(pick)) }
                case .colorPick:
                    break
                }
                if let cutout {
                    dimmed.addPath(cutout)
                }
                canvas.fill(dimmed,
                            with: .color(.black.opacity(model.mode == .colorPick ? 0.12 : 0.45)),
                            style: FillStyle(eoFill: true))
                if let cutout {
                    canvas.stroke(cutout,
                                  with: .color(model.mode == .textExtract ? Theme.accent : .white),
                                  style: StrokeStyle(lineWidth: 1.5,
                                                     dash: model.mode == .window || selectedRect != nil
                                                         ? [] : [7, 4]))
                }
                // quick markup ink, clipped to the selection
                if let rect = selectedRect {
                    var inked = canvas
                    inked.clip(to: Path(rect))
                    drawSnipAnnotations(quickAnnotations, in: &inked, scale: 1)
                    if let currentStroke {
                        drawSnipAnnotations([currentStroke], in: &inked, scale: 1)
                    }
                }
                if model.mode == .rect || model.mode == .textExtract,
                   selectedRect == nil, let rect = liveRect, rect.width > 24 {
                    let label = "\(Int(rect.width * context.scale)) × \(Int(rect.height * context.scale))"
                    canvas.draw(Text(label).font(.system(size: 11, weight: .medium).monospacedDigit())
                                    .foregroundStyle(.white),
                                at: CGPoint(x: rect.midX, y: min(size.height - 12, rect.maxY + 14)))
                }
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            if case .active(let point) = phase {
                hoverPoint = point
            } else {
                hoverPoint = nil
            }
        }
        .gesture(dragGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                switch model.mode {
                case .rect, .textExtract:
                    if let rect = selectedRect {
                        if rect.contains(value.startLocation), model.mode == .rect {
                            markupDrag(value)
                        } else {
                            // drag outside the selection = start a new one
                            selectedRect = nil
                            quickAnnotations = []
                            dragStart = value.startLocation
                            dragCurrent = value.location
                        }
                    } else {
                        dragStart = value.startLocation
                        dragCurrent = value.location
                    }
                case .freeform:
                    freeformPoints.append(value.location)
                case .window, .colorPick:
                    break
                }
            }
            .onEnded { value in
                switch model.mode {
                case .rect, .textExtract:
                    if selectedRect != nil {
                        if let stroke = currentStroke {
                            quickAnnotations.append(stroke)
                            currentStroke = nil
                        }
                    } else if let rect = liveRect, rect.width > 4, rect.height > 4 {
                        if model.mode == .textExtract {
                            model.act(.textExtract(rect, context))
                        } else {
                            selectedRect = rect   // enter Quick Markup
                        }
                    }
                    dragStart = nil
                    dragCurrent = nil
                case .freeform:
                    if freeformPoints.count > 8 {
                        model.act(.freeform(freeformPoints, context))
                    }
                    freeformPoints = []
                case .window:
                    let travel = hypot(value.translation.width, value.translation.height)
                    if travel < 4, let pick = hoveredPick {
                        model.act(.window(pick))
                    }
                case .colorPick:
                    let travel = hypot(value.translation.width, value.translation.height)
                    if travel < 4 {
                        let hex = ColorLoupe.hex(at: value.location, context: context)
                        model.act(.colorPicked(hex))
                    }
                }
            }
    }

    private func markupDrag(_ value: DragGesture.Value) {
        switch markupTool {
        case .eraser:
            let point = value.location
            quickAnnotations.removeAll { annotation in
                if case .stroke(let points, _) = annotation.kind {
                    return points.contains { hypot($0.x - point.x, $0.y - point.y) < 12 }
                }
                return false
            }
        case .pen, .highlighter:
            if var stroke = currentStroke, case .stroke(var points, let hl) = stroke.kind {
                points.append(value.location)
                stroke.kind = .stroke(points: points, highlighter: hl)
                currentStroke = stroke
            } else {
                currentStroke = SnipAnnotation(kind: .stroke(points: [value.location],
                                                             highlighter: markupTool == .highlighter),
                                               color: markupColor, width: 3.5)
            }
        }
    }

    // MARK: top bar

    private var topBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 3) {
                barModeButton(.rect, icon: "rectangle.dashed", help: "Rectangle — drag, then mark up")
                barModeButton(.freeform, icon: "lasso", help: "Freeform — draw any shape")
                barModeButton(.window, icon: "macwindow", help: "Window — click one")
                Button {
                    model.act(.fullScreen(context))
                } label: {
                    barIcon("rectangle.inset.filled")
                }
                .buttonStyle(.plain)
                .help("Full screen — captures immediately")
                barDivider
                barModeButton(.textExtract, icon: "text.viewfinder",
                              help: "Text extractor — drag over text, it lands on the clipboard")
                barModeButton(.colorPick, icon: "eyedropper",
                              help: "Color picker — click any pixel to copy its hex")
                barDivider
                Menu {
                    ForEach([3, 5, 10], id: \.self) { seconds in
                        Button("Snip in \(seconds) s") {
                            model.act(.delay(TimeInterval(seconds)))
                        }
                    }
                } label: {
                    barIcon("timer")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 34, height: 28)
                .help("Delay — re-freezes the screen after the wait")
                barDivider
                Button {
                    model.act(.cancel)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 28)
                        .contentShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help("Cancel (Esc)")
            }
            .foregroundStyle(.white)
            .padding(5)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(.white.opacity(0.2), lineWidth: 1))
            .environment(\.colorScheme, .dark)
            .shadow(color: .black.opacity(0.4), radius: 14, y: 4)
            Text(hint)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.black.opacity(0.45), in: Capsule())
        }
        .padding(.top, 30)
    }

    private var barDivider: some View {
        Divider().frame(height: 18).padding(.horizontal, 3)
    }

    private func barIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 13))
            .frame(width: 34, height: 28)
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }

    private func barModeButton(_ mode: CaptureOverlayModel.BarMode,
                               icon: String, help: String) -> some View {
        Button {
            model.mode = mode
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13))
                .frame(width: 34, height: 28)
                .background(model.mode == mode ? Theme.accent.opacity(0.5) : .clear,
                            in: RoundedRectangle(cornerRadius: 7))
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var hint: String {
        switch model.mode {
        case .rect: return "Drag to select — then draw on it, ⏎ copies & saves · Esc cancels"
        case .freeform: return "Draw around what you want · Esc cancels"
        case .window: return "Click a window to capture it · Esc cancels"
        case .textExtract: return "Drag over text — it's copied as text · Esc cancels"
        case .colorPick: return "Click any pixel to copy its hex color · Esc cancels"
        }
    }

    // MARK: quick markup bar

    @ViewBuilder
    private func markupBar(for rect: CGRect) -> some View {
        let barHeight: CGFloat = 44
        let screenHeight = context.screen.frame.height
        let below = rect.maxY + barHeight + 16 < screenHeight
        HStack(spacing: 4) {
            ForEach(Array(markupColors.enumerated()), id: \.offset) { _, color in
                Button {
                    markupTool = markupTool == .highlighter ? .highlighter : .pen
                    markupColor = color
                } label: {
                    Circle()
                        .fill(color)
                        .frame(width: 15, height: 15)
                        .overlay(Circle().strokeBorder(
                            .white.opacity(markupColor == color && markupTool != .eraser ? 0.95 : 0.25),
                            lineWidth: markupColor == color && markupTool != .eraser ? 2 : 1))
                        .frame(width: 24, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            barDivider
            quickToolButton(.pen, icon: "pencil.tip", help: "Pen")
            quickToolButton(.highlighter, icon: "highlighter", help: "Highlighter")
            quickToolButton(.eraser, icon: "eraser", help: "Eraser — drag over a mark")
            Button {
                _ = quickAnnotations.popLast()
            } label: {
                barIcon("arrow.uturn.backward")
            }
            .buttonStyle(.plain)
            .disabled(quickAnnotations.isEmpty)
            .help("Undo last mark")
            barDivider
            Button("Copy  ⏎") {
                commitSelection(openEditor: false)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help("Copy to clipboard & save to Snips")
            Button("Edit") {
                commitSelection(openEditor: true)
            }
            .controlSize(.small)
            .help("Open in the full editor")
            Button {
                model.act(.cancel)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Cancel (Esc)")
        }
        .foregroundStyle(.white)
        .padding(5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(.white.opacity(0.2), lineWidth: 1))
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(0.4), radius: 12, y: 3)
        .fixedSize()
        .position(x: max(180, min(rect.midX, context.screen.frame.width - 180)),
                  y: below ? rect.maxY + 34 : max(30, rect.minY - 34))
    }

    private func quickToolButton(_ tool: QuickTool, icon: String, help: String) -> some View {
        Button {
            markupTool = tool
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12))
                .frame(width: 30, height: 28)
                .background(markupTool == tool ? Theme.accent.opacity(0.5) : .clear,
                            in: RoundedRectangle(cornerRadius: 7))
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Color loupe

/// Magnified pixel grid + hex readout following the cursor in color-pick mode.
private struct ColorLoupe: View {
    let context: SnipCaptureSession.ScreenContext
    let viewPoint: CGPoint

    private static let gridSize = 11
    private static let cell: CGFloat = 11

    var body: some View {
        let colors = Self.sample(context: context, viewPoint: viewPoint)
        let hex = Self.hex(at: viewPoint, context: context)
        let side = CGFloat(Self.gridSize) * Self.cell
        VStack(spacing: 6) {
            Canvas { canvas, _ in
                for (rowIndex, row) in colors.enumerated() {
                    for (columnIndex, color) in row.enumerated() {
                        let cellRect = CGRect(x: CGFloat(columnIndex) * Self.cell,
                                              y: CGFloat(rowIndex) * Self.cell,
                                              width: Self.cell, height: Self.cell)
                        canvas.fill(Path(cellRect), with: .color(Color(nsColor: color)))
                    }
                }
                // center pixel marker
                let mid = CGFloat(Self.gridSize / 2) * Self.cell
                canvas.stroke(Path(CGRect(x: mid, y: mid, width: Self.cell, height: Self.cell)),
                              with: .color(.white), lineWidth: 1.5)
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.7), lineWidth: 1))
            Text(hex)
                .font(.system(size: 11, weight: .semibold).monospaced())
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.black.opacity(0.75), in: Capsule())
        }
        .position(x: min(max(viewPoint.x + 80, 80), context.screen.frame.width - 80),
                  y: min(max(viewPoint.y - 90, 90), context.screen.frame.height - 90))
        .allowsHitTesting(false)
    }

    static func hex(at viewPoint: CGPoint, context: SnipCaptureSession.ScreenContext) -> String {
        let colors = sample(context: context, viewPoint: viewPoint)
        let center = colors[gridSize / 2][gridSize / 2]
        let r = Int(round(center.redComponent * 255))
        let g = Int(round(center.greenComponent * 255))
        let b = Int(round(center.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// Reads a gridSize×gridSize block of pixels centred on the cursor.
    static func sample(context: SnipCaptureSession.ScreenContext,
                       viewPoint: CGPoint) -> [[NSColor]] {
        let radius = gridSize / 2
        let centerX = Int(viewPoint.x * context.scale)
        let centerY = Int(viewPoint.y * context.scale)
        var buffer = [UInt8](repeating: 0, count: gridSize * gridSize * 4)
        let fallback = [[NSColor]](repeating: [NSColor](repeating: .black, count: gridSize),
                                   count: gridSize)
        guard let cg = CGContext(data: &buffer,
                                 width: gridSize, height: gridSize,
                                 bitsPerComponent: 8, bytesPerRow: gridSize * 4,
                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return fallback }
        // Draw the image so the wanted block lands on the tiny context.
        // CGContext origin is bottom-left; flip Y around the image height.
        let flippedCenterY = context.image.height - centerY
        cg.interpolationQuality = .none
        cg.draw(context.image,
                in: CGRect(x: -CGFloat(centerX - radius),
                           y: -CGFloat(flippedCenterY - radius - 1),
                           width: CGFloat(context.image.width),
                           height: CGFloat(context.image.height)))
        var rows: [[NSColor]] = []
        for row in 0..<gridSize {
            var line: [NSColor] = []
            for column in 0..<gridSize {
                // Buffer row 0 is the TOP of the tiny context's output.
                let offset = ((gridSize - 1 - row) * gridSize + column) * 4
                line.append(NSColor(srgbRed: CGFloat(buffer[offset]) / 255,
                                    green: CGFloat(buffer[offset + 1]) / 255,
                                    blue: CGFloat(buffer[offset + 2]) / 255,
                                    alpha: 1))
            }
            rows.append(line)
        }
        return rows.reversed()
    }
}
