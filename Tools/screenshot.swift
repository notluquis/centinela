// Renders `docs/panel.png`: the panel with invented data, for the README.
//
// Run it with `make screenshot`. It lives here rather than in a scratch directory because the
// image is committed, and an image nobody can regenerate goes stale without anybody noticing.

import AppKit
import CentinelaCore
import SwiftUI

// Invented data. Real responses carry internal URLs and business data, and this image is
// committed, so nothing here may come from a live organization.
@main struct Screenshot {
    static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let domain = "cl.bioalergia.centinela.shot"
        let suite = UserDefaults(suiteName: domain)!
        suite.removePersistentDomain(forName: domain)
        let settings = AppSettings(defaults: suite,
                                   tokenAccount: "centinela-shot-t",
                                   refreshAccount: "centinela-shot-r")
        settings.organization = "example"
        settings.saveToken("x")
        let state = AppState(settings: settings)

        let now = Date()
        let iso = ISO8601DateFormatter()
        func minutesAgo(_ minutos: Int) -> String {
            iso.string(from: now.addingTimeInterval(Double(-minutos) * 60))
        }

        func issue(_ id: String, _ title: String, _ culprit: String, _ count: Int,
                   _ users: Int, _ sub: String, _ pri: String, _ seen: String,
                   _ unhandled: Bool = false) -> SentryIssue {
            let json = """
            {"id":"\(id)","shortId":"EXAMPLE-API-\(id)","title":"\(title)","culprit":"\(culprit)",
             "level":"error","substatus":"\(sub)","priority":"\(pri)",
             "permalink":"https://example.sentry.io/issues/\(id)/",
             "lastSeen":"\(seen)","userCount":\(users),"count":"\(count)",
             "isUnhandled":\(unhandled),
             "project":{"id":"1","slug":"example-api","name":"example-api"}}
            """
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            return try! dec.decode(SentryIssue.self, from: Data(json.utf8))
        }

        var list: [SentryIssue] = []
        list.append(issue("41", "TypeError: cannot read property of an undefined value",
                           "src/routes/checkout.ts", 128, 34, "escalating", "high", minutesAgo(4), true))
        list.append(issue("42", "TimeoutError: upstream did not answer in 30s",
                           "src/services/billing.ts", 61, 12, "ongoing", "medium", minutesAgo(37)))
        list.append(issue("43", "DecodingError: keyNotFound(invoice_id)",
                           "src/jobs/reconcile.ts", 24, 5, "regressed", "medium", minutesAgo(96)))
        list.append(issue("44", "RangeError: invalid time value",
                           "src/lib/dates.ts", 9, 3, "new", "low", minutesAgo(210)))
        list.append(issue("45", "ConnectionResetError: peer closed the connection",
                           "src/db/pool.ts", 7, 2, "ongoing", "low", minutesAgo(320)))
        list.append(issue("46", "ValidationError: expected an ISO-8601 date",
                           "src/api/webhooks.ts", 4, 1, "new", "low", minutesAgo(600)))
        state.data.issues = list
        // Through JSON rather than `Point`'s initialiser, which is internal. It also means the
        // image exercises the same decoder the app runs.
        let heights: [Int] = [3, 5, 4, 9, 22, 14, 7, 6, 5, 11, 31, 18, 8, 6, 4, 5]
        var rows: [String] = []
        for index in 0..<24 {
            let at: Int = Int(now.timeIntervalSince1970) - (24 - index) * 3600
            let howMany: Int = heights[index % 16]
            rows.append("[\(at),[{\"count\":\(howMany)}]]")
        }
        let raw: String = "{\"data\":[" + rows.joined(separator: ",") + "]}"
        state.data.series = (try? EventSeries(json: Data(raw.utf8))) ?? EventSeries(points: [])
        state.lastUpdated = now

        // Health needs something in it, because the second panel in the picture shows that
        // tab and an empty one would say the app has nothing to show.
        state.data.crashFree = 0.9987
        let uptime = """
        [{"id":"1","name":"api.example.com","status":"active","url":"https://api.example.com",
          "intervalSeconds":60,"uptimeStatus":1}]
        """
        let decoder = JSONDecoder()
        state.data.monitors = (try? decoder.decode([UptimeMonitor].self, from: Data(uptime.utf8))) ?? []
        let byProject = """
        {"groups":[{"by":{"project":1},"totals":{"sum(quantity)":214}},
                   {"by":{"project":2},"totals":{"sum(quantity)":14}}]}
        """
        let projects = """
        [{"id":"1","slug":"example-api","name":"example-api"},
         {"id":"2","slug":"example-web","name":"example-web"}]
        """
        state.data.errorsByProject = (try? ProjectErrorCount.from(
            statsJSON: Data(byProject.utf8),
            projects: decoder.decode([Project].self, from: Data(projects.utf8)))) ?? []

        // Two panels, the same view twice with a different tab showing. Rendered from
        // `MainPanel` rather than drawn by hand, so a picture that stops matching the app is a
        // compile error and not a stale illustration.
        //
        // A background of its own on each. Alone the panel has none of the material
        // `MenuBarExtra` draws, and with no vibrancy behind it every label resolves to white:
        // the first version of this image came out with the sparkline, the level icons, and not
        // one letter. Dark on purpose, which is also how it looks in the bar.
        func shot(_ tab: PanelSection) -> NSImage? {
            let root = ZStack {
                Color(nsColor: NSColor(calibratedWhite: 0.13, alpha: 1))
                MainPanel(initialSection: tab, state: state)
            }
            let host = NSHostingView(rootView: root)
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 430),
                               styleMask: [.borderless], backing: .buffered, defer: false)
            win.contentView = host
            // On screen rather than offscreen: the view needs a real backing store to draw text.
            win.appearance = NSAppearance(named: .darkAqua)
            win.setFrameOrigin(NSPoint(x: 100, y: 100))
            win.orderFrontRegardless()
            host.layoutSubtreeIfNeeded()
            // Sized to its content, the way the real panel is.
            let height = max(host.fittingSize.height, 260)
            win.setContentSize(NSSize(width: 380, height: height))
            host.frame = NSRect(x: 0, y: 0, width: 380, height: height)
            host.layoutSubtreeIfNeeded()
            for _ in 0..<60 {
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
                host.layoutSubtreeIfNeeded()
                host.displayIfNeeded()
            }
            // The probe signs in with an invented token, so Sentry answers 401 and the panel says
            // so. That banner belongs to the probe, not to the app, and does not go in the image.
            state.data.lastError = nil
            state.lastUpdated = now.addingTimeInterval(-8)
            host.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
            host.cacheDisplay(in: host.bounds, to: rep)
            let image = NSImage(size: host.bounds.size)
            image.addRepresentation(rep)
            win.orderOut(nil)
            return image
        }

        guard let front = shot(.issues), let back = shot(.health) else { return }

        // Side by side and both whole, not one stacked behind the other. Stacked was tried and
        // read as a rendering fault rather than as two views: the panel repeats its header, so
        // the same large number appeared twice with one copy sliced by the panel in front of it.
        //
        // `MenuBarExtra(.window)` draws a rounded panel that floats over the desktop. Written out
        // flat it read as a mock-up of the app rather than a picture of it. The margin is
        // transparent, so the image sits on whatever background reads it.
        let radius: CGFloat = 12
        let margin: CGFloat = 30
        let gap: CGFloat = 26
        let tall = max(front.size.height, back.size.height)
        let size = NSSize(width: front.size.width + gap + back.size.width + margin * 2,
                          height: tall + margin * 2)

        let canvas = NSImage(size: size)
        canvas.lockFocus()
        func place(_ image: NSImage, x: CGFloat) {
            // Top-aligned: the panels differ in height by whatever their lists reserve, and
            // hanging them from the same top edge reads as two windows rather than two
            // rectangles that happen to sit on a shelf.
            let frame = NSRect(x: x, y: size.height - margin - image.size.height,
                               width: image.size.width, height: image.size.height)
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
            shadow.shadowBlurRadius = 18
            shadow.shadowOffset = NSSize(width: 0, height: -5)
            NSGraphicsContext.current?.saveGraphicsState()
            shadow.set()
            NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).fill()
            NSGraphicsContext.current?.restoreGraphicsState()
            NSGraphicsContext.current?.saveGraphicsState()
            NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).addClip()
            image.draw(in: frame)
            NSGraphicsContext.current?.restoreGraphicsState()
        }
        place(front, x: margin)
        place(back, x: margin + front.size.width + gap)
        canvas.unlockFocus()

        guard let data = canvas.tiffRepresentation,
              let out = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
        else { return }
        try? out.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        print("  escrito: \(CommandLine.arguments[1])")
        try? Keychain.delete(account: "centinela-shot-t")
        suite.removePersistentDomain(forName: domain)
    }
}
