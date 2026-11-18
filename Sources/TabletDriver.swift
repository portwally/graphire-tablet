import AppKit
import Combine
import CoreGraphics
import IOKit.hid

/// Live state shown in the settings window and menu.
final class TabletState: ObservableObject {
    static let shared = TabletState()
    enum Connection: Equatable { case searching, connected, failed(String) }
    @Published var connection: Connection = .searching
    @Published var tool: String = "—"
    @Published var pressure: Double = 0
    @Published var accessibilityGranted = false
}

/// User-space driver for the Wacom Graphire (ET-0405-U, USB 056A:0010).
///
/// Protocol (from the Linux `wacom_graphire_irq`, confirmed on this tablet):
///   - Feature report 2 = [0x02, 0x02] switches the tablet from mouse mode to tablet mode.
///   - Input report 2, 8 bytes:
///       d[1] bit7 proximity, bits5-6 tool (0 pen, 1 eraser, 2 mouse w/ wheel, 3 mouse)
///            bit0 tip / left, bit1 lower switch / right, bit2 upper switch / middle
///       d[2..3] X (LE, 0...10206), d[4..5] Y (LE, 0...7422)
///       pen:   pressure = d[6] | (d[7] & 3) << 8  (0...511)
///       mouse: wheel = -(Int8)d[6]
final class TabletDriver {
    static let vendorID = 0x056A
    static let productID = 0x0010
    static let maxX = 10206.0
    static let maxY = 7422.0
    static let maxPressure = 511.0
    /// Points moved per tablet count at mouse speed 1.0 (tablet is ~2032 counts/inch).
    static let relativeScale = 0.15

    enum Tool { case pen, eraser, mouse }

    private let settings = Settings.shared
    private let state = TabletState.shared
    private let source = CGEventSource(stateID: .hidSystemState)
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var observers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()

    // Pointer state
    private var inProximity = false
    private var tool: Tool = .pen
    private var cursor = CGPoint.zero
    private var lastRaw: CGPoint?
    private var smoothed: CGPoint?
    private var rawPoint = CGPoint.zero
    private var pressure = 0.0
    private var buttonMask: Int64 = 0

    // Button state
    private var tipDown = false          // pen tip or mouse left button
    private var buttonLeftDown = false   // side switch mapped to Left Click
    private var rightDown = false
    private var middleDown = false
    private var lowerHeld = false
    private var upperHeld = false

    // Click counting (double-click detection)
    private var clickCount: Int64 = 1
    private var lastClickTime: TimeInterval = 0
    private var lastClickPoint = CGPoint.zero

    private var mappingRect: CGRect?
    private var lastModeRequest: TimeInterval = 0
    private var reportsLogged = 0
    private let proximityDeviceID: Int64 = 0x5A

    private var leftIsDown: Bool { tipDown || buttonLeftDown }

    // MARK: - Lifecycle

    func start() {
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = m
        IOHIDManagerSetDeviceMatching(m, [kIOHIDVendorIDKey: Self.vendorID,
                                          kIOHIDProductIDKey: Self.productID] as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(m, { ctx, _, _, dev in
            Unmanaged<TabletDriver>.fromOpaque(ctx!).takeUnretainedValue().attached(dev)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(m, { ctx, _, _, dev in
            Unmanaged<TabletDriver>.fromOpaque(ctx!).takeUnretainedValue().removed(dev)
        }, ctx)
        IOHIDManagerRegisterInputReportCallback(m, { ctx, _, _, _, reportID, report, length in
            Unmanaged<TabletDriver>.fromOpaque(ctx!).takeUnretainedValue()
                .handleReport(reportID: reportID, report: report, length: length)
        }, ctx)
        // Common modes: keep tracking while menus are open or windows are being dragged.
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        var r = IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        Log.write("IOHIDManagerOpen(seize) = \(Log.hex(r))")
        if r != kIOReturnSuccess {
            r = IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
            Log.write("IOHIDManagerOpen(shared) = \(Log.hex(r))")
            if r != kIOReturnSuccess {
                state.connection = .failed("Could not open the tablet (\(Log.hex(r))). Is the Wacom driver still running?")
            }
        }

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                        object: nil, queue: .main) { [weak self] _ in self?.mappingRect = nil })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Log.write("wake: re-sending tablet mode")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self?.setTabletMode() }
            })
        settings.objectWillChange
            .sink { [weak self] in DispatchQueue.main.async { self?.mappingRect = nil } }
            .store(in: &cancellables)
    }

    private func attached(_ dev: IOHIDDevice) {
        Log.write("tablet attached")
        device = dev
        state.connection = .connected
        setTabletMode()
    }

    private func removed(_ dev: IOHIDDevice) {
        Log.write("tablet removed")
        if inProximity { leaveProximity() }
        device = nil
        state.connection = .searching
    }

    /// Switch from boot-mouse mode to full tablet mode (Linux: wacom_set_device_mode, report 2 = 2).
    private func setTabletMode() {
        guard let dev = device else { return }
        lastModeRequest = ProcessInfo.processInfo.systemUptime
        for attempt in 1...3 {
            var data: [UInt8] = [2, 2]
            let r = IOHIDDeviceSetReport(dev, kIOHIDReportTypeFeature, 2, &data, data.count)
            var back = [UInt8](repeating: 0, count: 2)
            var len = back.count
            let g = IOHIDDeviceGetReport(dev, kIOHIDReportTypeFeature, 2, &back, &len)
            Log.write("set tablet mode attempt \(attempt): set=\(Log.hex(r)) get=\(Log.hex(g)) value=\(back)")
            if r == kIOReturnSuccess && g == kIOReturnSuccess && back == [2, 2] { return }
        }
    }

    // MARK: - Report parsing

    private func handleReport(reportID: UInt32, report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        var d = Array(UnsafeBufferPointer(start: report, count: length))
        // On this tablet macOS delivers 8 bytes including the report ID; be tolerant anyway.
        if reportID != 0, d.count == 7 { d.insert(UInt8(reportID), at: 0) }
        if reportsLogged < 5 {
            reportsLogged += 1
            Log.write("report id=\(reportID) len=\(length): " + d.map { String(format: "%02x", $0) }.joined(separator: " "))
        }
        guard let id = d.first else { return }
        if id == 2, d.count >= 8 {
            process(d)
        } else if id == 1, ProcessInfo.processInfo.systemUptime - lastModeRequest > 1 {
            Log.write("got mouse-mode report; switching to tablet mode again")
            setTabletMode()
        }
    }

    private func process(_ d: [UInt8]) {
        guard d[1] & 0x80 != 0 else {
            if inProximity { leaveProximity() }
            return
        }
        let newTool: Tool
        switch (d[1] >> 5) & 3 {
        case 0: newTool = .pen
        case 1: newTool = .eraser
        default: newTool = .mouse
        }
        if inProximity && newTool != tool { leaveProximity() }
        if !inProximity {
            tool = newTool
            enterProximity()
        }

        var raw = CGPoint(x: Double(UInt16(d[2]) | UInt16(d[3]) << 8),
                          y: Double(UInt16(d[4]) | UInt16(d[5]) << 8))
        if settings.leftHanded { raw = CGPoint(x: Self.maxX - raw.x, y: Self.maxY - raw.y) }
        rawPoint = raw

        if tool == .mouse { processMouse(d, raw) } else { processPen(d, raw) }
    }

    private func processPen(_ d: [UInt8], _ raw: CGPoint) {
        let p = min(1, Double(Int(d[6]) | Int(d[7] & 0x03) << 8) / Self.maxPressure)
        let touching = d[1] & 0x01 != 0
        let lower = d[1] & 0x02 != 0
        let upper = d[1] & 0x04 != 0
        state.pressure = p

        // Tip click with hysteresis so it doesn't chatter around the threshold.
        let threshold = settings.tipThreshold
        let wantTip = tipDown ? (touching && p >= threshold * 0.5) : (touching && p >= threshold)
        pressure = wantTip
            ? max(0.001, pow(max(0, (p - threshold) / max(0.0001, 1 - threshold)), settings.pressureCurve))
            : 0
        buttonMask = (wantTip ? 1 : 0) | (lower ? 2 : 0) | (upper ? 4 : 0)

        let point = settings.mode == .pen ? absolutePoint(smooth(raw)) : relativePoint(raw)
        let moved = hypot(point.x - cursor.x, point.y - cursor.y) >= 0.3
        if moved || (leftIsDown && wantTip) { postMotion(to: point) }

        if wantTip != tipDown {
            tipDown = wantTip
            if !buttonLeftDown { postLeft(down: wantTip) }
        }
        handleSideButton(pressed: lower, held: &lowerHeld, action: settings.lowerButton)
        handleSideButton(pressed: upper, held: &upperHeld, action: settings.upperButton)
    }

    private func processMouse(_ d: [UInt8], _ raw: CGPoint) {
        let left = d[1] & 0x01 != 0
        let right = d[1] & 0x02 != 0
        let middle = (d[1] >> 5) & 3 == 2 && d[1] & 0x04 != 0
        let wheel = -Int(Int8(bitPattern: d[6]))
        pressure = 0
        buttonMask = 0

        let point = relativePoint(raw)
        if point != cursor { postMotion(to: point) }
        if left != tipDown { tipDown = left; postLeft(down: left) }
        if right != rightDown {
            rightDown = right
            post(right ? .rightMouseDown : .rightMouseUp, button: .right, clickState: 1)
        }
        if middle != middleDown {
            middleDown = middle
            post(middle ? .otherMouseDown : .otherMouseUp, button: .center, clickState: 1)
        }
        if wheel != 0 {
            CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 1,
                    wheel1: Int32(wheel), wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Proximity

    private func enterProximity() {
        inProximity = true
        lastRaw = nil
        smoothed = nil
        cursor = CGEvent(source: nil)?.location ?? .zero
        state.tool = tool == .pen ? "Pen" : tool == .eraser ? "Eraser" : "Mouse"
        if tool != .mouse { postProximity(enter: true) }
    }

    private func leaveProximity() {
        if tipDown { tipDown = false; if !buttonLeftDown { postLeft(down: false) } }
        if buttonLeftDown { buttonLeftDown = false; postLeft(down: false) }
        if rightDown { rightDown = false; post(.rightMouseUp, button: .right, clickState: 1) }
        if middleDown { middleDown = false; post(.otherMouseUp, button: .center, clickState: 1) }
        lowerHeld = false
        upperHeld = false
        pressure = 0
        buttonMask = 0
        if tool != .mouse { postProximity(enter: false) }
        inProximity = false
        state.tool = "—"
        state.pressure = 0
    }

    private func postProximity(enter: Bool) {
        guard let e = CGEvent(source: source) else { return }
        e.type = .tabletProximity
        e.location = cursor
        e.setIntegerValueField(.tabletProximityEventVendorID, value: Int64(Self.vendorID))
        e.setIntegerValueField(.tabletProximityEventTabletID, value: 1)
        e.setIntegerValueField(.tabletProximityEventPointerID, value: tool == .eraser ? 1 : 0)
        e.setIntegerValueField(.tabletProximityEventDeviceID, value: proximityDeviceID)
        e.setIntegerValueField(.tabletProximityEventSystemTabletID, value: 1)
        e.setIntegerValueField(.tabletProximityEventVendorPointerType, value: tool == .eraser ? 0x082A : 0x0812)
        e.setIntegerValueField(.tabletProximityEventVendorPointerSerialNumber, value: 1)
        e.setIntegerValueField(.tabletProximityEventVendorUniqueID, value: 1)
        // device id | abs x | abs y | buttons | pressure
        e.setIntegerValueField(.tabletProximityEventCapabilityMask, value: 0x0447)
        e.setIntegerValueField(.tabletProximityEventPointerType, value: tool == .eraser ? 3 : 1)
        e.setIntegerValueField(.tabletProximityEventEnterProximity, value: enter ? 1 : 0)
        e.post(tap: .cghidEventTap)
    }

    // MARK: - Buttons

    private func handleSideButton(pressed: Bool, held: inout Bool, action: ButtonAction) {
        guard pressed != held else { return }
        held = pressed
        switch action {
        case .none:
            break
        case .rightClick:
            rightDown = pressed
            post(pressed ? .rightMouseDown : .rightMouseUp, button: .right, clickState: 1)
        case .middleClick:
            middleDown = pressed
            post(pressed ? .otherMouseDown : .otherMouseUp, button: .center, clickState: 1)
        case .leftClick:
            buttonLeftDown = pressed
            if !tipDown { postLeft(down: pressed) }
        case .doubleClick:
            guard pressed, !leftIsDown else { return }
            post(.leftMouseDown, button: .left, clickState: 1)
            post(.leftMouseUp, button: .left, clickState: 1)
            post(.leftMouseDown, button: .left, clickState: 2)
            post(.leftMouseUp, button: .left, clickState: 2)
            clickCount = 2
            lastClickTime = ProcessInfo.processInfo.systemUptime
            lastClickPoint = cursor
        }
    }

    private func postLeft(down: Bool) {
        if down {
            let now = ProcessInfo.processInfo.systemUptime
            let near = hypot(cursor.x - lastClickPoint.x, cursor.y - lastClickPoint.y) <= 8
            clickCount = (now - lastClickTime <= NSEvent.doubleClickInterval && near) ? clickCount + 1 : 1
            lastClickTime = now
            lastClickPoint = cursor
        }
        post(down ? .leftMouseDown : .leftMouseUp, button: .left, clickState: clickCount)
    }

    // MARK: - Motion

    private func postMotion(to point: CGPoint) {
        let type: CGEventType
        let button: CGMouseButton
        if leftIsDown { type = .leftMouseDragged; button = .left }
        else if rightDown { type = .rightMouseDragged; button = .right }
        else if middleDown { type = .otherMouseDragged; button = .center }
        else { type = .mouseMoved; button = .left }
        let delta = CGPoint(x: point.x - cursor.x, y: point.y - cursor.y)
        cursor = point
        post(type, button: button, clickState: leftIsDown ? clickCount : 0, delta: delta)
    }

    private func post(_ type: CGEventType, button: CGMouseButton, clickState: Int64, delta: CGPoint = .zero) {
        guard let e = CGEvent(mouseEventSource: source, mouseType: type,
                              mouseCursorPosition: cursor, mouseButton: button) else { return }
        if tool != .mouse && inProximity {
            e.setIntegerValueField(.mouseEventSubtype, value: Int64(CGEventMouseSubtype.tabletPoint.rawValue))
            e.setDoubleValueField(.mouseEventPressure, value: pressure)
            e.setIntegerValueField(.tabletEventPointX, value: Int64(rawPoint.x))
            e.setIntegerValueField(.tabletEventPointY, value: Int64(rawPoint.y))
            e.setDoubleValueField(.tabletEventPointPressure, value: pressure)
            e.setIntegerValueField(.tabletEventDeviceID, value: proximityDeviceID)
            e.setIntegerValueField(.tabletEventPointButtons, value: buttonMask)
        }
        if clickState > 0 { e.setIntegerValueField(.mouseEventClickState, value: clickState) }
        e.setIntegerValueField(.mouseEventDeltaX, value: Int64(delta.x.rounded()))
        e.setIntegerValueField(.mouseEventDeltaY, value: Int64(delta.y.rounded()))
        e.post(tap: .cghidEventTap)
    }

    private func smooth(_ raw: CGPoint) -> CGPoint {
        let s = min(max(settings.smoothing, 0), 0.9)
        guard let prev = smoothed, s > 0 else { smoothed = raw; return raw }
        // Don't smooth big jumps (pen placed somewhere new).
        if hypot(raw.x - prev.x, raw.y - prev.y) > 400 { smoothed = raw; return raw }
        let p = CGPoint(x: prev.x + (raw.x - prev.x) * (1 - s), y: prev.y + (raw.y - prev.y) * (1 - s))
        smoothed = p
        return p
    }

    private func absolutePoint(_ raw: CGPoint) -> CGPoint {
        let rect: CGRect
        if let r = mappingRect { rect = r } else { rect = Displays.rect(for: settings.displayUUID); mappingRect = rect }
        var areaW = Self.maxX, areaH = Self.maxY
        if settings.forceProportions, rect.height > 0 {
            let screenAspect = rect.width / rect.height
            if screenAspect > areaW / areaH { areaH = areaW / screenAspect } else { areaW = areaH * screenAspect }
        }
        let nx = min(max(raw.x / areaW, 0), 1)
        let ny = min(max(raw.y / areaH, 0), 1)
        return CGPoint(x: rect.minX + nx * (rect.width - 1), y: rect.minY + ny * (rect.height - 1))
    }

    private func relativePoint(_ raw: CGPoint) -> CGPoint {
        defer { lastRaw = raw }
        guard let last = lastRaw else { return cursor }
        let scale = Self.relativeScale * settings.mouseSpeed
        var p = CGPoint(x: cursor.x + (raw.x - last.x) * scale, y: cursor.y + (raw.y - last.y) * scale)
        let b = Displays.desktopBounds()
        p.x = min(max(p.x, b.minX), b.maxX - 1)
        p.y = min(max(p.y, b.minY), b.maxY - 1)
        return p
    }
}
