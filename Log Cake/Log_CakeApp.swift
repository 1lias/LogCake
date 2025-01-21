import SwiftUI
import AppKit

struct TimeEntry: Codable {
    let category: String
    let startTime: Date
    let endTime: Date
}

// Add a new structure to store the current tracking state
struct CurrentTrackingState: Codable {
    let category: String
    let startTime: Date
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
    // Power notification observer
    var powerNotificationObserver: NSObjectProtocol?
    
    var statusItem: NSStatusItem!
    var timer: Timer?
    var currentCategory: String?
    var startTime: Date?
    var timeEntries: [TimeEntry] = []
    var dayBoundaryTimer: Timer?
    var currentDay: Date?
    
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
        // Set up sleep notification observer
        powerNotificationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("Computer going to sleep - stopping time tracking")
            self?.handleSleep()
        }
        
        loadTimeEntriesFromFile()
        loadCurrentTrackingState() // Load any ongoing tracking session
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "dot.square", accessibilityDescription: "Dot Square")
        }
        
        setupMenu()
        
        // Set up auto-save timer (every minute)
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.saveCurrentProgress(openFile: false)
            self?.saveCurrentTrackingState() // Save current tracking state
        }
        
        // If we loaded an active tracking session, start the timer
        if currentCategory != nil && startTime != nil {
            startLiveUpdates()
            updateStatusBarIcon()
        }
    }

    // Handle computer sleep
    func handleSleep() {
        if currentCategory != nil {
            stopTracking()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Remove the observer when the app terminates
        if let observer = powerNotificationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        
        saveTimeEntriesToFile()
        saveCurrentTrackingState()
    }

    func saveTimeEntriesToFile() {
        exportEntries(timeEntries, openFile: false, asJSON: true)
    }

    func loadTimeEntriesFromFile() {
        if let containerURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = containerURL.appendingPathComponent("timeEntries.json")
            if let data = try? Data(contentsOf: fileURL) {
                let decoder = JSONDecoder()
                if let loadedEntries = try? decoder.decode([TimeEntry].self, from: data) {
                    timeEntries = loadedEntries
                }
            }
        }
    }

    // New method to save current tracking state
    func saveCurrentTrackingState() {
        guard let currentCategory = currentCategory,
              let startTime = startTime else {
            // If there's no active tracking, remove the state file
            if let containerURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let stateURL = containerURL.appendingPathComponent("currentTracking.json")
                try? FileManager.default.removeItem(at: stateURL)
            }
            return
        }
        
        let currentState = CurrentTrackingState(category: currentCategory, startTime: startTime)
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(currentState),
           let containerURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let stateURL = containerURL.appendingPathComponent("currentTracking.json")
            try? data.write(to: stateURL)
        }
    }
    
    // New method to load current tracking state
    func loadCurrentTrackingState() {
        guard let containerURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        
        let stateURL = containerURL.appendingPathComponent("currentTracking.json")
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(CurrentTrackingState.self, from: data) else {
            return
        }
        
        // Only restore the state if it's from the same calendar day
        let calendar = Calendar.current
        if calendar.isDate(state.startTime, inSameDayAs: Date()) {
            currentCategory = state.category
            startTime = state.startTime
            print("Restored tracking session: \(state.category) from \(state.startTime)")
        } else {
            // If it's a different day, clean up the state file
            try? FileManager.default.removeItem(at: stateURL)
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
        updateStatusBarIcon()
        setupMenu()
        
        // Clear the tracking state file
        saveCurrentTrackingState()
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
    
    func setupDayBoundaryCheck() {
        // Store current day
        currentDay = Calendar.current.startOfDay(for: Date())
        
        // Schedule timer to check for day changes every minute
        dayBoundaryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkDayBoundary()
        }
        RunLoop.main.add(dayBoundaryTimer!, forMode: .common)
    }

    func checkDayBoundary() {
        guard let currentDay = currentDay else { return }
        
        let now = Date()
        let startOfToday = Calendar.current.startOfDay(for: now)
        
        // Check if we've crossed into a new day
        if startOfToday > currentDay {
            handleDayChange(previousDay: currentDay, newDay: startOfToday)
        }
    }

    func handleDayChange(previousDay: Date, newDay: Date) {
        print("Day changed from \(previousDay) to \(newDay)")
        
        // Export previous day's entries
        let previousDayEntries = timeEntries.filter { entry in
            Calendar.current.isDate(entry.startTime, inSameDayAs: previousDay)
        }
        
        // Export the summary for the previous day
        exportEntries(previousDayEntries, openFile: false, asJSON: false)
        
        // Remove previous day's entries
        timeEntries.removeAll { entry in
            Calendar.current.isDate(entry.startTime, inSameDayAs: previousDay)
        }
        
        // Update current day
        self.currentDay = newDay
        
        // If currently tracking, stop and start a new session
        if let category = currentCategory {
            stopTracking()
            
            // Start a new tracking session
            currentCategory = category
            startTime = Date()
            updateStatusBarIcon()
            startLiveUpdates()
            setupMenu()
            
            print("Restarted tracking for new day: \(category)")
        }
        
        // Save the cleaned up state
        saveTimeEntriesToFile()
    }
    
    func saveCurrentProgress(openFile: Bool) {
        var entriesToExport = timeEntries
        
        if let currentCategory = currentCategory, let startTime = startTime {
            entriesToExport.append(TimeEntry(category: currentCategory, startTime: startTime, endTime: Date()))
        }
        
        exportEntries(entriesToExport, openFile: openFile)
    }
    
    func exportEntries(_ entries: [TimeEntry], openFile: Bool, asJSON: Bool = false) {
        if asJSON {
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(entries) {
                if let containerURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    let fileURL = containerURL.appendingPathComponent("timeEntries.json")
                    do {
                        try data.write(to: fileURL)
                        if openFile {
                            NSWorkspace.shared.open(fileURL)
                        }
                        print("Saved entries to: \(fileURL.path)")
                    } catch {
                        print("Failed to save entries: \(error)")
                    }
                }
            }
        } else {
            // Existing summary export logic
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
    }
    
    @objc func exportSummary() {
        saveCurrentProgress(openFile: true)
    }
}
