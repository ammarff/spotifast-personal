import AppKit
import Foundation
import PockKit

private struct LyricSnapshot: Decodable {
    let enabled: Bool
    let playing: Bool?
    let position_ms: UInt64?
    let sampled_at_ms: UInt64?
    let current: String?
    let next_at_ms: UInt64?
    let next: String?

    func visibleLine(at now: Date) -> String {
        guard enabled else { return "" }
        if playing == true,
           let position = position_ms,
           let sampled = sampled_at_ms,
           let nextAt = next_at_ms,
           let nextLine = next {
            let elapsed = max(0, now.timeIntervalSince1970 * 1000 - Double(sampled))
            if Double(position) + elapsed >= Double(nextAt) {
                return nextLine
            }
        }
        return current ?? ""
    }
}

@objc(SpotifastLyricsWidget)
final class SpotifastLyricsWidget: NSObject, PKWidget {
    static var identifier: String = "SpotifastLyricsWidget"
    var customizationLabel: String = "Spotifast Lyrics"
    var view: NSView!

    var imageForCustomization: NSImage {
        let image = NSImage(size: NSSize(width: 320, height: 30))
        image.lockFocus()
        ("Spotifast Lyrics" as NSString).draw(
            at: NSPoint(x: 12, y: 7),
            withAttributes: [.foregroundColor: NSColor.labelColor,
                             .font: NSFont.systemFont(ofSize: 14)]
        )
        image.unlockFocus()
        return image
    }

    private let label = NSTextField(labelWithString: "")
    private var timer: Timer?
    private var reading = false
    private var lastRead: Date?
    private var snapshot: LyricSnapshot?

    override required init() {
        super.init()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 30))
        label.frame = NSRect(x: 8, y: 4, width: 304, height: 22)
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        container.addSubview(label)
        view = container
    }

    func initialize() {}

    func viewDidAppear() {
        timer?.invalidate()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func viewDidDisappear() {
        timer?.invalidate()
        timer = nil
        snapshot = nil
        lastRead = nil
        label.stringValue = ""
    }

    private func tick() {
        label.stringValue = snapshot?.visibleLine(at: Date()) ?? ""
        // A 1-second read catches track changes. The local clock above
        // advances a known timed line without waiting for that read.
        if lastRead.map({ Date().timeIntervalSince($0) >= 1 }) ?? true {
            refresh()
        }
    }

    private func refresh() {
        guard !reading else { return }
        reading = true
        lastRead = Date()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Self.readSnapshot()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.reading = false
                guard self.timer != nil else { return }
                self.snapshot = result
                self.label.stringValue = result?.visibleLine(at: Date()) ?? ""
            }
        }
    }

    private static func readSnapshot() -> LyricSnapshot? {
        guard let app = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "rocks.spotifast.Spotifast"
        ) else { return nil }
        let binary = app.appendingPathComponent("Contents/MacOS/Spotifast")
        guard FileManager.default.isExecutableFile(atPath: binary.path) else { return nil }
        let process = Process()
        let output = Pipe()
        process.executableURL = binary
        process.arguments = ["lyrics"]
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return try JSONDecoder().decode(LyricSnapshot.self, from: data)
        } catch {
            return nil
        }
    }
}
