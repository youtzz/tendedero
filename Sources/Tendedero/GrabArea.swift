import AppKit
import SwiftUI

/// Bridges each photo to AppKit's drag and drop, so it can be dragged into
/// any app as a real file. Each destination means one thing:
///
/// - An app gets a copy, and the photo stays on the line.
/// - A folder or the Desktop keeps the file, and the photo leaves the line.
/// - The Trash discards it.
/// - Nowhere that accepts it: the photo flies back to the line.
///
/// A click copies, but only once the double-click window has passed, so a
/// double click opens the photo instead; press and hold opens Markup, the
/// corner cross discards.
struct GrabArea: NSViewRepresentable {
    let item: Pegged
    let line: Line

    func makeNSView(context: Context) -> GrabView {
        let view = GrabView()
        configure(view)
        return view
    }

    func updateNSView(_ view: GrabView, context: Context) {
        configure(view)
    }

    private func configure(_ view: GrabView) {
        let id = item.id
        let line = line
        let isRecording = item.isRecording
        view.url = item.url
        view.dragImage = item.thumb
        view.onClick = { line.copy(id) }
        view.onDoubleClick = { line.open(id) }
        view.onDragStart = { line.draggingID = id }
        view.onDragEnd = {
            line.draggingID = nil
            // Moved into a folder: it is saved where you wanted it.
            line.prune()
        }
        view.onTrash = { line.trash(id) }
        view.onDiscard = { line.discard(id) }
        view.onLongPress = { line.markup(id) }
        view.onForceClick = { line.quickLook(id) }
        view.onPressChange = { pressed in line.pressedID = pressed ? id : nil }
        // The hover buttons, as CleanShot's own overlay has them.
        view.onCopy = { line.copy(id) }
        view.hidesOnly = !line.isInInbox(id)
        if line.isInInbox(id) {
            view.onSave = { line.saveToDesktop(id) }
        }
        if CleanShotTools.isInstalled, !isRecording {
            view.onPin = { line.handToCleanShot("pin", id) }
            view.onEdit = { line.handToCleanShot("open-annotate", id) }
        }
        view.menuProvider = {
            let menu = NSMenu()
            // Items say themselves whether they can be used.
            menu.autoenablesItems = false
            menu.addItem(ClosureMenuItem(L("Copy")) { line.copy(id) })
            menu.addItem(ClosureMenuItem(L("Open")) { line.open(id) })
            menu.addItem(ClosureMenuItem(L("Quick Look")) { line.quickLook(id) })
            if !isRecording {
                menu.addItem(ClosureMenuItem(L("Markup")) { line.markup(id) })
            }
            menu.addItem(ClosureMenuItem(L("Show in Finder")) { line.reveal(id) })
            if CleanShotTools.isInstalled {
                let cleanShotItem = NSMenuItem(title: L("CleanShot"), action: nil, keyEquivalent: "")
                let cleanShotMenu = NSMenu()
                cleanShotMenu.autoenablesItems = false
                if !isRecording {
                    cleanShotMenu.addItem(ClosureMenuItem(L("Edit in CleanShot")) { line.handToCleanShot("open-annotate", id) })
                    cleanShotMenu.addItem(ClosureMenuItem(L("Pin in CleanShot")) { line.handToCleanShot("pin", id) })
                }
                cleanShotMenu.addItem(ClosureMenuItem(L("Send to CleanShot overlay")) { line.handToCleanShot("add-quick-access-overlay", id) })
                cleanShotItem.submenu = cleanShotMenu
                menu.addItem(cleanShotItem)
            }
            let inInbox = line.isInInbox(id)
            if inInbox {
                menu.addItem(ClosureMenuItem(L("Save to Desktop")) { line.saveToDesktop(id) })
            }
            menu.addItem(.separator())
            if inInbox {
                menu.addItem(ClosureMenuItem(L("Discard")) { line.discard(id) })
            } else {
                menu.addItem(ClosureMenuItem(L("Take down")) { line.discard(id) })
                menu.addItem(ClosureMenuItem(L("Move to Trash")) { line.trash(id) })
            }
            let left = ClosureMenuItem(L("Take down everything to the left")) { line.takeDown(id, toTheLeft: true) }
            left.isEnabled = !line.neighbours(of: id, toTheLeft: true).isEmpty
            menu.addItem(left)
            let right = ClosureMenuItem(L("Take down everything to the right")) { line.takeDown(id, toTheLeft: false) }
            right.isEnabled = !line.neighbours(of: id, toTheLeft: false).isEmpty
            menu.addItem(right)
            return menu
        }
    }
}

final class GrabView: NSView, NSDraggingSource {
    static var isDragging = false
    /// A photo's menu is open. It reaches past the line, so the line waits.
    static var isShowingMenu = false

    var url: URL?
    var dragImage: NSImage?
    var onClick: () -> Void = {}
    var onDoubleClick: () -> Void = {}
    var onDragStart: () -> Void = {}
    var onDragEnd: () -> Void = {}
    var onTrash: () -> Void = {}
    var onDiscard: () -> Void = {}
    var onLongPress: () -> Void = {}
    var onForceClick: () -> Void = {}
    var onPressChange: (Bool) -> Void = { _ in }
    var menuProvider: () -> NSMenu = { NSMenu() }
    var onCopy: () -> Void = {}
    /// The rest are there only when their button makes sense: Save for files
    /// in Tendedero's folder, pin and edit when CleanShot is installed.
    var onSave: (() -> Void)?
    var onPin: (() -> Void)?
    var onEdit: (() -> Void)?
    /// A file in Tendedero's folder is discarded with a cross; one anywhere
    /// else is only taken off the line, and says so with an eye.
    var hidesOnly = false

    private var downPoint: NSPoint?
    private var startedDrag = false
    private var holdTimer: Timer?
    private var didLongPress = false
    /// The click waiting to see whether a second one follows it. See
    /// `deferAction`.
    private var clickWork: DispatchWorkItem?

    /// How long you hold before Markup opens. Long enough not to fire on a
    /// slow click, short enough to feel deliberate.
    private static let holdDuration: TimeInterval = 0.45

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The buttons drawn over the card while the pointer is on it, as in
    /// CleanShot's own overlay: close in the top left, pin in the top right,
    /// edit in the bottom left, Copy and Save as pills in the middle.
    private enum Control { case close, pin, edit, copy, save }
    private var pressedControl: Control?
    private var hovering = false
    private var tracking: NSTrackingArea?
    private var hoverCheck: Timer?

    private static let circleSize: CGFloat = 20
    private static let margin: CGFloat = 3
    private static let pillSize = CGSize(width: 56, height: 20)
    private static let pillGap: CGFloat = 4

    /// Where each button sits, in view coordinates. Written from the top
    /// left, then mirrored into AppKit's bottom-left space.
    private func controlRects() -> [(Control, NSRect)] {
        func fromTop(_ rect: NSRect) -> NSRect {
            NSRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
        }
        let s = Self.circleSize, m = Self.margin
        var out: [(Control, NSRect)] = [
            (.close, fromTop(NSRect(x: m, y: m, width: s, height: s))),
        ]
        if onPin != nil {
            out.append((.pin, fromTop(NSRect(x: bounds.width - m - s, y: m, width: s, height: s))))
        }
        if onEdit != nil {
            out.append((.edit, fromTop(NSRect(x: m, y: bounds.height - m - s, width: s, height: s))))
        }
        // The pills need room; a very short card keeps only the corner
        // buttons, and Copy stays on a plain click.
        guard bounds.height >= 62 else { return out }
        var pills: [Control] = [.copy]
        if onSave != nil { pills.append(.save) }
        let p = Self.pillSize
        let total = CGFloat(pills.count) * p.height + CGFloat(max(pills.count - 1, 0)) * Self.pillGap
        var top = (bounds.height - total) / 2
        for control in pills {
            out.append((control, fromTop(NSRect(x: (bounds.width - p.width) / 2, y: top,
                                                width: p.width, height: p.height))))
            top += p.height + Self.pillGap
        }
        return out
    }

    private func control(at point: NSPoint) -> Control? {
        for (control, rect) in controlRects() where rect.insetBy(dx: -2, dy: -2).contains(point) {
            return control
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        // The second click of a double click: the single click it completes
        // is called off, wherever it was aimed, and the photo opens. The
        // hover buttons sit right where the eye aims and would otherwise
        // fire twice, or copy a photo that was only being looked at.
        if event.clickCount == 2 {
            clickWork?.cancel()
            clickWork = nil
            pressedControl = nil
            downPoint = nil
            needsDisplay = true
            onDoubleClick()
            return
        }
        if let control = control(at: convert(event.locationInWindow, from: nil)) {
            pressedControl = control
            needsDisplay = true
            return
        }
        downPoint = event.locationInWindow
        startedDrag = false
        didLongPress = false
        onPressChange(true)
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: Self.holdDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.downPoint != nil, !self.startedDrag else { return }
                self.didLongPress = true
                self.onPressChange(false)
                self.onLongPress()
            }
        }
    }

    /// A force click on a trackpad opens Quick Look, as it does in Finder.
    /// It counts instead of the click and of a long press.
    override func pressureChange(with event: NSEvent) {
        guard event.stage == 2, downPoint != nil, !startedDrag, !didLongPress else { return }
        didLongPress = true
        endPress()
        onForceClick()
    }

    private func endPress() {
        holdTimer?.invalidate()
        holdTimer = nil
        onPressChange(false)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downPoint, !startedDrag, let url else { return }
        let p = event.locationInWindow
        guard hypot(p.x - start.x, p.y - start.y) > 4, !didLongPress else { return }
        startedDrag = true
        endPress()

        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(imageFrame(), contents: dragImage)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        // Released where nothing accepts it: it flies back to the line.
        session.animatesToStartingPositionsOnCancelOrFail = true
        GrabView.isDragging = true
        onDragStart()
    }

    override func mouseUp(with event: NSEvent) {
        if let pressed = pressedControl {
            pressedControl = nil
            needsDisplay = true
            if control(at: convert(event.locationInWindow, from: nil)) == pressed { fire(pressed) }
            return
        }
        endPress()
        if downPoint != nil && !startedDrag && !didLongPress && event.clickCount == 1 {
            deferAction { [weak self] in self?.onClick() }
        }
        downPoint = nil
        didLongPress = false
    }

    private func fire(_ control: Control) {
        switch control {
        case .close: onDiscard()
        // Copy and Save wait a double click out too: the pills sit in the
        // middle of the card, right where a double click to open lands.
        case .copy: deferAction { [weak self] in self?.onCopy() }
        case .save: deferAction { [weak self] in self?.onSave?() }
        case .pin: onPin?()
        case .edit: onEdit?()
        }
    }

    /// A click acts only once the double-click window has passed, so the
    /// second click of a double click can call it off and open the photo
    /// instead: a photo that was only being looked at is neither copied nor
    /// taken down.
    private func deferAction(_ action: @escaping () -> Void) {
        clickWork?.cancel()
        let work = DispatchWorkItem(block: action)
        clickWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
    }

    override func rightMouseDown(with event: NSEvent) {
        // The menu runs until it closes, and the line stays down meanwhile.
        GrabView.isShowingMenu = true
        NSMenu.popUpContextMenu(menuProvider(), with: event, for: self)
        GrabView.isShowingMenu = false
    }

    // MARK: Hover buttons

    /// The pointer is on the card: the buttons show up, as CleanShot's do.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
        hoverCheck?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.verifyHover() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverCheck = timer
    }

    override func mouseExited(with event: NSEvent) {
        leaveHover()
    }

    /// Taken off the line: no hover state survives the trip.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { leaveHover() }
    }

    private func leaveHover() {
        hoverCheck?.invalidate()
        hoverCheck = nil
        guard hovering else { return }
        hovering = false
        pressedControl = nil
        needsDisplay = true
    }

    /// A tracking area misses the exit when the panel stops taking mouse
    /// events mid-hover, so while the pointer is here its place is also
    /// checked against the view's own frame, and the buttons go when it left.
    private func verifyHover() {
        guard let window else { return }
        let inView = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        if !bounds.insetBy(dx: -6, dy: -6).contains(inView) {
            leaveHover()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard hovering, !GrabView.isDragging else { return }
        for (control, rect) in controlRects() {
            draw(control, in: rect, pressed: control == pressedControl)
        }
    }

    /// White circles and pills, like the ones CleanShot draws over its own
    /// captures: they read on any photo.
    private func draw(_ control: Control, in rect: NSRect, pressed: Bool) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = 2.5
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()

        let alpha: CGFloat = pressed ? 0.66 : 0.94
        switch control {
        case .copy, .save:
            let pill = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
            NSColor.white.withAlphaComponent(alpha).setFill()
            pill.fill()
            let title = (control == .copy ? L("Copy") : L("Save")) as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.black.withAlphaComponent(0.78),
            ]
            let size = title.size(withAttributes: attributes)
            title.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                       withAttributes: attributes)
        case .close, .pin, .edit:
            NSColor.white.withAlphaComponent(alpha).setFill()
            NSBezierPath(ovalIn: rect).fill()
            let symbol: String
            switch control {
            case .close: symbol = hidesOnly ? "eye.slash" : "xmark"
            case .pin: symbol = "pin"
            default: symbol = "pencil.tip"
            }
            let configuration = NSImage.SymbolConfiguration(pointSize: 9, weight: control == .close ? .bold : .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.black.withAlphaComponent(0.75)]))
            if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration) {
                let size = image.size
                image.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                                      width: size.width, height: size.height))
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Apps pick copy. Finder picks move, so a folder or the Desktop keeps
        // the file. Delete is what lets the Dock's Trash accept it.
        context == .outsideApplication ? [.copy, .move, .delete] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        GrabView.isDragging = false
        startedDrag = false
        downPoint = nil
        log.notice("Drag ended with operation \(operation.rawValue, privacy: .public)")
        // Dropped on the Trash: macOS only tells us, we move the file.
        if operation.contains(.delete) {
            onDragEnd()
            onTrash()
            return
        }
        onDragEnd()
        // Finder finishes a move a moment later. Check again then, so a photo
        // saved into a folder leaves the line.
        if operation.contains(.move) {
            let done = onDragEnd
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { done() }
        }
    }

    /// The drag preview keeps the photo's aspect ratio inside the card.
    private func imageFrame() -> NSRect {
        guard let size = dragImage?.size, size.width > 0, size.height > 0 else { return bounds }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return NSRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }
}
