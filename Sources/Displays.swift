import AppKit

struct DisplayInfo: Identifiable, Hashable {
    let id: String              // display UUID (stable across reboots)
    let name: String
    let displayID: CGDirectDisplayID
}

enum Displays {
    static func uuid(of displayID: CGDirectDisplayID) -> String? {
        guard let u = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, u) as String
    }

    static func all() -> [DisplayInfo] {
        NSScreen.screens.compactMap { screen in
            guard let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = CGDirectDisplayID(n.uint32Value)
            guard let u = uuid(of: id) else { return nil }
            return DisplayInfo(id: u, name: screen.localizedName, displayID: id)
        }
    }

    static func builtinUUID() -> String? {
        all().first { CGDisplayIsBuiltin($0.displayID) != 0 }?.id
    }

    /// Union of all active displays, in global (top-left origin) coordinates.
    static func desktopBounds() -> CGRect {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids.prefix(Int(count)).map(CGDisplayBounds).reduce(CGRect.null) { $0.union($1) }
    }

    /// Screen rectangle the pen maps to for a `Settings.displayUUID` value.
    /// Falls back to the main display if the chosen one is disconnected.
    static func rect(for setting: String) -> CGRect {
        if setting == Settings.allDisplays { return desktopBounds() }
        if let d = all().first(where: { $0.id == setting }) { return CGDisplayBounds(d.displayID) }
        return CGDisplayBounds(CGMainDisplayID())
    }
}
