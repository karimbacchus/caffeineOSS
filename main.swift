import Cocoa
import IOKit.pwr_mgt
import ServiceManagement

// CaffeineOSS — a tiny menu-bar "keep awake" app.
//
// Click the cup to toggle. Right-click (or ⌃-click) for timers and options.
//
// While active it holds the same IOKit power assertions as `caffeinate -dims`, in-process,
// so the kernel drops them automatically if the app quits or crashes. Optionally it also runs
// `pmset -a disablesleep 1` (one admin prompt) so the Mac stays awake with the lid closed.
// That setting is persistent, so it is undone on toggle-off, timer expiry, quit, and — if the
// app ever died without cleaning up — on the next launch.

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let defaults = UserDefaults.standard

    private var assertions: [IOPMAssertionID] = []     // system / idle / disk sleep
    private var displayAssertion: IOPMAssertionID?      // dropped while the lid is shut
    private var expiry: Date?
    private var expiryTimer: Timer?

    private var isActive: Bool { !assertions.isEmpty }

    /// User preference: also defeat lid-close (clamshell) sleep. Needs admin.
    private var lidMode: Bool {
        get { defaults.object(forKey: "lidMode") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "lidMode") }
    }

    /// Persisted so a crash never leaves `disablesleep` stuck on.
    private var lidSleepDisabled: Bool {
        get { defaults.bool(forKey: "lidSleepDisabled") }
        set { defaults.set(newValue, forKey: "lidSleepDisabled") }
    }

    private static let durations: [(String, TimeInterval)] = [
        ("15 Minutes", 15 * 60), ("30 Minutes", 30 * 60), ("1 Hour", 3600),
        ("2 Hours", 2 * 3600), ("5 Hours", 5 * 3600), ("8 Hours", 8 * 3600),
    ]

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Recover from a previous crash that left lid-sleep disabled.
        if lidSleepDisabled { setLidSleep(disabled: false) }

        watchLid()
        menu.delegate = self
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        deactivate()
    }

    // MARK: Actions

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            statusItem.menu = menu          // attach just long enough to pop it up
            statusItem.button?.performClick(nil)
        } else {
            toggle()
        }
    }

    @objc private func toggle() {
        isActive ? deactivate() : activate(for: nil)
    }

    @objc private func activateForDuration(_ sender: NSMenuItem) {
        activate(for: sender.representedObject as? TimeInterval)
    }

    @objc private func toggleLidMode() {
        lidMode.toggle()
        if isActive { setLidSleep(disabled: lidMode) }
        refresh()
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn’t change Open at Login"
            alert.runModal()
        }
    }

    // MARK: Core

    private func activate(for duration: TimeInterval?) {
        if !isActive {
            assertions = [
                kIOPMAssertPreventUserIdleSystemSleep,
                kIOPMAssertionTypePreventSystemSleep,
                kIOPMAssertPreventDiskIdle,
            ].compactMap(Self.assert)
            if lidMode { setLidSleep(disabled: true) }
            lidChanged()
        }

        expiryTimer?.invalidate()
        expiry = duration.map { Date(timeIntervalSinceNow: $0) }
        if let duration {
            expiryTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.deactivate() }
            }
        }
        refresh()
    }

    private func deactivate() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        expiry = nil
        (assertions + [displayAssertion].compactMap { $0 }).forEach { IOPMAssertionRelease($0) }
        assertions.removeAll()
        displayAssertion = nil
        if lidSleepDisabled { setLidSleep(disabled: false) }
        refresh()
    }

    private static func assert(_ type: String) -> IOPMAssertionID? {
        var id = IOPMAssertionID(0)
        let ok = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                             "CaffeineOSS is keeping your Mac awake" as CFString, &id)
        return ok == kIOReturnSuccess ? id : nil
    }

    // MARK: Lid

    /// Keeps the display on while the lid is open; lets it turn off while the lid is shut
    /// (no point lighting a closed screen). Skipped with an external display, where the
    /// user is working in clamshell mode and wants their monitor kept awake.
    private func lidChanged() {
        guard isActive else { return }
        if Self.lidClosed && !Self.hasExternalDisplay {
            guard let id = displayAssertion else { return }
            IOPMAssertionRelease(id)
            displayAssertion = nil
            Self.run("/usr/bin/pmset", "displaysleepnow")
        } else if displayAssertion == nil {
            var wake = IOPMAssertionID(0)
            IOPMAssertionDeclareUserActivity("CaffeineOSS lid opened" as CFString, kIOPMUserActiveLocal, &wake)
            displayAssertion = Self.assert(kIOPMAssertPreventUserIdleDisplaySleep)
        }
    }

    /// Subscribes to the power-management root domain's clamshell open/close messages.
    private func watchLid() {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        defer { IOObjectRelease(root) }
        IONotificationPortSetDispatchQueue(port, .main)
        var notifier = io_object_t(0)
        IOServiceAddInterestNotification(port, root, "IOGeneralInterest", { refcon, _, message, _ in
            guard message == 0xE003_4100, let refcon else { return } // kIOPMMessageClamshellStateChange
            MainActor.assumeIsolated {
                Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue().lidChanged()
            }
        }, Unmanaged.passUnretained(self).toOpaque(), &notifier)
    }

    private static var lidClosed: Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        defer { IOObjectRelease(root) }
        return IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Bool ?? false
    }

    private static var hasExternalDisplay: Bool {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16), count: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &count)
        return ids.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) == 0 }
    }

    @discardableResult
    private static func run(_ path: String, _ args: String...) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    // MARK: Root

    /// Runs `pmset -a disablesleep <0|1>` as root.
    ///
    /// The first time, this shows the admin prompt and also installs a sudoers rule that lets
    /// this user run exactly those two pmset commands without a password — so every later
    /// toggle is silent. Remove it any time with `sudo rm /etc/sudoers.d/caffeineoss`.
    private func setLidSleep(disabled: Bool) {
        guard disabled != lidSleepDisabled else { return }
        let pmset = "/usr/bin/pmset -a disablesleep \(disabled ? 1 : 0)"

        // Fast path: sudoers rule already installed → no prompt.
        if Self.run("/usr/bin/sudo", "-n", "/usr/bin/pmset", "-a", "disablesleep", disabled ? "1" : "0") {
            lidSleepDisabled = disabled
            return
        }

        // One-time: admin prompt that installs the rule (validated by visudo) and runs pmset.
        let rule = "\(NSUserName()) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"
        let shell = """
            f=$(/usr/bin/mktemp) && echo '\(rule)' > "$f" && /usr/sbin/visudo -cqf "$f" && \
            /usr/bin/install -m 0440 -o root -g wheel "$f" /etc/sudoers.d/caffeineoss; /bin/rm -f "$f"; \(pmset)
            """
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var error: NSDictionary?
        NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")?.executeAndReturnError(&error)
        if error == nil { lidSleepDisabled = disabled }
    }

    // MARK: UI

    private func refresh() {
        guard let button = statusItem.button else { return }
        let symbol = isActive ? "cup.and.saucer.fill" : "cup.and.saucer"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: statusText)
        button.toolTip = "\(statusText)\nClick to toggle · Right-click for options"
    }

    private var statusText: String {
        guard isActive else { return "Sleep allowed" }
        let lid = lidSleepDisabled ? ", even with lid closed" : ""
        if let expiry {
            return "Awake until \(expiry.formatted(date: .omitted, time: .shortened))\(lid)"
        }
        return "Awake indefinitely\(lid)"
    }

    /// Rebuilt each time it opens so the status line and checkmarks are always current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        item(in: menu, isActive ? "Allow Sleep" : "Keep Awake", #selector(toggle), key: "t")

        let timers = NSMenu()
        for (title, seconds) in Self.durations {
            item(in: timers, title, #selector(activateForDuration(_:))).representedObject = seconds
        }
        let timersItem = menu.addItem(withTitle: "Keep Awake For", action: nil, keyEquivalent: "")
        timersItem.submenu = timers
        menu.addItem(.separator())

        item(in: menu, "Stay Awake with Lid Closed", #selector(toggleLidMode)).state = lidMode ? .on : .off
        item(in: menu, "Open at Login", #selector(toggleLaunchAtLogin)).state =
            SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())

        menu.addItem(withTitle: "Quit CaffeineOSS", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil              // so the next left-click toggles instead of opening the menu
    }

    @discardableResult
    private func item(in menu: NSMenu, _ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu-bar only, no Dock icon
app.run()
