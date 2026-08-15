import Foundation
import ServiceManagement
import AppKit

public class LaunchAtLogin {
    public static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            return UserDefaults.standard.bool(forKey: "LaunchAtLoginFallback")
        }
    }
    
    public static func setEnabled(_ enable: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enable {
                    let status = SMAppService.mainApp.status
                    if status == .requiresApproval {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("[NanoStats] LaunchAtLogin error: \(error)")
                // Open System Settings -> Login Items so user can approve/toggle
                SMAppService.openSystemSettingsLoginItems()
            }
        } else {
            UserDefaults.standard.set(enable, forKey: "LaunchAtLoginFallback")
        }
    }
}
