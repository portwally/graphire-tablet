import AppKit
import ServiceManagement
import SwiftUI

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            Log.write("login item \(on ? "register" : "unregister") failed: \(error)")
        }
    }
}

enum Privacy {
    static func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

struct PressureBar: View {
    var value: Double
    var threshold: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule().fill(Color.accentColor).frame(width: max(0, geo.size.width * value))
                Rectangle().fill(Color.red.opacity(0.8)).frame(width: 2)
                    .offset(x: geo.size.width * threshold - 1)
            }
        }
        .frame(width: 180, height: 8)
        .help("Blue: current pen pressure. Red line: where the tip starts clicking.")
    }
}

struct SettingsView: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var state = TabletState.shared
    @State private var displays = Displays.all()
    @State private var openAtLogin = LoginItem.isEnabled

    private var connectionText: String {
        switch state.connection {
        case .searching: return "Not connected"
        case .connected:
            return state.modelName.isEmpty ? "Connected" : state.modelName + (state.modelTested ? "" : " (untested model)")
        case .failed(let msg): return msg
        }
    }

    /// Pressure curve slider runs on a log scale: -1 (soft) ... 0 (linear) ... +1 (firm).
    private var curveBinding: Binding<Double> {
        Binding(get: { log2(settings.pressureCurve) / 1.5 },
                set: { settings.pressureCurve = pow(2, $0 * 1.5) })
    }

    var body: some View {
        Form {
            Section("Status") {
                LabeledContent("Tablet", value: connectionText)
                if !state.accessibilityGranted {
                    LabeledContent("Permission") {
                        HStack {
                            Text("Accessibility access needed").foregroundStyle(.red)
                            Button("Open Settings…") { Privacy.openAccessibility() }
                        }
                    }
                }
                LabeledContent("Tool", value: state.tool)
                LabeledContent("Pressure") { PressureBar(value: state.pressure, threshold: settings.tipThreshold) }
            }

            Section("Tracking") {
                Picker("Mode", selection: $settings.mode) {
                    ForEach(TrackingMode.allCases) { Text($0.title).tag($0) }
                }
                if settings.mode == .pen {
                    Picker("Screen", selection: $settings.displayUUID) {
                        ForEach(displays) { Text($0.name).tag($0.id) }
                        Text("All Displays").tag(Settings.allDisplays)
                    }
                    Toggle("Force proportions", isOn: $settings.forceProportions)
                        .help("Uses only part of the tablet so circles stay round.")
                } else {
                    Slider(value: $settings.mouseSpeed, in: 0.25...4) {
                        Text("Speed")
                    } minimumValueLabel: { Text("Slow") } maximumValueLabel: { Text("Fast") }
                }
                Toggle("Left-handed (rotate tablet 180°)", isOn: $settings.leftHanded)
                Slider(value: $settings.smoothing, in: 0...0.8) {
                    Text("Smoothing")
                } minimumValueLabel: { Text("Off") } maximumValueLabel: { Text("Max") }
            }

            Section("Pen") {
                Slider(value: $settings.tipThreshold, in: 0...0.4) {
                    Text("Tip feel")
                } minimumValueLabel: { Text("Soft") } maximumValueLabel: { Text("Firm") }
                Slider(value: curveBinding, in: -1...1) {
                    Text("Pressure curve")
                } minimumValueLabel: { Text("Soft") } maximumValueLabel: { Text("Firm") }
            }

            Section("Side Switch") {
                Picker("Upper button", selection: $settings.upperButton) {
                    ForEach(ButtonAction.allCases) { Text($0.title).tag($0) }
                }
                Picker("Lower button", selection: $settings.lowerButton) {
                    ForEach(ButtonAction.allCases) { Text($0.title).tag($0) }
                }
            }

            if state.hasPad {
                Section("Tablet Buttons") {
                    Picker("Left button", selection: $settings.padBackButton) {
                        ForEach(PadAction.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Right button", selection: $settings.padForwardButton) {
                        ForEach(PadAction.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Wheel", selection: $settings.padWheel) {
                        ForEach(PadWheelAction.allCases) { Text($0.title).tag($0) }
                    }
                }
            }

            Section("General") {
                Toggle("Open at login", isOn: Binding(
                    get: { openAtLogin },
                    set: { LoginItem.set($0); openAtLogin = LoginItem.isEnabled }))
                HStack {
                    Spacer()
                    Button("Restore Defaults") { settings.resetToDefaults() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            displays = Displays.all()
        }
        .onAppear { openAtLogin = LoginItem.isEnabled }
    }
}
