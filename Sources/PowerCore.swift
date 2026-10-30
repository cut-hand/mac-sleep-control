import Foundation

enum PowerSource: String, Codable, CaseIterable, Sendable, Identifiable {
    case ac, battery, ups
    var id: String { rawValue }
    var title: String {
        switch self { case .ac: return "接通电源"; case .battery: return "使用电池"; case .ups: return "UPS 电源" }
    }
    var flag: String {
        switch self { case .ac: return "-c"; case .battery: return "-b"; case .ups: return "-u" }
    }
}

struct SleepSettings: Codable, Equatable, Sendable {
    var display: Int
    var system: Int
    var isValid: Bool { (0...1440).contains(display) && (0...1440).contains(system) }
    func matches(_ other: Self) -> Bool { self == other }
}

struct PowerSnapshot: Codable, Equatable, Sendable {
    var settings: [PowerSource: SleepSettings]
    var createdAt: Date = Date()

    static func parse(_ output: String) throws -> Self {
        var source: PowerSource?
        var values: [PowerSource: [String: Int]] = [:]
        for raw in output.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasSuffix(":") {
                switch line {
                case "AC Power:": source = .ac
                case "Battery Power:": source = .battery
                case "UPS Power:": source = .ups
                default: source = nil
                }
                continue
            }
            let parts = line.split(whereSeparator: { $0.isWhitespace })
            if let source, parts.count >= 2,
               ["displaysleep", "sleep"].contains(String(parts[0])),
               let value = Int(parts[1]), value >= 0 {
                values[source, default: [:]][String(parts[0])] = value
            }
        }
        let settings = values.compactMapValues { values -> SleepSettings? in
            guard let display = values["displaysleep"], let system = values["sleep"] else { return nil }
            return SleepSettings(display: display, system: system)
        }
        guard !settings.isEmpty else { throw PowerError.message("无法读取系统的息屏和睡眠设置。") }
        return Self(settings: settings)
    }

    func command() throws -> String {
        guard !settings.isEmpty else { throw PowerError.message("没有可应用的电源设置。") }
        return try PowerSource.allCases.compactMap { source in
            guard let setting = settings[source] else { return nil }
            // Restoring existing system values can exceed the editor's 24-hour range.
            guard setting.display >= 0, setting.system >= 0 else { throw PowerError.message("时间不能为负数。") }
            return "/usr/bin/pmset \(source.flag) displaysleep \(setting.display) sleep \(setting.system)"
        }.joined(separator: " && ")
    }
}

enum PowerError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(message) = self { return message }; return nil }
}

enum PowerService {
    static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            if output.contains("(-128)") { throw PowerError.message("已取消授权，系统设置未提交。") }
            throw PowerError.message(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }

    static func read() throws -> PowerSnapshot { try .parse(run("/usr/bin/pmset", ["-g", "custom"])) }

    static func authorizationScript(for snapshot: PowerSnapshot) throws -> String {
        let command = try snapshot.command()
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\" with prompt \"息眠需要更新 Mac 的息屏和睡眠时间。\" with administrator privileges"
    }

    static func apply(_ snapshot: PowerSnapshot) throws {
        _ = try run("/usr/bin/osascript", ["-e", try authorizationScript(for: snapshot)])
    }
}
