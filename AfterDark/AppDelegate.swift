import Cocoa
import Carbon.HIToolbox

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var overlayWindow: NSWindow?
    var currentBrightness: Float = 1.0

    // Hotkeys
    private var increaseHotKeyRef: EventHotKeyRef?
    private var decreaseHotKeyRef: EventHotKeyRef?
    private var hotKeyEventHandler: EventHandlerRef?

    // Simple auto-disable (fixed 7 AM)
    private var disableInMorning: Bool = UserDefaults.standard.bool(forKey: "DisableInMorning")
    private let morningHour: Int = 7
    private var autoDisableTimer: Timer?
    private var nextDisableDate: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWakeNotification),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            button.image = NSImage(systemSymbolName: "rays", accessibilityDescription: "AfterDark")?
                .withSymbolConfiguration(config)
            button.image?.isTemplate = true
        }

        setupMenu()
        setupHotkeys()

        if disableInMorning {
            scheduleNextDisable()
            scheduleTimer()
        }
    }

    // MARK: - Menu
    private func setupMenu() {
        let menu = NSMenu()

        // Brightness header (native label)
        menu.addItem(NSMenuItem(title: "Brightness", action: nil, keyEquivalent: ""))

        // Brightness slider directly
        let sliderItem = NSMenuItem()
        let slider = NSSlider(value: Double(currentBrightness),
                                minValue: 0.1,
                                maxValue: 1.0,
                                target: self,
                                action: #selector(brightnessChanged(_:)))
        slider.isContinuous = true
        
        // Set slider appearance to grey
        slider.trackFillColor = NSColor.systemGray
        slider.appearance = NSAppearance(named: .aqua) // Force light appearance for consistent grey

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 40))
        slider.frame = NSRect(x: 20, y: 10, width: 180, height: 20) // 12pt padding left/right
        container.addSubview(slider)

        sliderItem.view = container
        menu.addItem(sliderItem)

        menu.addItem(NSMenuItem.separator())

        // Disable in Morning toggle
        let disableItem = NSMenuItem(title: "Disable in Morning",
                                     action: #selector(toggleDisableInMorning),
                                     keyEquivalent: "")
        disableItem.state = disableInMorning ? .on : .off
        disableItem.target = self
        menu.addItem(disableItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit AfterDark", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    @objc private func toggleDisableInMorning(_ sender: NSMenuItem) {
        disableInMorning.toggle()
        sender.state = disableInMorning ? .on : .off
        UserDefaults.standard.set(disableInMorning, forKey: "DisableInMorning")

        if disableInMorning {
            scheduleNextDisable()
            scheduleTimer()
        } else {
            autoDisableTimer?.invalidate(); autoDisableTimer = nil
            nextDisableDate = nil
        }
    }

    // MARK: - Brightness & Overlay
    @objc private func brightnessChanged(_ slider: NSSlider) {
        setBrightness(Float(slider.doubleValue))
    }

    func setBrightness(_ level: Float) {
        currentBrightness = max(0.1, min(1.0, level))
        updateOverlay()

        // Update slider value when changed programmatically (hotkeys)
        if let menu = statusItem.menu,
           let slider = menu.items.compactMap({ $0.view?.subviews.first as? NSSlider }).first {
            slider.doubleValue = Double(currentBrightness)
        }
    }

    private func adjustBrightness(by delta: Float) {
        setBrightness(currentBrightness + delta)
    }

    func updateOverlay() {
        if currentBrightness >= 0.99 { disableOverlay() }
        else { enableOverlay() }
    }

    func enableOverlay() {
        if overlayWindow == nil, let screen = NSScreen.main {
            overlayWindow = NSWindow(contentRect: screen.frame,
                                      styleMask: .borderless,
                                      backing: .buffered,
                                      defer: false)
            overlayWindow?.level = .screenSaver
            overlayWindow?.ignoresMouseEvents = true
            overlayWindow?.isOpaque = false
            overlayWindow?.backgroundColor = .black
            overlayWindow?.alphaValue = 0
            overlayWindow?.makeKeyAndOrderFront(nil)
            overlayWindow?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        }
        let alpha = CGFloat(1 - currentBrightness)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            overlayWindow?.animator().alphaValue = alpha
        }
    }

    func disableOverlay() { overlayWindow?.orderOut(nil); overlayWindow = nil }

    // MARK: - Auto Disable (simple 7 AM)
    private func scheduleTimer() {
        autoDisableTimer?.invalidate()
        autoDisableTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkAutoDisable()
        }
    }

    private func scheduleNextDisable() {
        let now = Date()
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: now)
        comps.hour = morningHour
        comps.minute = 0
        comps.second = 0
        if let today = Calendar.current.date(from: comps) {
            if now < today {
                nextDisableDate = today
            } else {
                nextDisableDate = Calendar.current.date(byAdding: .day, value: 1, to: today)
            }
            print("📅 Next disable at: \(nextDisableDate!)")
        }
    }

    private func checkAutoDisable() {
        guard disableInMorning, let fire = nextDisableDate else { return }
        if Date() >= fire {
            setBrightness(1.0)
            disableOverlay()
            print("🌅 Auto-disabled at \(Date())")
            scheduleNextDisable()
        }
    }

    @objc private func handleWakeNotification(_ note: Notification) {
        checkAutoDisable()
    }

    // MARK: - Hotkeys
    private func setupHotkeys() {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { (_, ev, _) -> OSStatus in
            var id = EventHotKeyID()
            GetEventParameter(ev, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            if let app = NSApp.delegate as? AppDelegate {
                switch id.id {
                case 1: app.adjustBrightness(by: -0.1)
                case 2: app.adjustBrightness(by: +0.1)
                default: break
                }
            }
            return noErr
        }, 1, &eventSpec, nil, &hotKeyEventHandler)

        let id1 = EventHotKeyID(signature: OSType(0x41464452), id: 1)
        RegisterEventHotKey(UInt32(kVK_F1), 0, id1, GetEventDispatcherTarget(), 0, &decreaseHotKeyRef)
        let id2 = EventHotKeyID(signature: OSType(0x41464452), id: 2)
        RegisterEventHotKey(UInt32(kVK_F2), 0, id2, GetEventDispatcherTarget(), 0, &increaseHotKeyRef)
    }

    // MARK: - Quit
    @objc func quit() { NSApplication.shared.terminate(nil) }
}
