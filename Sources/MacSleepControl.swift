import SwiftUI
import AppKit

@main
struct MacSleepControlApp: App {
    @StateObject private var model = PowerModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("息眠", id: "main") {
            ContentView(model: model)
                .task { await model.refresh() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.stopAwake(announce: false) }
        }
        .defaultSize(width: 740, height: 740)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .appInfo) {
                Button("显示息眠") { showMain() }.keyboardShortcut("0", modifiers: .command)
            }
        }

        MenuBarExtra("息眠", systemImage: model.keepAwake ? "sun.max.fill" : "moon.zzz") {
            Button("打开息眠…") { showMain() }
            if let setting = model.current?.settings[model.selected] {
                Text("息屏：\(model.format(setting.display)) · 睡眠：\(model.format(setting.system))")
            }
            Divider()
            if model.keepAwake {
                Button("结束临时保持唤醒") { model.stopAwake() }
            } else {
                Button("保持唤醒 1 小时") { model.awakeMinutes = 60; model.keepDisplayOn = false; model.startAwake() }
            }
            Button("立即息屏") { Task { await model.immediateSleep(displayOnly: true) } }.disabled(model.busy)
            Divider()
            Button("退出息眠") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
        }
    }

    private func showMain() { openWindow(id: "main"); NSApplication.shared.activate(ignoringOtherApps: true) }
}

struct ContentView: View {
    @ObservedObject var model: PowerModel
    private let ink = Color(red: 0.17, green: 0.20, blue: 0.27)
    private let accent = Color(red: 0.26, green: 0.37, blue: 0.68)

    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack(spacing: 14) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 28)).foregroundStyle(.white)
                    .frame(width: 57, height: 57)
                    .background(LinearGradient(colors: [accent, Color(red: 0.43, green: 0.47, blue: 0.71)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 17))
                VStack(alignment: .leading, spacing: 4) {
                    Text("息眠").font(.system(size: 26, weight: .bold))
                    Text("让屏幕和 Mac，按你的节奏休息。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("重新读取系统设置，放弃未应用的编辑").disabled(model.busy)
            }

            HStack {
                Text("闲置多久后休息").font(.system(size: 15, weight: .semibold))
                Spacer()
                if model.sources.count > 1 {
                    Picker("电源", selection: $model.selected) {
                        ForEach(model.sources) { source in Text(source.title).tag(source) }
                    }.labelsHidden().frame(width: 185)
                        .onChange(of: model.selected) { model.loadEditor() }
                        .disabled(model.busy)
                } else { Label(model.selected.title, systemImage: "powerplug").font(.system(size: 12)).foregroundStyle(.secondary) }
            }

            HStack(alignment: .top, spacing: 14) {
                timerCard("显示器息屏", subtitle: "关闭屏幕，电脑可继续工作", icon: "display", text: $model.displayText, never: $model.displayNever, current: model.current?.settings[model.selected]?.display)
                timerCard("电脑睡眠", subtitle: "让整台 Mac 进入低功耗状态", icon: "bed.double.fill", text: $model.sleepText, never: $model.sleepNever, current: model.current?.settings[model.selected]?.system)
            }.disabled(model.busy || model.current == nil)

            HStack(spacing: 8) {
                Text("快捷方案").font(.system(size: 11)).foregroundStyle(.secondary)
                Button("省电 · 5 / 15") { model.preset(display: 5, sleep: 15) }
                Button("日常 · 10 / 30") { model.preset(display: 10, sleep: 30) }
                Button("仅息屏") { model.preset(display: 10, sleep: 0) }
                Button("始终开启") { model.preset(display: 0, sleep: 0) }
            }.controlSize(.small).disabled(model.busy || model.current == nil)

            VStack(alignment: .leading, spacing: 6) {
                Text(model.timingHint ?? "从停止操作鼠标、键盘后计时。修改后点击「应用设置」生效。")
                    .foregroundStyle(model.editorSettings == nil ? .red : .secondary)
                Text("正在播放媒体、运行任务等应用活动可能推迟自动睡眠。")
                    .foregroundStyle(.secondary)
            }.font(.system(size: 11))

            HStack {
                Button("恢复原设置…") { model.confirmRestore = true }.disabled(model.backup == nil || model.busy)
                if model.busy { ProgressView().controlSize(.small).padding(.leading, 8) }
                Spacer()
                Button("应用设置") { Task { await model.apply() } }
                    .buttonStyle(.borderedProminent).tint(accent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.busy || !model.changed || model.editorSettings == nil || model.current == nil)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("临时保持唤醒", systemImage: "cup.and.saucer").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    if model.keepAwake {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            if let date = model.awakeUntil { Text("至 \(date.formatted(date: .omitted, time: .shortened))").font(.system(size: 11)).foregroundStyle(accent) }
                            else { Text("至退出应用").font(.system(size: 11)).foregroundStyle(accent) }
                        }
                    }
                }
                HStack(spacing: 15) {
                    Picker("持续", selection: $model.awakeMinutes) {
                        Text("30 分钟").tag(30)
                        Text("1 小时").tag(60)
                        Text("2 小时").tag(120)
                        Text("直到退出").tag(0)
                    }.frame(width: 165).disabled(model.keepAwake)
                    Toggle("屏幕也保持常亮", isOn: $model.keepDisplayOn).font(.system(size: 12)).disabled(model.keepAwake)
                    Spacer()
                    Button(model.keepAwake ? "结束" : "开始") { model.keepAwake ? model.stopAwake() : model.startAwake() }
                        .disabled(model.busy)
                }
                Text("适合下载、演示或长时间任务；到期或退出后自动结束，合盖仍由 macOS 管理。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(17).background(accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))

            HStack(spacing: 10) {
                Button("立即息屏") { Task { await model.immediateSleep(displayOnly: true) } }
                Button("立即睡眠…") { model.confirmSleep = true }
                Spacer()
                Button("查看防睡眠活动") { Task { await model.inspectAssertions() } }.buttonStyle(.link).font(.system(size: 11))
            }.controlSize(.small).disabled(model.busy)

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: model.isError ? "exclamationmark.circle" : "checkmark.circle")
                Text(model.message).textSelection(.enabled).lineLimit(3)
            }.font(.system(size: 11)).foregroundStyle(model.isError ? Color.red : Color.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 28, alignment: .top)
        }
        .padding(28).frame(width: 740)
        .foregroundStyle(ink).background(Color(red: 0.97, green: 0.975, blue: 0.985))
        .preferredColorScheme(.light)
        .alert("恢复首次修改前的设置？", isPresented: $model.confirmRestore) {
            Button("取消", role: .cancel) { }
            Button("恢复") { Task { await model.apply(restore: true) } }
        } message: {
            Text("会恢复已备份的各电源类型的息屏和睡眠时间。\(model.backup.map { "备份时间：" + $0.createdAt.formatted(date: .abbreviated, time: .shortened) } ?? "")")
        }
        .alert("现在让 Mac 睡眠？", isPresented: $model.confirmSleep) {
            Button("取消", role: .cancel) { }
            Button("立即睡眠") { Task { await model.immediateSleep(displayOnly: false) } }
        } message: { Text("进行中的任务可能暂停，临时保持唤醒也会结束。") }
        .sheet(isPresented: $model.showDiagnostics) {
            VStack(alignment: .leading, spacing: 14) {
                Text("防睡眠活动").font(.title2.bold())
                Text("这些是 macOS 当前记录的活动。PreventUserIdleSystemSleep 等条目可能延迟睡眠；列表会随应用状态变化。")
                    .font(.callout).foregroundStyle(.secondary)
                ScrollView([.horizontal, .vertical]) {
                    Text(model.diagnostics).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack { Spacer(); Button("完成") { model.showDiagnostics = false }.keyboardShortcut(.defaultAction) }
            }.padding(24).frame(width: 760, height: 470)
        }
    }

    private func timerCard(_ title: String, subtitle: String, icon: String, text: Binding<String>, never: Binding<Bool>, current: Int?) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack { Image(systemName: icon).font(.system(size: 21)).foregroundStyle(accent); Spacer(); Text("当前 \(current.map(model.format) ?? "—")").font(.system(size: 10)).foregroundStyle(.secondary) }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("分钟", text: text)
                    .font(.system(size: 34, weight: .medium, design: .rounded)).textFieldStyle(.plain)
                    .frame(width: 135).disabled(never.wrappedValue)
                    .opacity(never.wrappedValue ? 0.25 : 1)
                    .accessibilityLabel("\(title)分钟数")
                Text("分钟").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            HStack {
                ForEach([5, 15, 30, 60], id: \.self) { minutes in
                    Button("\(minutes)") { text.wrappedValue = String(minutes); never.wrappedValue = false }.controlSize(.mini)
                }
                Spacer()
            }
            Toggle("永不\(title == "显示器息屏" ? "息屏" : "睡眠")", isOn: never).font(.system(size: 12)).toggleStyle(.switch).controlSize(.mini)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(ink.opacity(0.07), lineWidth: 1))
    }
}
