import Foundation

@main
enum PowerCoreTests {
    static func main() throws {
        let sample = """
        Battery Power:
         displaysleep 3
         disksleep 10
         sleep 15 (sleep prevented by powerd)
        AC Power:
         displaysleep 10
         sleep 0
        UPS Power:
         sleep 20
         displaysleep 5
        """
        let parsed = try PowerSnapshot.parse(sample)
        precondition(parsed.settings.count == 3)
        precondition(parsed.settings[.battery] == SleepSettings(display: 3, system: 15))
        precondition(parsed.settings[.ac] == SleepSettings(display: 10, system: 0))
        let command = try parsed.command()
        precondition(command == "/usr/bin/pmset -c displaysleep 10 sleep 0 && /usr/bin/pmset -b displaysleep 3 sleep 15 && /usr/bin/pmset -u displaysleep 5 sleep 20")
        let roundTrip = try JSONDecoder().decode(PowerSnapshot.self, from: JSONEncoder().encode(parsed))
        precondition(roundTrip == parsed)
        let invalidSamples = ["", "AC Power:\n displaysleep 10", "AC Power:\n sleep -1\n displaysleep 5", "Other:\n sleep 2\n displaysleep 3"]
        for sample in invalidSamples {
            do { _ = try PowerSnapshot.parse(sample); fatalError("Expected invalid parse: \(sample)") }
            catch is PowerError { }
        }
        precondition(!SleepSettings(display: -1, system: 2).isValid)
        precondition(!SleepSettings(display: 2, system: 1441).isValid)
        precondition(SleepSettings(display: 0, system: 1440).isValid)
        do {
            _ = try PowerSnapshot(settings: [.ac: .init(display: -1, system: 10)]).command()
            fatalError("Negative values must be rejected")
        } catch is PowerError { }
        let script = try PowerService.authorizationScript(for: PowerSnapshot(settings: [.ac: .init(display: 10, system: 30)]))
        precondition(script.contains("with administrator privileges"))
        precondition(script.contains("/usr/bin/pmset -c displaysleep 10 sleep 30"))
        let compiledScript = FileManager.default.temporaryDirectory.appendingPathComponent("mac-sleep-auth-\(UUID().uuidString).scpt")
        defer { try? FileManager.default.removeItem(at: compiledScript) }
        // Compile the real authorization script without executing it or requesting privileges.
        _ = try PowerService.run("/usr/bin/osacompile", ["-o", compiledScript.path, "-e", script])
        let live = try PowerService.read()
        precondition(!live.settings.isEmpty)
        print("PASS: parser, power-source isolation, command generation, validation, backup round-trip, authorization script compilation, live read")
    }
}
