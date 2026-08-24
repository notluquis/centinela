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

        // Two different windows, not the same one twice. Stacking two panels was tried and read
        // as a rendering fault: the panel repeats its header, so the same large number appeared
        // twice with one copy sliced by the panel in front of it. The settings window shares no
        // chrome with the panel, so the overlap reads as two windows of one app.
        //
        // Both come from the real views rather than being drawn by hand, so a picture that stops
        // matching the app is a compile error and not an illustration nobody updated.
        //
        // A background of its own on each. Alone these have none of the material the system
        // draws behind them, and with no vibrancy every label resolves to white: the first
        // version of this image came out with the sparkline, the level icons, and not one
        // letter. Dark on purpose, which is also how it looks on screen.
        func shot<V: View>(_ view: V, width: CGFloat, minimum: CGFloat) -> NSImage? {
            let root = ZStack {
                Color(nsColor: NSColor(calibratedWhite: 0.13, alpha: 1))
                view
            }
            let host = NSHostingView(rootView: root)
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: minimum),
                               styleMask: [.borderless], backing: .buffered, defer: false)
            win.contentView = host
            // On screen rather than offscreen: the view needs a real backing store to draw text.
            win.appearance = NSAppearance(named: .darkAqua)
            win.setFrameOrigin(NSPoint(x: 100, y: 100))
            win.orderFrontRegardless()
            host.layoutSubtreeIfNeeded()
            let height = max(host.fittingSize.height, minimum)
            win.setContentSize(NSSize(width: width, height: height))
            host.frame = NSRect(x: 0, y: 0, width: width, height: height)
            host.layoutSubtreeIfNeeded()
            for _ in 0..<60 {
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
                host.layoutSubtreeIfNeeded()
                host.displayIfNeeded()
            }
            // The probe signs in with an invented token, so Sentry answers 401 and the panel says
            // so. That banner belongs to the probe, not to the app, and does not go in the image.
            state.data.lastError = nil
            // Ninety seconds and not eight. The footer renders this relative to the real clock,
            // so at eight seconds the string moved between one render and the next — "10 seconds
            // ago", then "12" — and every `make screenshot` rewrote both images with visually
            // identical content, leaving a new half-megabyte blob in the repository each time.
            // Eight versions of this file already account for a third of `.git`. At ninety
            // seconds the string is "1 minute ago" with half a minute of slack either side, which
            // a render measured at about two seconds cannot cross.
            //
            // Measured after the change: two consecutive runs produce byte-identical files. A
            // run that follows a rebuild of this tool can still differ, so the rule stands —
            // regenerate when the interface changed, not out of habit.
            state.lastUpdated = now.addingTimeInterval(-90)
            host.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
            host.cacheDisplay(in: host.bounds, to: rep)
            let image = NSImage(size: host.bounds.size)
            image.addRepresentation(rep)
            win.orderOut(nil)
            return image
        }

        guard let back = shot(SettingsView(state: state), width: 480, minimum: 430),
              let front = shot(MainPanel(state: state), width: 380, minimum: 260)
        else { return }


        // Overlapped the way a second window sits over the first: the settings window up and
        // to the right, the panel over its lower left. `MenuBarExtra(.window)` draws a rounded
        // panel that floats, and written out flat it read as a mock-up rather than a picture of
        // the app. The margin is transparent, so the image sits on whatever reads it.
        let radius: CGFloat = 12
        let margin: CGFloat = 34
        let overlapX: CGFloat = 178
        let overlapY: CGFloat = 54
        let size = NSSize(width: front.size.width + overlapX + margin * 2,
                          height: max(front.size.height + overlapY, back.size.height) + margin * 2)

        let canvas = NSImage(size: size)
        canvas.lockFocus()
        func place(_ image: NSImage, at origin: NSPoint, blur: CGFloat) {
            let frame = NSRect(origin: origin, size: image.size)
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
            shadow.shadowBlurRadius = blur
            shadow.shadowOffset = NSSize(width: 0, height: -6)
            NSGraphicsContext.current?.saveGraphicsState()
            shadow.set()
            NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).fill()
            NSGraphicsContext.current?.restoreGraphicsState()
            NSGraphicsContext.current?.saveGraphicsState()
            NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).addClip()
            image.draw(in: frame)
            NSGraphicsContext.current?.restoreGraphicsState()
        }
        place(back, at: NSPoint(x: size.width - margin - back.size.width,
                                y: size.height - margin - back.size.height), blur: 16)
        place(front, at: NSPoint(x: margin, y: margin), blur: 26)
        canvas.unlockFocus()

        func write(_ image: NSImage, to path: String) {
            guard let data = image.tiffRepresentation,
                  let out = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
            else { return }
            try? out.write(to: URL(fileURLWithPath: path))
        }
        let output = CommandLine.arguments[1]
        write(canvas, to: output)

        // And the social preview: the image GitHub shows when somebody pastes the link into Slack
        // or a timeline. 1280 by 640 is the size it asks for, and its own template says to keep
        // the parts that matter inside a 40-point border because the card gets cropped — so
        // everything here sits at least 72 points from an edge, which is that margin with room
        // to spare. Made here rather than by hand so it cannot end up showing a version of the
        // app that no longer looks like this.
        let safe: CGFloat = 72
        let card = NSImage(size: NSSize(width: 1280, height: 640))
        card.lockFocus()
        NSColor(calibratedWhite: 0.09, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 1280, height: 640).fill()

        let shotWidth: CGFloat = 540
        let scale = shotWidth / canvas.size.width
        let shotSize = NSSize(width: shotWidth, height: canvas.size.height * scale)
        canvas.draw(in: NSRect(x: 1280 - shotWidth - safe,
                               y: (640 - shotSize.height) / 2,
                               width: shotSize.width, height: shotSize.height))

        let title = NSAttributedString(string: "Centinela", attributes: [
            .font: NSFont.systemFont(ofSize: 72, weight: .semibold),
            .foregroundColor: NSColor.white
        ])
        title.draw(at: NSPoint(x: safe, y: 366))

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 6
        let tagline = NSAttributedString(
            string: "Your Sentry issues in the\nmacOS menu bar.\n\nNative SwiftUI. Read-only.\nBuilds without Xcode.",
            attributes: [
                .font: NSFont.systemFont(ofSize: 27, weight: .regular),
                .foregroundColor: NSColor(calibratedWhite: 0.72, alpha: 1),
                .paragraphStyle: paragraph
            ])
        tagline.draw(in: NSRect(x: safe + 2, y: 148, width: 470, height: 200))
        card.unlockFocus()
        write(card, to: (output as NSString).deletingLastPathComponent + "/social-preview.png")
        print("  escrito: " + (output as NSString).deletingLastPathComponent + "/social-preview.png")
        print("  escrito: \(CommandLine.arguments[1])")
        try? Keychain.delete(account: "centinela-shot-t")
        suite.removePersistentDomain(forName: domain)
    }
}
