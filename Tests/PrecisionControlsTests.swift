import XCTest
@testable import SessionPresentation

final class PrecisionControlsTests: XCTestCase {
    func testConfirmedCadenceMaintainsTenMPHWithConsistentWriteLatency() {
        for latency in [0.01, 0.05, 0.2] {
            var clock = MovementPlaybackClock(now: 0), now = 0.0, metres = 0.0
            let speed = SpeedConversion.metresPerSecond(mph: 10)
            for _ in 0..<120 {
                now += clock.delay(now: now)
                metres += speed * clock.advance(now: now)
                now += latency
                clock.confirm(now: now)
            }
            XCTAssertEqual(metres, speed * 60, accuracy: 0.001)
            XCTAssertEqual(SpeedConversion.mph(metresPerSecond: metres / now), 10, accuracy: 0.04)
        }
    }

    func testSlowThenFastWriteCannotSendImmediateCatchUpBurst() {
        for interval in [MovementPlaybackClock.routeInterval, MovementPlaybackClock.joystickInterval] {
            var clock = MovementPlaybackClock(now: 0, interval: interval)
            _ = clock.advance(now: interval)
            clock.confirm(now: interval + 0.05)
            _ = clock.advance(now: 2 * interval)
            let recoveredAt = 2 * interval + 1.2
            clock.confirm(now: recoveredAt)
            let wait = clock.delay(now: recoveredAt)
            XCTAssertEqual(wait, interval, accuracy: 0.00001)
            let movementSeconds = clock.advance(now: recoveredAt + wait)
            XCTAssertEqual(movementSeconds, interval, accuracy: 0.00001)
            let observedMPH = 10 * movementSeconds / (wait + 0.01)
            XCTAssertLessThan(observedMPH, 11)
        }
    }

    func testWritesAroundOneSecondDoNotBurstAfterAQuickConfirmation() {
        let speed = SpeedConversion.metresPerSecond(mph: 60)
        for interval in [MovementPlaybackClock.routeInterval, MovementPlaybackClock.joystickInterval] {
            for latency in [0.999, 1.000, 1.001] {
                var clock = MovementPlaybackClock(now: 0, interval: interval)
                _ = clock.advance(now: interval)
                let acknowledgment = interval + latency
                clock.confirm(now: acknowledgment)
                let delay = clock.delay(now: acknowledgment)
                XCTAssertGreaterThanOrEqual(delay, interval - 0.00101)
                let step = speed * clock.advance(now: acknowledgment + delay)
                XCTAssertEqual(step, speed * interval, accuracy: 0.00001)
                XCTAssertLessThanOrEqual(step / (delay + 0.05), speed)
            }
        }
    }

    func testResumeAndJumpResetPriorConfirmationTiming() {
        var clock = MovementPlaybackClock(now: 0)
        _ = clock.advance(now: 0.5); clock.confirm(now: 0.7)
        clock.reset(now: 100)
        XCTAssertEqual(clock.delay(now: 100), 0.5)
        XCTAssertEqual(clock.advance(now: 100.5), 0.5)
        clock.confirm(now: .nan)
        XCTAssertEqual(clock.delay(now: 100.5), 0.5)
    }

    func testWriteLatencyUsesRemainingTickTimeInsteadOfAnotherFullDelay() {
        var clock = MovementPlaybackClock(now: 0)
        XCTAssertEqual(clock.delay(now: 0), 0.5)
        XCTAssertEqual(clock.advance(now: 0.5), 0.5)
        // A write took 0.2 seconds. The next wait must be only 0.3 seconds.
        clock.confirm(now: 0.7)
        XCTAssertEqual(clock.delay(now: 0.7), 0.3, accuracy: 0.000001)
        XCTAssertEqual(clock.advance(now: 1), 0.5)
    }

    func testConstantCruiseCoversTheRequestedDistanceDespiteShortCommandDelays() {
        var clock = MovementPlaybackClock(now: 0)
        var now = 0.0, metres = 0.0
        for _ in 0..<120 {
            now += clock.delay(now: now)
            let elapsed = clock.advance(now: now)
            metres += RouteMotion.step(speed: 10, target: 10, remaining: 10_000,
                                       mode: .eBike, smooth: false, seconds: elapsed).metres
            now += 0.2
            clock.confirm(now: now)
        }
        XCTAssertEqual(metres, 600, accuracy: 0.00001)
        XCTAssertEqual(now, 60.2, accuracy: 0.00001)
    }

    func testSlowOrdinaryWriteCountsButSuspensionDoesNotCatchUp() {
        var clock = MovementPlaybackClock(now: 0)
        XCTAssertEqual(clock.advance(now: 0.8), 0.8)
        XCTAssertEqual(RouteMotion.step(speed: 10, target: 10, remaining: 100,
                                       mode: .eBike, smooth: false, seconds: 0.8).metres, 8)
        XCTAssertEqual(clock.advance(now: 300), 0.5)
        clock.reset(now: 600)
        XCTAssertEqual(clock.advance(now: 600.5), 0.5)
    }

    func testRouteAndJoystickKeepConfiguredSpeedUnderOrdinaryWriteLatency() {
        let examples: [(TravelMode, Double)] = [(.walk, 3), (.run, 6), (.cycle, 12), (.eBike, 15), (.drive, 60)]
        for latencies in [[0.05, 0.2], [0.35]] {
            for (mode, mph) in examples {
                let speed = SpeedConversion.metresPerSecond(mph: mph)
                let route = cruiseTrace(mode: mode, mph: mph, interval: MovementPlaybackClock.routeInterval, latencies: latencies)
                XCTAssertEqual(route.seconds, 60, accuracy: 0.00001)
                XCTAssertEqual(route.metres, speed * 60, accuracy: 0.00001)
                let joystick = cruiseTrace(mode: mode, mph: mph, interval: MovementPlaybackClock.joystickInterval, latencies: latencies)
                XCTAssertEqual(joystick.metres, speed * joystick.seconds, accuracy: 0.00001)
                if mode == .drive {
                    XCTAssertEqual(route.metres, 1609.344, accuracy: 0.00001)
                    XCTAssertEqual(joystick.metres * 60 / joystick.seconds, 1609.344, accuracy: 0.00001)
                }
            }
        }
    }

    func testCycleEBikeAndDriveCoverTheSameDistanceAtFiveMPH() {
        for mode in [TravelMode.cycle, .eBike, .drive] {
            for interval in [MovementPlaybackClock.routeInterval, MovementPlaybackClock.joystickInterval] {
                let trace = cruiseTrace(mode: mode, mph: 5, interval: interval, latencies: [0.05, 0.2])
                XCTAssertEqual(trace.seconds, 60, accuracy: 0.00001)
                XCTAssertEqual(trace.metres, 134.112, accuracy: 0.00001)
            }
        }
    }

    private func cruiseTrace(mode: TravelMode, mph: Double, interval: Double,
                             latencies: [Double]) -> (seconds: Double, metres: Double) {
        let speed = SpeedConversion.metresPerSecond(mph: mode.clampedSpeedMPH(mph))
        var clock = MovementPlaybackClock(now: 0, interval: interval)
        var readyAt = 0.0, dispatchedAt = 0.0, metres = 0.0, writes = 0
        while true {
            let next = readyAt + clock.delay(now: readyAt)
            if next > 60.000001 { return (dispatchedAt, metres) }
            dispatchedAt = next
            let elapsed = clock.advance(now: next)
            if interval == MovementPlaybackClock.routeInterval {
                metres += RouteMotion.step(speed: speed, target: speed, remaining: 10_000,
                    mode: mode, smooth: false, seconds: elapsed).metres
            } else {
                metres += speed * elapsed
            }
            readyAt = next + latencies[writes % latencies.count]
            clock.confirm(now: readyAt)
            writes += 1
        }
    }

    func testLiveSpeedChangeUsesNewTargetAndRespectsSmoothOption() {
        let instant = RouteMotion.step(speed: 2, target: 12, remaining: 1000, mode: .eBike, smooth: false)
        XCTAssertEqual(instant.speed, 12)
        XCTAssertEqual(instant.metres, 6)
        let smooth = RouteMotion.step(speed: 2, target: 12, remaining: 1000, mode: .eBike, smooth: true)
        XCTAssertLessThan(smooth.speed, 12)
        XCTAssertGreaterThan(smooth.speed, 2)
        let slower = RouteMotion.step(speed: 12, target: 2, remaining: 1000, mode: .eBike, smooth: false)
        XCTAssertEqual(slower.metres, 1)
    }

    func testRouteMotionClampsExactlyAtTheNextBoundary() {
        let speed = SpeedConversion.metresPerSecond(mph: 60)
        for smoothing in [false, true] {
            let step = RouteMotion.step(speed: speed, target: speed, remaining: 2.345,
                                        mode: .drive, smooth: smoothing, seconds: 0.85)
            XCTAssertEqual(step.metres, 2.345)
            XCTAssertEqual(step.speed, 0)
        }
    }

    func testDisplayedSpeedMeasuresConfirmedDistanceOverRealElapsedTime() {
        var samples = RouteSpeedSamples()
        samples.append(metres: 5, seconds: 0.7)
        XCTAssertEqual(samples.metresPerSecond, 5 / 0.7, accuracy: 0.00001)
        samples.append(metres: 5, seconds: 0.5)
        XCTAssertEqual(samples.metresPerSecond, 10 / 1.2, accuracy: 0.00001)
        samples.reset()
        XCTAssertEqual(samples.metresPerSecond, 0)
    }

    func testMarkerAndPolylineUseTheSameProjectionAtHigherLatitudes() throws {
        let a = RoutePoint(latitude: 60, longitude: 10)
        let b = RoutePoint(latitude: 65, longitude: 20)
        let track = try XCTUnwrap(RouteTrack([a, b]))
        let mid = track.point(at: track.length / 2)
        XCTAssertEqual(mid.mercatorY, (a.mercatorY + b.mercatorY) / 2, accuracy: 0.0000001)
        let nearest = try XCTUnwrap(track.nearest(to: mid))
        XCTAssertEqual(nearest.metres, track.length / 2, accuracy: 0.001)
        XCTAssertEqual(nearest.point.latitude, mid.latitude, accuracy: 0.0000001)
    }

    func testMarkerStaysOnSegmentsAroundBothSidesOfACorner() throws {
        let a = RoutePoint(latitude: 37, longitude: -122)
        let b = RoutePoint(latitude: 37, longitude: -121.99)
        let c = RoutePoint(latitude: 37.01, longitude: -121.99)
        let track = try XCTUnwrap(RouteTrack([a, b, c]))
        for distance in stride(from: track.cumulative[1] - 20, through: track.cumulative[1] + 20, by: 1) {
            let point = track.point(at: distance)
            let snap = try XCTUnwrap(track.nearest(to: point, preferredDistance: distance))
            XCTAssertEqual(snap.metres, distance, accuracy: 0.01)
            XCTAssertLessThan(snap.point.distance(to: point), 0.01)
        }
    }

    func testDragToleranceRetainsNearbyBranchUntilFingerClearlyMovesAway() throws {
        let track = try XCTUnwrap(RouteTrack([
            RoutePoint(latitude: 0, longitude: 0), RoutePoint(latitude: 0, longitude: 0.01),
            RoutePoint(latitude: 0.00005, longitude: 0.01), RoutePoint(latitude: 0.00005, longitude: 0)
        ]))
        let nearby = RoutePoint(latitude: 0.00003, longitude: 0.005)
        let exact = try XCTUnwrap(track.nearest(to: nearby))
        let stable = try XCTUnwrap(track.nearest(to: nearby, preferredDistance: track.cumulative[1] / 2,
                                               continuityTolerance: 2))
        XCTAssertGreaterThan(exact.metres, track.cumulative[2])
        XCTAssertLessThan(stable.metres, track.cumulative[1])
        let switched = try XCTUnwrap(track.nearest(to: RoutePoint(latitude: 0.00005, longitude: 0.005),
                                                  preferredDistance: stable.metres, continuityTolerance: 2))
        XCTAssertGreaterThan(switched.metres, track.cumulative[2])
    }

    func testDetailedDrawingRetainsSmallDeliberateMoves() {
        var drawing = RouteDrawing()
        drawing.beginStroke()
        drawing.append(RoutePoint(latitude: 0, longitude: 0), spacing: 0.05)
        drawing.append(RoutePoint(latitude: 0, longitude: 0.000005), spacing: 0.05)
        drawing.endStroke()
        XCTAssertEqual(drawing.points.count, 2)
        drawing.undo()
        XCTAssertTrue(drawing.points.isEmpty)
    }

    func testDisplayPreferencesAreIndependentAndOldActivitiesStillDecode() throws {
        let now = Date()
        var state = SessionSnapshot(phase: .active, startedAt: now, lastConfirmedAt: now,
                                    expiresAt: now.addingTimeInterval(12), place: nil, lowPower: false,
                                    journey: JourneyActivity(state: .moving, progress: 0.2, remainingMetres: 100,
                                                             estimatedArrival: now.addingTimeInterval(10)))
        state.islandPlace = "Selected place"
        state.lockScreenShowsProgress = false
        state.islandShowsProgress = true
        state.islandShowsTimer = false
        XCTAssertNil(state.place)
        XCTAssertNotNil(state.islandPlace)
        XCTAssertNil(state.visibleJourney(onIsland: false, at: now))
        XCTAssertNotNil(state.visibleJourney(onIsland: true, at: now))
        XCTAssertNil(state.visibleJourney(onIsland: true, at: now.addingTimeInterval(13)))
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(SessionSnapshot.self, from: data), state)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["islandPlace", "lockScreenShowsProgress", "islandShowsProgress", "islandShowsTimer"] { old.removeValue(forKey: key) }
        let restored = try JSONDecoder().decode(SessionSnapshot.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(restored.islandPlace)
        XCTAssertNotNil(restored.visibleJourney(onIsland: false, at: now))
        XCTAssertLessThan(data.count, 4096)
    }
}
