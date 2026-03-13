import SwiftUI
import ServiceManagement

enum MenuBarDisplayMode: String, CaseIterable {
    case iconOnly = "Icon Only"
    case iconAndNumber = "Icon + Tokens"
    case iconAndMiniGraph = "Icon + Mini Graph"
}

struct SettingsView: View {
    @AppStorage("logPath") private var logPath = "~/.claude/"
    @AppStorage("displayMode") private var displayMode = MenuBarDisplayMode.iconOnly.rawValue
    @AppStorage("animationEnabled") private var animationEnabled = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        Form {
            Section("Log Path") {
                HStack {
                    TextField("Path", text: $logPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse...") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            logPath = url.path
                        }
                    }
                }
            }
            Section("Menu Bar") {
                Picker("Display", selection: $displayMode) {
                    ForEach(MenuBarDisplayMode.allCases, id: \.rawValue) { mode in
                        Text(mode.rawValue).tag(mode.rawValue)
                    }
                }
                Toggle("Animation", isOn: $animationEnabled)
            }
            Section("General") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !newValue
                        }
                    }
            }
            Section {
                Button("Quit Token Garden") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 320)
        .padding()
    }
}
