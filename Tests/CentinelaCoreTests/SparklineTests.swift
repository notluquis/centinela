import Testing

@testable import CentinelaCore

@Suite("Sparkline arithmetic")
struct SparklineTests {
    @Test("An empty series yields no points")
    func empty() {
        #expect(Sparkline.normalize([]).isEmpty)
    }

    @Test("A single point is anchored at the centre")
    func onePoint() {
        let points = Sparkline.normalize([7])
        #expect(points.count == 1)
        #expect(points[0].x == 0.5)
        #expect(points[0].y == 0.5)
    }

    /// The case that matters: with no errors the series is all zeros and `max - min` is 0.
    /// Dividing there yields `NaN`, which Core Graphics does NOT report as an error: it draws
    /// nothing, and the widget looks like it has no data exactly when the system is healthy.
    @Test("A flat series draws a middle line and never NaN", arguments: [[0, 0, 0, 0], [5, 5, 5]])
    func flat(values: [Int]) {
        let points = Sparkline.normalize(values)
        #expect(points.count == values.count)
        for point in points {
            #expect(!point.y.isNaN)
            #expect(point.y == 0.5)
        }
    }

    @Test("A normal series puts the minimum at the bottom and the maximum at the top")
    func normal() {
        let points = Sparkline.normalize([0, 5, 10])
        #expect(points.map(\.y) == [0, 0.5, 1])
        #expect(points.map(\.x) == [0, 0.5, 1])
    }

    @Test("Everything stays inside the unit square")
    func insideUnitSquare() {
        let points = Sparkline.normalize([3, 100, 0, 42, 7])
        #expect(points.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
    }

    @Test("The summary tells zero apart from something")
    func summary() {
        #expect(Sparkline.summary([0, 0], window: .twentyFourHours) == "No errors in the last 24 hours.")
        let withErrors = Sparkline.summary([1, 4], window: .twentyFourHours)
        #expect(withErrors == "5 errors in the last 24 hours, peaking at 4 per interval.")
    }
}
