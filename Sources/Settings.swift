import Foundation

enum TrackingMode: String, CaseIterable, Identifiable {
    case pen, mouse
    var id: String { rawValue }
    var title: String { self == .pen ? "Pen (absolute)" : "Mouse (relative)" }
}

enum ButtonAction: String, CaseIterable, Identifiable {
    case rightClick, doubleClick, middleClick, leftClick, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .rightClick: return "Right Click"
        case .doubleClick: return "Double Click"
        case .middleClick: return "Middle Click"
        case .leftClick: return "Left Click"
        case .none: return "Disabled"
        }
    }
}

/// Graphire4 tablet buttons.
enum PadAction: String, CaseIterable, Identifiable {
    case back, forward, undo, redo, rightClick, middleClick, doubleClick, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .back: return "Back (mouse button 4)"
        case .forward: return "Forward (mouse button 5)"
        case .undo: return "Undo (⌘Z)"
        case .redo: return "Redo (⇧⌘Z)"
        case .rightClick: return "Right Click"
        case .middleClick: return "Middle Click"
        case .doubleClick: return "Double Click"
        case .none: return "Disabled"
        }
    }
}

/// Graphire4 tablet scroll wheel.
enum PadWheelAction: String, CaseIterable, Identifiable {
    case scroll, zoom, disabled
    var id: String { rawValue }
    var title: String {
        switch self {
        case .scroll: return "Scroll"
        case .zoom: return "Zoom (⌘ + scroll)"
        case .disabled: return "Disabled"
        }
    }
}

/// User settings, persisted in UserDefaults. Only touched from the main thread.
final class Settings: ObservableObject {
    static let shared = Settings()
    static let allDisplays = "all"
    private let d = UserDefaults.standard

    @Published var mode: TrackingMode { didSet { d.set(mode.rawValue, forKey: "mode") } }
    /// Display UUID the pen maps to, or `Settings.allDisplays`.
    @Published var displayUUID: String { didSet { d.set(displayUUID, forKey: "displayUUID") } }
    @Published var forceProportions: Bool { didSet { d.set(forceProportions, forKey: "forceProportions") } }
    @Published var leftHanded: Bool { didSet { d.set(leftHanded, forKey: "leftHanded") } }
    /// Fraction of full pressure needed before the tip clicks (0 = lightest touch).
    @Published var tipThreshold: Double { didSet { d.set(tipThreshold, forKey: "tipThreshold") } }
    /// Exponent applied to pressure sent to apps: <1 soft, 1 linear, >1 firm.
    @Published var pressureCurve: Double { didSet { d.set(pressureCurve, forKey: "pressureCurve") } }
    @Published var lowerButton: ButtonAction { didSet { d.set(lowerButton.rawValue, forKey: "lowerButton") } }
    @Published var upperButton: ButtonAction { didSet { d.set(upperButton.rawValue, forKey: "upperButton") } }
    /// Speed multiplier for mouse mode and the Graphire mouse.
    @Published var mouseSpeed: Double { didSet { d.set(mouseSpeed, forKey: "mouseSpeed") } }
    /// 0 = raw, up to 0.8 = heavy smoothing of pen jitter.
    @Published var smoothing: Double { didSet { d.set(smoothing, forKey: "smoothing") } }
    @Published var padBackButton: PadAction { didSet { d.set(padBackButton.rawValue, forKey: "padBackButton") } }
    @Published var padForwardButton: PadAction { didSet { d.set(padForwardButton.rawValue, forKey: "padForwardButton") } }
    @Published var padWheel: PadWheelAction { didSet { d.set(padWheel.rawValue, forKey: "padWheel") } }

    private init() {
        d.register(defaults: [
            "mode": TrackingMode.pen.rawValue,
            "forceProportions": false,
            "leftHanded": false,
            "tipThreshold": 0.02,
            "pressureCurve": 1.0,
            "lowerButton": ButtonAction.rightClick.rawValue,
            "upperButton": ButtonAction.doubleClick.rawValue,
            "mouseSpeed": 1.0,
            "smoothing": 0.25,
        ])
        mode = TrackingMode(rawValue: d.string(forKey: "mode") ?? "") ?? .pen
        // First launch: map to the built-in display (what already worked with the Wacom driver).
        displayUUID = d.string(forKey: "displayUUID") ?? Displays.builtinUUID() ?? Settings.allDisplays
        forceProportions = d.bool(forKey: "forceProportions")
        leftHanded = d.bool(forKey: "leftHanded")
        tipThreshold = d.double(forKey: "tipThreshold")
        pressureCurve = d.double(forKey: "pressureCurve")
        lowerButton = ButtonAction(rawValue: d.string(forKey: "lowerButton") ?? "") ?? .rightClick
        upperButton = ButtonAction(rawValue: d.string(forKey: "upperButton") ?? "") ?? .doubleClick
        mouseSpeed = d.double(forKey: "mouseSpeed")
        smoothing = d.double(forKey: "smoothing")
        padBackButton = PadAction(rawValue: d.string(forKey: "padBackButton") ?? "") ?? .back
        padForwardButton = PadAction(rawValue: d.string(forKey: "padForwardButton") ?? "") ?? .forward
        padWheel = PadWheelAction(rawValue: d.string(forKey: "padWheel") ?? "") ?? .scroll
        d.set(displayUUID, forKey: "displayUUID")
    }

    func resetToDefaults() {
        mode = .pen
        displayUUID = Displays.builtinUUID() ?? Settings.allDisplays
        forceProportions = false
        leftHanded = false
        tipThreshold = 0.02
        pressureCurve = 1.0
        lowerButton = .rightClick
        upperButton = .doubleClick
        mouseSpeed = 1.0
        smoothing = 0.25
        padBackButton = .back
        padForwardButton = .forward
        padWheel = .scroll
    }
}
