import SwiftUI
import Combine
import IOKit.pwr_mgt

@MainActor
final class PowerModel: ObservableObject {
    @Published var current: PowerSnapshot?
    @Published var selected: PowerSource = .ac
    @Published var displayText = "10"
    @Published var sleepText = "30"
    @Published var displayNever = false
    @Published var sleepNever = false
    @Published var busy = false
    @Published var message = "正在读取系统设置…"
    @Published var isError = false
    @Published var backup: PowerSnapshot?
    @Published var keepAwake = false
    @Published var keepDisplayOn = false
    @Published var awakeMinutes = 60
    @Published var awakeUntil: Date?
    @Published var diagnostics = ""
    @Published var showDiagnostics = false
    @Published var confirmRestore = false
    @Published var confirmSleep = false
    private var assertions: [IOPMAssertionID] = []
    private var expiryTimer: Timer?

    private var backupURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacSleepControl", isDirectory: true).appendingPathComponent("original-settings.json")
    }

    init() {
        do {
            if FileManager.default.fileExists(atPath: backupURL.path) {
                backup = try JSONDecoder().decode(PowerSnapshot.self, from: Data(contentsOf: backupURL))
            }
        } catch { message = "原设置备份读取失败：\(error.localizedDescription)"; isError = true }
    }

    var sources: [PowerSource] { PowerSource.allCases.filter { current?.settings[$0] != nil } }
    var editorSettings: SleepSettings? {
        guard let display = displayNever ? 0 : Int(displayText.trimmingCharacters(in: .whitespaces)),
              let sleep = sleepNever ? 0 : Int(sleepText.trimmingCharacters(in: .whitespaces)),
              displayNever || display > 0, sleepNever || sleep > 0 else { return nil }
        let settings = SleepSettings(display: display, system: sleep)
        return settings.isValid ? settings : nil
    }
    var changed: Bool { guard let editorSettings else { return false }; return current?.settings[selected] != editorSettings }
    var timingHint: String? {
        guard let s = editorSettings else { return "请输入 1–1440 的整数分钟，或选择「永不」。" }
        if s.system > 0 && (s.display == 0 || s.system < s.display) {
            return "电脑睡眠也会关闭屏幕，实际息屏可能早于上方设定。"
        }
        return nil
    }

    func loadEditor() {
        guard let setting = current?.settings[selected] else { return }
        displayNever = setting.display == 0
        sleepNever = setting.system == 0
        displayText = String(setting.display == 0 ? 10 : setting.display)
        sleepText = String(setting.system == 0 ? 30 : setting.system)
    }

    func refresh() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let snapshot = try await Task.detached { try PowerService.read() }.value
            current = snapshot
            if snapshot.settings[selected] == nil { selected = sources.first ?? .ac }
            loadEditor()
            setMessage("已读取系统当前设置")
        } catch { setMessage(error.localizedDescription, error: true) }
    }

    func preset(display: Int, sleep: Int) {
        displayNever = display == 0; sleepNever = sleep == 0
        displayText = String(display == 0 ? 10 : display)
        sleepText = String(sleep == 0 ? 30 : sleep)
    }

    private func ensureBackup(_ snapshot: PowerSnapshot) throws {
        guard backup == nil else { return }
        try FileManager.default.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: backupURL, options: .atomic)
        backup = snapshot
    }

    func apply(restore: Bool = false) async {
        guard !busy, let editorSettings = restore ? SleepSettings(display: 0, system: 0) : editorSettings else { return }
        busy = true
        defer { busy = false }
        do {
            let before = try await Task.detached { try PowerService.read() }.value
            let target: PowerSnapshot
            if restore {
                guard let backup else { throw PowerError.message("还没有原设置备份。") }
                target = PowerSnapshot(settings: backup.settings.filter { before.settings[$0.key] != nil })
                guard !target.settings.isEmpty else { throw PowerError.message("备份中没有此 Mac 可用的电源类型。") }
            } else {
                guard before.settings[selected] != nil else { throw PowerError.message("此电源类型已不可用，请刷新。") }
                try ensureBackup(before)
                target = PowerSnapshot(settings: [selected: editorSettings])
            }
            do {
                try await Task.detached { try PowerService.apply(target) }.value
            } catch {
                // Multi-source restoration may partially succeed; always show the actual state.
                current = try? await Task.detached { try PowerService.read() }.value
                loadEditor()
                throw error
            }
            let after = try await Task.detached { try PowerService.read() }.value
            current = after; loadEditor()
            guard target.settings.allSatisfy({ after.settings[$0.key] == $0.value }) else {
                throw PowerError.message("系统返回的时间与请求不一致，请查看当前值后重试。")
            }
            setMessage(restore ? "已恢复首次修改前的设置" : "已应用并核对系统设置，退出应用后仍然有效")
        } catch { setMessage(error.localizedDescription, error: true) }
    }

    func startAwake() {
        stopAwake(announce: false)
        let types = keepDisplayOn ? [kIOPMAssertionTypePreventUserIdleSystemSleep, kIOPMAssertionTypePreventUserIdleDisplaySleep] : [kIOPMAssertionTypePreventUserIdleSystemSleep]
        for type in types {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "MacSleepControl temporary keep-awake" as CFString, &id)
            guard result == kIOReturnSuccess else {
                stopAwake(announce: false)
                setMessage("无法开启临时保持唤醒（\(result)）", error: true)
                return
            }
            assertions.append(id)
        }
        keepAwake = true
        if awakeMinutes > 0 {
            awakeUntil = Date().addingTimeInterval(Double(awakeMinutes * 60))
            expiryTimer = Timer.scheduledTimer(withTimeInterval: Double(awakeMinutes * 60), repeats: false) { [weak self] _ in
                Task { @MainActor in self?.stopAwake() }
            }
        }
        setMessage("临时保持唤醒已开启\(keepDisplayOn ? "，屏幕将保持常亮" : "，屏幕仍可按系统设置息屏")")
    }

    func stopAwake(announce: Bool = true) {
        expiryTimer?.invalidate(); expiryTimer = nil
        for id in assertions { IOPMAssertionRelease(id) }
        assertions.removeAll(); keepAwake = false; awakeUntil = nil
        if announce { setMessage("已结束临时保持唤醒") }
    }

    func immediateSleep(displayOnly: Bool) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            stopAwake(announce: false)
            _ = try await Task.detached { try PowerService.run("/usr/bin/pmset", [displayOnly ? "displaysleepnow" : "sleepnow"]) }.value
            setMessage(displayOnly ? "已发送立即息屏指令" : "已发送立即睡眠指令")
        } catch { setMessage(error.localizedDescription, error: true) }
    }

    func inspectAssertions() async {
        do {
            diagnostics = try await Task.detached { try PowerService.run("/usr/bin/pmset", ["-g", "assertions"]) }.value
            showDiagnostics = true
        } catch { setMessage(error.localizedDescription, error: true) }
    }

    func setMessage(_ text: String, error: Bool = false) { message = text; isError = error }
    func format(_ value: Int) -> String { value == 0 ? "永不" : "\(value) 分钟" }
}
