import AppKit
import Foundation

public class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    
    private let networkMonitor = NetworkMonitor()
    private let systemMonitor = SystemMonitor()
    private var timer: Timer?
    /// Serial queue for sampling — keeps all monitor state access off the main thread
    private let sampleQueue = DispatchQueue(label: "com.nanostats.sampling", qos: .utility)
    private var isSamplePending = false
    
    // MARK: - Preferences (UserDefaults)
    
    private var unitMode: UnitMode {
        get {
            if let raw = UserDefaults.standard.string(forKey: "UnitMode"),
               let mode = UnitMode(rawValue: raw) {
                return mode
            }
            return .fixedMB
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "UnitMode")
            updateDisplay()
        }
    }
    
    private var refreshInterval: TimeInterval {
        get {
            let val = UserDefaults.standard.double(forKey: "RefreshInterval")
            return val > 0 ? val : 1.0
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "RefreshInterval")
            restartTimer()
        }
    }
    
    private var selectedInterface: String {
        get {
            return UserDefaults.standard.string(forKey: "SelectedInterface") ?? "auto"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "SelectedInterface")
            resetNetworkSession()
            updateDisplay()
        }
    }
    
    // Metric Visibility & Ordering
    private var enabledMetrics: [MetricType] {
        get {
            if let rawList = UserDefaults.standard.array(forKey: "EnabledMetrics") as? [String] {
                let parsed = rawList.compactMap { MetricType(rawValue: $0) }
                if !parsed.isEmpty { return parsed }
            }
            return MetricType.allCases
        }
        set {
            let rawList = newValue.map { $0.rawValue }
            UserDefaults.standard.set(rawList, forKey: "EnabledMetrics")
            updateDisplay()
        }
    }
    
    private var metricOrder: [MetricType] {
        get {
            if let rawList = UserDefaults.standard.array(forKey: "MetricOrder") as? [String] {
                let parsed = rawList.compactMap { MetricType(rawValue: $0) }
                if !parsed.isEmpty { return parsed }
            }
            return MetricType.allCases
        }
        set {
            let rawList = newValue.map { $0.rawValue }
            UserDefaults.standard.set(rawList, forKey: "MetricOrder")
            updateDisplay()
        }
    }
    
    // Filtered list of metrics currently displayed in order
    private var activeOrderedMetrics: [MetricType] {
        let enabledSet = Set(enabledMetrics)
        var ordered = metricOrder.filter { enabledSet.contains($0) }
        for m in MetricType.allCases where enabledSet.contains(m) && !ordered.contains(m) {
            ordered.append(m)
        }
        return ordered
    }
    
    // Menu items for Overview
    private var headerItem: NSMenuItem!
    private var sessionDownloadItem: NSMenuItem!
    private var sessionUploadItem: NSMenuItem!
    private var ipAddressItem: NSMenuItem!

    private var reorderPanel: ReorderPanel?
    private var lastRenderedKey: String = ""
    
    public override init() {
        super.init()
        setupStatusItem()
        setupMenu()
        startTimer()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = IconProvider.mainAppIcon
            button.imagePosition = .imageLeft
        }
    }
    
    private func setupMenu() {
        menu = NSMenu(title: "NanoStats")
        menu.delegate = self
        
        // --- Overview Section ---
        headerItem = NSMenuItem(title: "NanoStats Monitor", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        
        ipAddressItem = NSMenuItem(title: "IP Address: Checking...", action: nil, keyEquivalent: "")
        ipAddressItem.isEnabled = false
        menu.addItem(ipAddressItem)
        
        sessionDownloadItem = NSMenuItem(title: "Session Downloaded: 0 B", action: nil, keyEquivalent: "")
        sessionDownloadItem.isEnabled = false
        menu.addItem(sessionDownloadItem)
        
        sessionUploadItem = NSMenuItem(title: "Session Uploaded: 0 B", action: nil, keyEquivalent: "")
        sessionUploadItem.isEnabled = false
        menu.addItem(sessionUploadItem)
        

        let resetItem = NSMenuItem(title: "Reset Session Totals", action: #selector(onResetSession), keyEquivalent: "r")
        resetItem.target = self
        menu.addItem(resetItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // --- Submenus ---
        
        // Customize Metrics (opens drag-and-drop panel)
        let customizeItem = NSMenuItem(title: "Customize Metrics...", action: #selector(onOpenReorderPanel), keyEquivalent: "")
        customizeItem.target = self
        menu.addItem(customizeItem)
        
        // Network Interface Selection Submenu
        let interfaceMenu = NSMenu(title: "Network Interface")
        let interfaceSubmenuItem = NSMenuItem(title: "Network Interface", action: nil, keyEquivalent: "")
        interfaceSubmenuItem.submenu = interfaceMenu
        menu.addItem(interfaceSubmenuItem)
        
        // Speed Units Submenu
        let unitsMenu = NSMenu(title: "Speed Units")
        for mode in UnitMode.allCases {
            let item = NSMenuItem(title: mode.rawValue, action: #selector(onSelectUnitMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            unitsMenu.addItem(item)
        }
        let unitsSubmenuItem = NSMenuItem(title: "Speed Units", action: nil, keyEquivalent: "")
        unitsSubmenuItem.submenu = unitsMenu
        menu.addItem(unitsSubmenuItem)
        
        // Refresh Rate Submenu
        let refreshMenu = NSMenu(title: "Refresh Interval")
        let intervals: [(String, TimeInterval)] = [
            ("0.5 seconds", 0.5),
            ("1.0 second", 1.0),
            ("2.0 seconds", 2.0),
            ("5.0 seconds", 5.0)
        ]
        for (label, val) in intervals {
            let item = NSMenuItem(title: label, action: #selector(onSelectRefreshInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = val
            refreshMenu.addItem(item)
        }
        let refreshSubmenuItem = NSMenuItem(title: "Refresh Interval", action: nil, keyEquivalent: "")
        refreshSubmenuItem.submenu = refreshMenu
        menu.addItem(refreshSubmenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // --- System & Preferences ---
        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(onToggleLaunchAtLogin(_:)), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(launchItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit NanoStats", action: #selector(onQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    // MARK: - Menu Delegate & Dynamic Items
    
    public func menuWillOpen(_ menu: NSMenu) {
        // Single getifaddrs pass reused for both the IP display and the interface submenu
        let activeInterfaces = networkMonitor.getActiveInterfaces()
        updateInterfaceSubmenu(activeInterfaces)
        updateCheckmarks()
        
        let primaryIp = activeInterfaces.first(where: { $0.ipAddress != nil })?.ipAddress ?? "Offline"
        ipAddressItem.title = "IP Address: \(primaryIp)"
    }
    
    private func updateInterfaceSubmenu(_ activeInterfaces: [NetworkInterfaceInfo]) {
        guard let interfaceItem = menu.item(withTitle: "Network Interface"),
              let subMenu = interfaceItem.submenu else { return }
        
        subMenu.removeAllItems()
        
        let autoItem = NSMenuItem(title: "Auto (All Interfaces)", action: #selector(onSelectInterface(_:)), keyEquivalent: "")
        autoItem.target = self
        autoItem.representedObject = "auto"
        autoItem.state = (selectedInterface == "auto") ? .on : .off
        subMenu.addItem(autoItem)
        subMenu.addItem(NSMenuItem.separator())
        
        for info in activeInterfaces {
            let title = info.ipAddress != nil ? "\(info.name) (\(info.ipAddress!))" : info.name
            let item = NSMenuItem(title: title, action: #selector(onSelectInterface(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = info.name
            item.state = (selectedInterface == info.name) ? .on : .off
            subMenu.addItem(item)
        }
    }
    
    private func updateCheckmarks() {
        // Speed Units
        if let unitsMenu = menu.item(withTitle: "Speed Units")?.submenu {
            for item in unitsMenu.items {
                if let raw = item.representedObject as? String {
                    item.state = (raw == unitMode.rawValue) ? .on : .off
                }
            }
        }
        
        // Refresh Interval
        if let refreshMenu = menu.item(withTitle: "Refresh Interval")?.submenu {
            for item in refreshMenu.items {
                if let val = item.representedObject as? TimeInterval {
                    item.state = (val == refreshInterval) ? .on : .off
                }
            }
        }
        
        // Launch at Login
        if let launchItem = menu.items.first(where: { $0.title == "Launch at Login" }) {
            launchItem.state = LaunchAtLogin.isEnabled ? .on : .off
        }
    }
    
    // MARK: - Timer & Polling Loop
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.updateDisplay()
        }
        RunLoop.current.add(timer!, forMode: .common)
    }
    
    private func restartTimer() {
        timer?.invalidate()
        startTimer()
    }
    
    /// Serializes session resets with the sampling queue to avoid races with poll()
    private func resetNetworkSession() {
        sampleQueue.sync {
            networkMonitor.resetSession()
        }
    }
    
    private func updateDisplay() {
        // Coalesce: skip if a sample is already queued/running
        guard !isSamplePending else { return }
        isSamplePending = true
        
        sampleQueue.async { [weak self] in
            guard let self = self else { return }
            
            let netSample = self.networkMonitor.poll(selectedInterface: self.selectedInterface)
            let sysSample = self.systemMonitor.poll()
            
            let downStr = SpeedFormatter.formatSpeed(netSample.downloadSpeedBytesPerSec, unitMode: self.unitMode)
            let upStr = SpeedFormatter.formatSpeed(netSample.uploadSpeedBytesPerSec, unitMode: self.unitMode)
            
            let activeMetrics = self.activeOrderedMetrics
            let activeKeys = activeMetrics.map { $0.rawValue }.joined(separator: ",")
            
            let renderKey = "\(downStr)_\(upStr)_\(sysSample.cpuPercent)_\(sysSample.gpuPercent)_\(sysSample.memoryPercent)_\(sysSample.temperatureCelsius)_\(activeKeys)"
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.isSamplePending = false
                guard let button = self.statusItem.button else { return }
                
                if renderKey != self.lastRenderedKey {
                    self.lastRenderedKey = renderKey
                    
                    button.image = IconProvider.renderMetricsImage(
                        enabledMetrics: activeMetrics,
                        upStr: upStr,
                        downStr: downStr,
                        cpuPercent: sysSample.cpuPercent,
                        gpuPercent: sysSample.gpuPercent,
                        memPercent: sysSample.memoryPercent,
                        tempCelsius: sysSample.temperatureCelsius
                    )
                    button.attributedTitle = NSAttributedString(string: "")
                }
                
                self.headerItem.title = "Interface: \(netSample.activeInterfaceName)"
                self.sessionDownloadItem.title = "Session Downloaded: \(SpeedFormatter.formatDataSize(netSample.sessionDownloadedBytes))"
                self.sessionUploadItem.title = "Session Uploaded: \(SpeedFormatter.formatDataSize(netSample.sessionUploadedBytes))"
            }
        }
    }
    
    // MARK: - Action Handlers
    
    @objc private func onOpenReorderPanel() {
        if reorderPanel == nil {
            reorderPanel = ReorderPanel()
            reorderPanel?.onOrderChanged = { [weak self] newOrder, newEnabled in
                guard let self = self else { return }
                let rawOrder = newOrder.map { $0.rawValue }
                UserDefaults.standard.set(rawOrder, forKey: "MetricOrder")
                let rawEnabled = Array(newEnabled).map { $0.rawValue }
                UserDefaults.standard.set(rawEnabled, forKey: "EnabledMetrics")
                self.lastRenderedKey = ""
                self.updateDisplay()
            }
        }
        reorderPanel?.show(orderedMetrics: metricOrder, enabledMetrics: Set(enabledMetrics))
    }
    
    @objc private func onResetSession() {
        resetNetworkSession()
        updateDisplay()
    }
    
    @objc private func onSelectUnitMode(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let mode = UnitMode(rawValue: raw) {
            unitMode = mode
        }
    }
    
    @objc private func onSelectRefreshInterval(_ sender: NSMenuItem) {
        if let val = sender.representedObject as? TimeInterval {
            refreshInterval = val
        }
    }
    
    @objc private func onSelectInterface(_ sender: NSMenuItem) {
        if let ifName = sender.representedObject as? String {
            selectedInterface = ifName
        }
    }
    
    @objc private func onToggleLaunchAtLogin(_ sender: NSMenuItem) {
        let currentState = LaunchAtLogin.isEnabled
        LaunchAtLogin.setEnabled(!currentState)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            sender.state = LaunchAtLogin.isEnabled ? .on : .off
        }
    }
    
    @objc private func onQuit() {
        NSApplication.shared.terminate(nil)
    }
}
