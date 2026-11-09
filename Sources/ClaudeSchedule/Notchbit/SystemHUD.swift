import AppKit
import CoreAudio
import ApplicationServices
import Carbon.HIToolbox
import IOKit.ps

/// Receives "the keyboard layout changed" even while Orbit is in the background
private final class LayoutObserver: NSObject {
    private let onChange: () -> Void
    init(_ onChange: @escaping () -> Void) {
        self.onChange = onChange
        super.init()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(changed), name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
                                                            object: nil, suspensionBehavior: .deliverImmediately)
    }
    deinit { DistributedNotificationCenter.default().removeObserver(self) }
    @objc private func changed() { DispatchQueue.main.async { [onChange] in onChange() } }
}

/// Watches the Mac's volume and the screen brightness and tells the notch when either changes,
/// so it can show a little level meter (like the system one, but in the notch).
/// Both are event driven: nothing runs while neither changes.
@MainActor
final class SystemHUD {
    static let shared = SystemHUD()
    private var started = false

    // volume
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var lastVolume: Float = -1
    private var lastMute: Bool?
    private var audioBlock: AudioObjectPropertyListenerBlock?
    private var watched: [AudioObjectPropertyAddress] = []
    private var deviceBlock: AudioObjectPropertyListenerBlock?

    // brightness (macOS has no public notification for it; DisplayServices posts one)
    private var screenID = CGMainDisplayID()
    private var lastBrightness: Float = -1
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias RegFn = @convention(c) (CGDirectDisplayID, UnsafeRawPointer?, CFNotificationCallback?) -> Int32
    private typealias UnregFn = @convention(c) (CGDirectDisplayID, UnsafeRawPointer?) -> Int32
    private var getBrightness: GetFn?
    private var unregister: UnregFn?
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private var setBrightness: SetFn?

    // battery
    private var powerSource: CFRunLoopSource?
    private var lastPercent = -1
    private var lastPlugged: Bool?

    // keyboard layout
    private var layoutObserver: LayoutObserver?
    private var previousLayout = ""
    /// While the screen is locked, and for a moment after unlocking or waking, macOS changes the layout by itself: that is not the user switching
    private var screenLocked = false
    private var quietUntil = Date.distantPast
    private var sessionObservers: [NSObjectProtocol] = []
    private var lastLayout = ""
    private var lastLayoutAt = Date.distantPast

    // media keys
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?

    func start() {
        guard !started else { return }
        started = true
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { SystemHUD.shared.syncKeys() }
        }
        watchKeyboardLayout()
        watchBattery()
        watchDefaultDevice()
        attachVolume()
        startBrightness()
        syncKeys(prompt: false)
    }

    func stop() {
        guard started else { return }
        started = false
        stopKeys()
        layoutObserver = nil
        sessionObservers.forEach { DistributedNotificationCenter.default().removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        sessionObservers = []
        if let src = powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .defaultMode); powerSource = nil }
        detachVolume()
        if let block = deviceBlock {
            var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, .main, block)
            deviceBlock = nil
        }
        _ = unregister?(screenID, nil)
    }

    // MARK: Battery
    //
    // Event driven (macOS tells us when the charge or the plug changes). A small meter shows when the charger is plugged in or out,
    // when the battery drops to 20% on battery power, when it reaches 80% while charging, and when it is full.

    private func batteryState() -> (percent: Int, plugged: Bool, charging: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef], let ps = list.first,
              let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any] else { return nil }
        let cap = d[kIOPSCurrentCapacityKey] as? Int ?? 0, full = d[kIOPSMaxCapacityKey] as? Int ?? 100
        let pct = full > 0 ? Int((Double(cap) / Double(full) * 100).rounded()) : cap
        let plugged = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let charging = d[kIOPSIsChargingKey] as? Bool ?? false
        return (pct, plugged, charging)
    }

    private func watchBattery() {
        guard let b = batteryState() else { return }   // a Mac without a battery
        lastPercent = b.percent
        lastPlugged = b.plugged
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let hud = Unmanaged<SystemHUD>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { hud.batteryChanged() }
        }, me)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        powerSource = src
    }

    private func batteryChanged() {
        guard let b = batteryState() else { return }
        defer { lastPercent = b.percent; lastPlugged = b.plugged }
        if let was = lastPlugged, was != b.plugged {
            NotchbitModel.shared.showBattery(percent: b.percent, charging: b.plugged, text: b.plugged ? "Charging" : "On battery")
            return
        }
        guard lastPercent >= 0, lastPercent != b.percent else { return }
        if !b.plugged, lastPercent > 20, b.percent <= 20 {
            NotchbitModel.shared.showBattery(percent: b.percent, charging: false, text: "Low battery")
        } else if b.plugged, lastPercent < 80, b.percent >= 80, b.percent < 100 {
            NotchbitModel.shared.showBattery(percent: b.percent, charging: true, text: "80% charged")
        } else if b.plugged, lastPercent < 100, b.percent >= 100 {
            NotchbitModel.shared.showBattery(percent: 100, charging: true, text: "Fully charged")
        }
    }

    // MARK: Keyboard layout (language)

    private func prop(_ src: TISInputSource, _ key: CFString) -> Any? {
        guard let p = TISGetInputSourceProperty(src, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(p).takeUnretainedValue()
    }

    private func watchKeyboardLayout() {
        lastLayout = currentLayout().id
        func quiet(_ seconds: Double) { quietUntil = Date().addingTimeInterval(seconds) }
        let dc = DistributedNotificationCenter.default(), wc = NSWorkspace.shared.notificationCenter
        sessionObservers = [
            dc.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { SystemHUD.shared.screenLocked = true; NotchbitController.shared.screenLockChanged(true); NotchbitModel.shared.showLock(true) }
            },
            dc.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { SystemHUD.shared.screenLocked = false; SystemHUD.shared.quietUntil = Date().addingTimeInterval(4); NotchbitController.shared.screenLockChanged(false); NotchbitModel.shared.showLock(false) }
            },
            wc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { SystemHUD.shared.quietUntil = Date().addingTimeInterval(5) }
            },
            wc.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { SystemHUD.shared.quietUntil = Date().addingTimeInterval(4) }
            }
        ]
        layoutObserver = LayoutObserver { MainActor.assumeIsolated { SystemHUD.shared.layoutChanged() } }
    }

    private func currentLayout() -> (id: String, code: String, name: String) {
        guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return ("", "", "") }
        let id = prop(src, kTISPropertyInputSourceID) as? String ?? ""
        let name = prop(src, kTISPropertyLocalizedName) as? String ?? id
        let lang = (prop(src, kTISPropertyInputSourceLanguages) as? [String])?.first ?? ""
        let code = String(lang.prefix(2)).uppercased()
        return (id, code.isEmpty ? String(name.prefix(2)).uppercased() : code, name)
    }

    private func layoutChanged() {
        let l = currentLayout()
        if screenLocked || Date() < quietUntil {
            lastLayout = l.id     // note it, but say nothing
            return
        }
        // macOS sends this more than once for a single switch
        guard !l.id.isEmpty, l.id != lastLayout || Date().timeIntervalSince(lastLayoutAt) > 0.6 else { return }
        if l.id == lastLayout { return }
        previousLayout = lastLayout
        lastLayout = l.id
        lastLayoutAt = Date()
        NotchbitModel.shared.showKeyboard(code: l.code, name: l.name)
    }

    /// The shortcuts set in System Settings → Keyboard → Keyboard Shortcuts → Input Sources
    private struct Shortcut { var key: Int64; var mods: UInt64; var next: Bool }
    private var shortcuts: [Shortcut] = []

    private func loadShortcuts() {
        shortcuts = []
        let all = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys") ?? [:]
        for (id, next) in [("60", false), ("61", true)] {
            guard let d = all[id] as? [String: Any], (d["enabled"] as? Bool) ?? ((d["enabled"] as? Int ?? 0) != 0),
                  let v = d["value"] as? [String: Any], let p = v["parameters"] as? [Any], p.count >= 3,
                  let key = (p[1] as? NSNumber)?.int64Value, let mods = (p[2] as? NSNumber)?.uint64Value else { continue }
            shortcuts.append(Shortcut(key: key, mods: mods & 0x1E0000, next: next))
        }
    }

    private func keyboardSources() -> [TISInputSource] {
        let filter = [kTISPropertyInputSourceIsSelectCapable: true, kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource!] as CFDictionary
        return (TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource]) ?? []
    }

    /// Switches the layout ourselves (previous one, or the next in the list) and shows it in the notch
    private func switchLayout(next: Bool) {
        let list = keyboardSources()
        guard list.count > 1 else { return }
        let ids = list.map { prop($0, kTISPropertyInputSourceID) as? String ?? "" }
        let cur = currentLayout().id
        var target = ids.firstIndex(of: next ? "" : previousLayout)
        if target == nil || ids[target!] == cur {
            let i = ids.firstIndex(of: cur) ?? -1
            target = (i + 1) % list.count
        }
        TISSelectInputSource(list[target!])
        previousLayout = cur
        lastLayout = ids[target!]
        lastLayoutAt = Date()
        let l = currentLayout()
        // the switch can take a moment to show up as "current"
        let src = list[target!]
        let name = prop(src, kTISPropertyLocalizedName) as? String ?? l.name
        let lang = (prop(src, kTISPropertyInputSourceLanguages) as? [String])?.first ?? ""
        NotchbitModel.shared.showKeyboard(code: String(lang.prefix(2)).uppercased(), name: name)
    }

    // MARK: Volume

    private func volumeAddress(_ element: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
    }
    /// The volume macOS itself uses (works for every device, including AirPods, which have no plain main volume)
    private func virtualAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: 0x766D7663 /* 'vmvc' */, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }
    private func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }

    private func readFloat(_ dev: AudioObjectID, _ addr: AudioObjectPropertyAddress) -> Float? {
        var a = addr
        guard AudioObjectHasProperty(dev, &a) else { return nil }
        var v = Float32(0), size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &v) == noErr ? v : nil
    }

    private func readVolume() -> Float? {
        if let v = readFloat(device, virtualAddress()) { return v }
        if let v = readFloat(device, volumeAddress(kAudioObjectPropertyElementMain)) { return v }
        let l = readFloat(device, volumeAddress(1)), r = readFloat(device, volumeAddress(2))
        if let l, let r { return (l + r) / 2 }
        return l ?? r
    }

    private func isSettable(_ addr: AudioObjectPropertyAddress) -> Bool {
        var a = addr, settable: DarwinBoolean = false
        guard device != kAudioObjectUnknown, AudioObjectHasProperty(device, &a) else { return false }
        AudioObjectIsPropertySettable(device, &a, &settable)
        return settable.boolValue
    }

    private func setVolume(_ v: Float) {
        var nv = Float32(max(0, min(1, v)))
        let size = UInt32(MemoryLayout<Float32>.size)
        for addr in [virtualAddress(), volumeAddress(kAudioObjectPropertyElementMain)] where isSettable(addr) {
            var a = addr
            AudioObjectSetPropertyData(device, &a, 0, nil, size, &nv)
            return
        }
        for el in [UInt32(1), 2] where isSettable(volumeAddress(el)) {   // left and right separately
            var a = volumeAddress(el)
            AudioObjectSetPropertyData(device, &a, 0, nil, size, &nv)
        }
    }

    private func readMute() -> Bool? {
        var a = muteAddress()
        guard AudioObjectHasProperty(device, &a) else { return nil }
        var v = UInt32(0), size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &a, 0, nil, &size, &v) == noErr ? v != 0 : nil
    }

    private func attachVolume() {
        detachVolume()
        var dev = AudioObjectID(kAudioObjectUnknown), size = UInt32(MemoryLayout<AudioObjectID>.size)
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &dev) == noErr, dev != kAudioObjectUnknown else { return }
        device = dev
        lastVolume = readVolume() ?? -1
        lastMute = readMute()
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.volumeChanged() }
        }
        audioBlock = block
        for var addr in [virtualAddress(), volumeAddress(kAudioObjectPropertyElementMain), volumeAddress(1), volumeAddress(2), muteAddress()] where AudioObjectHasProperty(dev, &addr) {
            if AudioObjectAddPropertyListenerBlock(dev, &addr, .main, block) == noErr { watched.append(addr) }
        }
    }

    private func detachVolume() {
        guard let block = audioBlock else { return }
        for var addr in watched { AudioObjectRemovePropertyListenerBlock(device, &addr, .main, block) }
        watched = []
        audioBlock = nil
    }

    /// When the output changes (headphones in, AirPods…), listen to the new one without showing anything
    private func watchDefaultDevice() {
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.attachVolume() }
        }
        deviceBlock = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, .main, block)
    }

    private func volumeChanged() {
        let v = readVolume(), m = readMute()
        guard let v else { return }
        let moved = abs(v - lastVolume) > 0.001, muteMoved = m != lastMute
        guard moved || muteMoved else { return }
        lastVolume = v; lastMute = m
        NotchbitModel.shared.showHUD(.volume, Double(v), muted: m ?? false)
    }

    // MARK: Brightness

    private func startBrightness() {
        guard let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW) else { return }
        guard let g = dlsym(h, "DisplayServicesGetBrightness"), let r = dlsym(h, "DisplayServicesRegisterForBrightnessChangeNotifications") else { return }
        getBrightness = unsafeBitCast(g, to: GetFn.self)
        if let st = dlsym(h, "DisplayServicesSetBrightness") { setBrightness = unsafeBitCast(st, to: SetFn.self) }
        if let u = dlsym(h, "DisplayServicesUnregisterForBrightnessChangeNotifications") { unregister = unsafeBitCast(u, to: UnregFn.self) }
        var ids = [CGDirectDisplayID](repeating: 0, count: 8), n: UInt32 = 0
        CGGetActiveDisplayList(8, &ids, &n)
        screenID = ids.prefix(Int(n)).first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
        var b: Float = -1
        if getBrightness?(screenID, &b) == 0 { lastBrightness = b }
        let reg = unsafeBitCast(r, to: RegFn.self)
        let cb: CFNotificationCallback = { _, _, _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { SystemHUD.shared.brightnessChanged() } }
        }
        _ = reg(screenID, nil, cb)
    }

    private func brightnessChanged() {
        var b: Float = -1
        guard getBrightness?(screenID, &b) == 0, abs(b - lastBrightness) > 0.001 else { return }
        lastBrightness = b
        // Automatic changes (ambient light, battery saver, night mode) are not shown. With the keys taken over, the key handler shows
        // the level itself, so a change that did not come from a key is ignored here.
        if tap != nil { return }
        NotchbitModel.shared.showHUD(.brightness, Double(b), muted: false)
    }

    // MARK: Taking over the volume / brightness keys
    //
    // macOS draws its own panel when a key is pressed, and there is no way to hide that panel.
    // So, with the user's permission (Accessibility), the notch takes the keys over: it swallows them and changes the level itself.
    // Without the permission, or with the switch off, nothing is touched and macOS works as usual.

    static var trusted: Bool { AXIsProcessTrusted() }

    private var wantsKeys: Bool {
        let d = UserDefaults.standard
        return (d.object(forKey: "notchbit.hud") as? Bool ?? true) && (d.object(forKey: "notchbit.hideOSD") as? Bool ?? false)
    }

    /// Called when a setting may have changed or the app comes to the front
    func syncKeys(prompt: Bool = false) {
        guard started else { return }
        if wantsKeys { startKeys(prompt: prompt) } else { stopKeys() }
    }

    private func startKeys(prompt: Bool) {
        guard tap == nil else { return }
        guard AXIsProcessTrusted() else {
            if prompt { _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) }
            return
        }
        loadShortcuts()
        let mask = CGEventMask((1 << 14) | (1 << 10) | (1 << 11))   // volume / brightness keys, and key presses (for the input-source shortcut)
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
                                        callback: { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let hud = Unmanaged<SystemHUD>.fromOpaque(info).takeUnretainedValue()
            let swallow = MainActor.assumeIsolated { hud.handle(type, event) }
            return swallow ? nil : Unmanaged.passUnretained(event)
        }, userInfo: me) else { return }
        tap = t
        tapSource = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
    }

    private func stopKeys() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let src = tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        tapSource = nil
        tap = nil
    }

    /// true = the key was ours: macOS never sees it (so it shows no panel)
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return false
        }
        let keyboardOn = UserDefaults.standard.object(forKey: "notchbit.hudKeyboard") as? Bool ?? true
        if type == .keyDown || type == .keyUp {
            guard keyboardOn, !shortcuts.isEmpty else { return false }
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            let mods = UInt64(event.flags.rawValue) & 0x1E0000
            guard let sc = shortcuts.first(where: { $0.key == key && $0.mods == mods }) else { return false }
            if type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { switchLayout(next: sc.next) }
            return true
        }
        guard type.rawValue == 14, let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return false }
        let data = ns.data1
        let code = (data & 0xFFFF0000) >> 16
        let down = (((data & 0x0000FFFF) & 0xFF00) >> 8) == 0xA
        let fine = ns.modifierFlags.contains([.option, .shift])    // Option + Shift: quarter steps, like macOS
        switch code {
        case 0, 1:   // sound up, down
            guard canSetVolume else { return false }
            if down { stepVolume(up: code == 0, fine: fine) }
            return true
        case 7:      // mute
            guard canSetVolume, readMute() != nil else { return false }
            if down { toggleMute() }
            return true
        case 2, 3:   // brightness up, down
            guard setBrightness != nil, getBrightness != nil else { return false }
            if down { stepBrightness(up: code == 2, fine: fine) }
            return true
        default:
            return false
        }
    }

    private var canSetVolume: Bool {
        isSettable(virtualAddress()) || isSettable(volumeAddress(kAudioObjectPropertyElementMain)) || (isSettable(volumeAddress(1)) && isSettable(volumeAddress(2)))
    }

    private func stepVolume(up: Bool, fine: Bool) {
        guard let cur = readVolume() else { return }
        let step: Float = fine ? 1.0 / 64 : 1.0 / 16
        let muted = readMute() ?? false
        let snapped = (cur / step).rounded() * step
        var v = snapped + (up ? step : -step)
        if abs(snapped - cur) > step * 0.5 { v = up ? ceil(cur / step) * step : floor(cur / step) * step }
        v = max(0, min(1, v))
        if muted && up { setMute(false) }
        setVolume(v)
        lastVolume = v
        lastMute = muted && !up ? true : false
        NotchbitModel.shared.showHUD(.volume, Double(v), muted: muted && !up)
    }

    private func setMute(_ on: Bool) {
        var a = muteAddress(), v = UInt32(on ? 1 : 0)
        AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v)
    }

    private func toggleMute() {
        let now = !(readMute() ?? false)
        setMute(now)
        lastMute = now
        NotchbitModel.shared.showHUD(.volume, Double(readVolume() ?? 0), muted: now)
    }

    private func stepBrightness(up: Bool, fine: Bool) {
        var b: Float = -1
        guard getBrightness?(screenID, &b) == 0 else { return }
        let step: Float = fine ? 1.0 / 64 : 1.0 / 16
        let v = max(0, min(1, (b / step).rounded() * step + (up ? step : -step)))
        _ = setBrightness?(screenID, v)
        lastBrightness = v
        NotchbitModel.shared.showHUD(.brightness, Double(v), muted: false)
    }
}
