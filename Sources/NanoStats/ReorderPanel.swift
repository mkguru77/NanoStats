import AppKit

private let kMetricDragType = NSPasteboard.PasteboardType("com.nanostats.metricRow")

/// A small floating panel with a drag-and-drop reorderable NSTableView for metrics.
public class ReorderPanel: NSPanel, NSTableViewDataSource, NSTableViewDelegate {
    
    private var tableView: NSTableView!
    private var scrollView: NSScrollView!
    private var orderedMetrics: [MetricType] = []
    private var enabledSet: Set<MetricType> = []
    
    /// Called when the user changes order or toggles a metric.
    public var onOrderChanged: (([MetricType], Set<MetricType>) -> Void)?
    
    public init() {
        super.init(
            contentRect: NSMakeRect(0, 0, 280, 230),
            styleMask: [.titled, .closable, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )
        
        self.title = "Reorder Metrics"
        self.isFloatingPanel = true
        self.becomesKeyOnlyIfNeeded = false
        self.level = .floating
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = false
        
        setupTableView()
    }
    
    private func setupTableView() {
        tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = 32
        tableView.intercellSpacing = NSMakeSize(0, 2)
        tableView.selectionHighlightStyle = .none
        tableView.style = .plain
        tableView.usesAlternatingRowBackgroundColors = true
        
        // Enable column
        let checkCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("check"))
        checkCol.width = 30
        checkCol.minWidth = 30
        checkCol.maxWidth = 30
        tableView.addTableColumn(checkCol)
        
        // Name column
        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameCol.width = 220
        tableView.addTableColumn(nameCol)
        
        tableView.dataSource = self
        tableView.delegate = self
        
        tableView.registerForDraggedTypes([kMetricDragType])
        tableView.draggingDestinationFeedbackStyle = .gap
        
        scrollView = NSScrollView(frame: NSMakeRect(0, 0, 280, 200))
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]
        
        let container = NSView(frame: NSMakeRect(0, 0, 280, 230))
        
        let label = NSTextField(labelWithString: "Drag to reorder · Click ✓ to toggle")
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.frame = NSMakeRect(0, 205, 280, 20)
        label.autoresizingMask = [.width, .minYMargin]
        container.addSubview(label)
        
        scrollView.frame = NSMakeRect(0, 0, 280, 202)
        container.addSubview(scrollView)
        
        self.contentView = container
    }
    
    public func show(orderedMetrics: [MetricType], enabledMetrics: Set<MetricType>) {
        self.orderedMetrics = orderedMetrics
        self.enabledSet = enabledMetrics
        tableView.reloadData()
        self.center()
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - NSTableViewDataSource
    
    public func numberOfRows(in tableView: NSTableView) -> Int {
        return orderedMetrics.count
    }
    
    // MARK: - NSTableViewDelegate
    
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let metric = orderedMetrics[row]
        
        if tableColumn?.identifier.rawValue == "check" {
            let cell = NSTableCellView()
            let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(onCheckboxToggle(_:)))
            checkbox.state = enabledSet.contains(metric) ? .on : .off
            checkbox.tag = row
            checkbox.frame = NSMakeRect(6, 4, 20, 24)
            cell.addSubview(checkbox)
            return cell
        } else {
            let cell = NSTableCellView()
            let textField = NSTextField(labelWithString: "☰  \(metric.displayName)")
            textField.font = NSFont.systemFont(ofSize: 13, weight: .regular)
            textField.frame = NSMakeRect(4, 4, 200, 24)
            textField.autoresizingMask = [.width]
            cell.textField = textField
            cell.addSubview(textField)
            return cell
        }
    }
    
    @objc private func onCheckboxToggle(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0 && row < orderedMetrics.count else { return }
        let metric = orderedMetrics[row]
        
        if enabledSet.contains(metric) {
            // Don't allow disabling the last metric
            if enabledSet.count > 1 {
                enabledSet.remove(metric)
            } else {
                sender.state = .on
                return
            }
        } else {
            enabledSet.insert(metric)
        }
        
        onOrderChanged?(orderedMetrics, enabledSet)
    }
    
    // MARK: - Drag & Drop
    
    public func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        let item = NSPasteboardItem()
        item.setString(String(row), forType: kMetricDragType)
        return item
    }
    
    public func tableView(_ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        if dropOperation == .above {
            return .move
        }
        return []
    }
    
    public func tableView(_ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let item = info.draggingPasteboard.pasteboardItems?.first,
              let rowStr = item.string(forType: kMetricDragType),
              let sourceRow = Int(rowStr) else { return false }
        
        var targetRow = row
        if sourceRow < targetRow {
            targetRow -= 1
        }
        
        let movedMetric = orderedMetrics.remove(at: sourceRow)
        orderedMetrics.insert(movedMetric, at: targetRow)
        
        tableView.reloadData()
        onOrderChanged?(orderedMetrics, enabledSet)
        return true
    }
}
