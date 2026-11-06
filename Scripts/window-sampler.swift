// Sample only; never activates an app or captures screen pixels.
import AppKit
import CoreGraphics
import Darwin

@_silgen_name("proc_pidpath")
func processPath(_ pid: Int32, _ buffer: UnsafeMutableRawPointer, _ size: UInt32) -> Int32

let arguments = CommandLine.arguments
let stop = arguments[1], output = arguments[2]
let prefixes = Array(arguments.dropFirst(3))
let initial = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
var samples = 0
var windows: [[String: Any]] = []
var focusChanges: [[String: Any]] = []
func sample() {
    samples += 1
    let front = NSWorkspace.shared.frontmostApplication
    if let front, front.processIdentifier != initial {
        focusChanges.append(["pid": front.processIdentifier, "name": front.localizedName ?? "", "sample": samples])
    }
    guard let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
        fatalError("Window list unavailable; cannot prove invisibility")
    }
    for row in rows {
        guard let pid = row[kCGWindowOwnerPID as String] as? Int32,
              let alpha = row[kCGWindowAlpha as String] as? Double, alpha > 0 else { continue }
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = processPath(pid, &buffer, UInt32(buffer.count))
        let path = length > 0 ? String(cString: buffer) : ""
        let name = row[kCGWindowOwnerName as String] as? String ?? ""
        if prefixes.contains(where: { path.hasPrefix($0) }) || name == "xctest" {
            windows.append(["pid": pid, "name": name, "path": path, "alpha": alpha,
                            "window": row[kCGWindowNumber as String] ?? 0, "sample": samples])
        }
    }
}
sample()
try Data("ready".utf8).write(to: URL(fileURLWithPath: output + ".ready"))
while !FileManager.default.fileExists(atPath: stop) {
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    sample()
}
let result: [String: Any] = ["samples": samples, "intervalSeconds": 0.2, "initialFrontmostPID": initial,
                           "visibleWindows": windows, "focusChanges": focusChanges]
try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
    .write(to: URL(fileURLWithPath: output))
print("Window sampler: \(samples) samples, \(windows.count) visible windows, \(focusChanges.count) focus changes")
exit(windows.isEmpty && focusChanges.isEmpty ? 0 : 1)
