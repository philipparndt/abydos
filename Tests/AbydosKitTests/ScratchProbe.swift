import Testing
import Foundation
@testable import AbydosKit

struct ScratchProbe {
    @Test func probe() {
        let root = URL(fileURLWithPath: "/Users/philipparndt/dev/smarthome/projects/mqtt-lamarzocco")
        let found = RunConfigurationDiscovery.discover(in: root)
        print("PROBE total \(found.count)")
        for c in found.prefix(30) {
            print("PROBE \(c.source.rawValue) | \(c.name) | \(c.file ?? "-"):\(c.line.map(String.init) ?? "-")")
        }
        let mains = RunConfigurationDiscovery.mainPackages(under: root.appendingPathComponent("app"))
        print("PROBE mains \(mains)")
    }
}
