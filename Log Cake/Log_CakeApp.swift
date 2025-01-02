import SwiftUI
import AppKit

struct TimeEntry: Codable {
    let category: String
    let startTime: Date
    let endTime: Date
}

@main
struct TimeTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    var currentCategory: String?
    var startTime: Date?
    var timeEntries: [TimeEntry] = []
    
    struct CategoryStyle {
        let name: String
        let color: NSColor
    }
    
    let categories: [CategoryStyle] = [
        CategoryStyle(name: "Work", color: NSColor.systemBlue),
        CategoryStyle(name: "Creative", color: NSColor.systemPurple),
        CategoryStyle(name: "Learning", color: NSColor.systemGreen),
        CategoryStyle(name: "Break", color: NSColor.systemOrange)
    ]
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "dot.square", accessibilityDescription: "Dot Square")
        }
        
        setupMenu()
        
        // Set up auto-save timer (every minute)
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.saveCurrentProgress(openFile: false)
        }
    }
    
    func createCategoryMenuItem(category: CategoryStyle) -> NSMenuItem {
        let item = NSMenuItem(title: category.name, action: #selector(toggleTracking(_:)), keyEquivalent: "")
        item.target = self
        
        // Create the circle indicator
        let circle = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            let circlePath = NSBezierPath(ovalIn: rect)
            category.color.setFill()
            circlePath.fill()
            return true
        }
        
        item.image = circle
        
        if category.name == currentCategory {
            item.state = .on
        }
        
        return item
    }
    
    func setupMenu() {
        let menu = NSMenu()
        
        // Add current tracking info if active
        if let currentCategory = currentCategory, let startTime = startTime {
            let duration = Int(-startTime.timeIntervalSinceNow)
            let hours = duration / 3600
            let minutes = (duration % 3600) / 60
            let seconds = duration % 60
            let timeInfoItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            timeInfoItem.attributedTitle = createMenuTitle("Currently tracking: \(currentCategory)", String(format: "%02d:%02d:%02d", hours, minutes, seconds))
            timeInfoItem.isEnabled = false
            menu.addItem(timeInfoItem)
            
            // Add stop button
            let stopItem = NSMenuItem(title: "Stop Tracking", action: #selector(stopTrackingAction), keyEquivalent: "s")
            stopItem.target = self
            menu.addItem(stopItem)
            
            menu.addItem(NSMenuItem.separator())
        }
        
        // Add category items
        for category in categories {
            menu.addItem(createCategoryMenuItem(category: category))
        }
        
        menu.addItem(NSMenuItem.separator())
        
        let summaryItem = NSMenuItem(title: "Export Daily Summary", action: #selector(exportSummary), keyEquivalent: "e")
        summaryItem.target = self
        menu.addItem(summaryItem)
        
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    @objc func toggleTracking(_ sender: NSMenuItem) {
        if currentCategory != nil {
            stopTracking()
        }
        
        // If selecting the same category, just stop
        if sender.title == currentCategory {
            currentCategory = nil
            updateStatusBarIcon()
            setupMenu() // Refresh menu to update states
            return
        }
        
        // Start tracking new category
        currentCategory = sender.title
        startTime = Date()
        updateStatusBarIcon()
        startLiveUpdates()
        setupMenu() // Refresh menu to update states
    }
    
    @objc func stopTrackingAction() {
        stopTracking()
        setupMenu() // Refresh menu to update states
    }
    
    func updateTimeDisplay() {
        guard let menu = statusItem.menu,
              let currentCategory = currentCategory,
              let startTime = startTime,
              let firstItem = menu.items.first else { return }
        
        let duration = Int(-startTime.timeIntervalSinceNow)
        let hours = duration / 3600
        let minutes = (duration % 3600) / 60
        let seconds = duration % 60
        firstItem.attributedTitle = createMenuTitle("Currently tracking: \(currentCategory)", String(format: "%02d:%02d:%02d", hours, minutes, seconds))
    }
    
    func createMenuTitle(_ prefix: String, _ time: String) -> NSAttributedString {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuBarFont(ofSize: 13),
            .foregroundColor: NSColor.disabledControlTextColor
        ]
        
        let title = NSMutableAttributedString(string: prefix + " ", attributes: titleAttributes)
        let timeAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuBarFont(ofSize: 13),
            .foregroundColor: NSColor.disabledControlTextColor
        ]
        let timeString = NSAttributedString(string: time, attributes: timeAttributes)
        title.append(timeString)
        return title
    }
    
    func startLiveUpdates() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateTimeDisplay()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    
    func stopTracking() {
        guard let category = currentCategory, let start = startTime else { return }
        timeEntries.append(TimeEntry(category: category, startTime: start, endTime: Date()))
        saveCurrentProgress(openFile: false)
        
        currentCategory = nil
        startTime = nil
        timer?.invalidate()
        timer = nil
        updateStatusBarIcon()  // Update the icon state
        setupMenu()  // Refresh the menu
    }
    
    func updateStatusBarIcon() {
        if let button = statusItem.button {
            if let category = currentCategory {
                let config = NSImage.SymbolConfiguration(scale: .medium)
                button.image = NSImage(systemSymbolName: "dot.square.fill", accessibilityDescription: "Dot Square Active")?.withSymbolConfiguration(config)
                button.title = " \(category)"
            } else {
                button.image = NSImage(systemSymbolName: "dot.square", accessibilityDescription: "Dot Square")
                button.title = ""
            }
        }
    }
    
    func saveCurrentProgress(openFile: Bool) {
        var entriesToExport = timeEntries
        
        if let currentCategory = currentCategory, let startTime = startTime {
            entriesToExport.append(TimeEntry(category: currentCategory, startTime: startTime, endTime: Date()))
        }
        
        exportEntries(entriesToExport, openFile: openFile)
    }
    
    func exportEntries(_ entries: [TimeEntry], openFile: Bool) {
        var summary = "Daily Time Tracking Summary\n"
        summary += "=========================\n\n"
        
        let groupedEntries = Dictionary(grouping: entries) { $0.category }
        
        for category in categories {
            let totalSeconds = (groupedEntries[category.name] ?? []).reduce(0) { acc, entry in
                acc + Int(entry.endTime.timeIntervalSince(entry.startTime))
            }
            
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            let seconds = totalSeconds % 60
            
            summary += "\(category.name): \(hours)h \(minutes)m \(seconds)s\n"
        }
        
        if let containerURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let fileName = "time-tracking-\(dateFormatter.string(from: Date())).txt"
            let fileURL = containerURL.appendingPathComponent(fileName)
            
            do {
                try summary.write(to: fileURL, atomically: true, encoding: .utf8)
                if openFile {
                    NSWorkspace.shared.open(fileURL)
                }
                print("Saved summary to: \(fileURL.path)")
            } catch {
                print("Failed to save summary: \(error)")
            }
        }
    }
    
    @objc func exportSummary() {
        saveCurrentProgress(openFile: true)
    }
}
