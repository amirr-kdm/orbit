import AppKit

/// macOS draws the lock screen in its own space, and normal windows are not shown there.
/// Like other notch apps, this puts the notch window into a space of its own that macOS shows above everything,
/// including the lock screen. It uses private window-server calls looked up at run time: if any is missing (a new macOS), nothing happens.
enum LockScreen {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, UnsafeRawPointer?) -> Int32
    private typealias SetLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    private static var space: Int32 = 0

    static var wanted: Bool { UserDefaults.standard.object(forKey: "notchbit.lockScreen") as? Bool ?? true }

    @discardableResult
    static func attach(_ window: NSWindow) -> Bool {
        guard wanted, window.windowNumber > 0,
              let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
              let a = dlsym(h, "SLSMainConnectionID"), let b = dlsym(h, "SLSSpaceCreate"), let c = dlsym(h, "SLSSpaceSetAbsoluteLevel"),
              let d = dlsym(h, "SLSShowSpaces"), let e = dlsym(h, "SLSSpaceAddWindowsAndRemoveFromSpaces") else { return false }
        let conn = unsafeBitCast(a, to: MainConnection.self)()
        if space == 0 {
            space = unsafeBitCast(b, to: SpaceCreate.self)(conn, 1, nil)
            guard space != 0 else { return false }
            let lr = unsafeBitCast(c, to: SetLevel.self)(conn, space, 400)
            let sr = unsafeBitCast(d, to: ShowSpaces.self)(conn, [NSNumber(value: space)] as CFArray)
            NSLog("[Notchbit] lock space created: id=%d setLevel=%d show=%d", space, lr, sr)
        } else {
            _ = unsafeBitCast(d, to: ShowSpaces.self)(conn, [NSNumber(value: space)] as CFArray)
        }
        let rc = unsafeBitCast(e, to: AddWindows.self)(conn, space, [NSNumber(value: window.windowNumber)] as CFArray, 7)
        NSLog("[Notchbit] lock attach: window=%d space=%d rc=%d", window.windowNumber, space, rc)
        return true
    }
}
