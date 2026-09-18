import AppKit
import Carbon.HIToolbox

/// 通过 Carbon RegisterEventHotKey 注册系统级快捷键(默认 ⌥Space)。
/// RegisterEventHotKey 无需辅助功能权限。C 回调不能捕获上下文,故用静态注册表按 id 分发。
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let callback: () -> Void
    private let hotID: UInt32

    private static var registry: [UInt32: GlobalHotKey] = [:]
    private static var nextID: UInt32 = 1
    private static let signature: OSType = 0x4B454152 // 'KEAR'

    init?(
        keyCode: UInt32 = UInt32(kVK_Space),
        modifiers: UInt32 = UInt32(optionKey),
        callback: @escaping () -> Void
    ) {
        self.callback = callback
        self.hotID = GlobalHotKey.nextID
        GlobalHotKey.nextID += 1
        GlobalHotKey.registry[hotID] = self

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                var hkID = EventHotKeyID()
                GetEventParameter(event,
                                  EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID),
                                  nil,
                                  MemoryLayout<EventHotKeyID>.size,
                                  nil,
                                  &hkID)
                DispatchQueue.main.async {
                    GlobalHotKey.registry[hkID.id]?.callback()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &handlerRef
        )
        guard installStatus == noErr else {
            GlobalHotKey.registry[hotID] = nil
            return nil
        }

        let eventHotKeyID = EventHotKeyID(signature: GlobalHotKey.signature, id: hotID)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            eventHotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            GlobalHotKey.registry[hotID] = nil
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        GlobalHotKey.registry[hotID] = nil
    }
}
