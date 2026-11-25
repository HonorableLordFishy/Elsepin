import Network
import SwiftUI

struct JourneyCard: View {
    var showsControls = true
    @Environment(\.dynamicTypeSize) private var typeSize
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var planner: RoutePlanner

    var body: some View {
        if let route = session.activeRoute, let trip = session.journey {
            ForegroundTimeline { context in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        ShiftRowIcon(symbol: session.travelMode.icon)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(route.destination.name).font(.system(.title3, design: .rounded, weight: .bold)).lineLimit(2)
                            Text(trip.state.title).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { planner.isPresented = true } label: {
                            Image(systemName: "list.bullet").frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .accessibilityLabel("Route details and directions")
                    }
                    ProgressView(value: trip.fraction).tint(LocusTheme.accent)
                        .accessibilityLabel("Journey progress")
                    if let note = route.source.playbackNote(mode: session.travelMode) {
                        Text(note).font(.caption).foregroundStyle(LocusTheme.statusWarn)
                    }
                    let metrics = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .top))
                    metrics {
                        metric(JourneyText.distance(trip.remainingMetres), caption: "remaining")
                        Spacer()
                        metric(JourneyText.duration(session.journeyRemainingSeconds), caption: "est. time + stops")
                        Spacer()
                        VStack(alignment: .leading, spacing: 3) {
                            if let seconds = session.journeyRemainingSeconds {
                                Text(context.addingTimeInterval(seconds), style: .time)
                                    .font(.headline.monospacedDigit())
                            } else { Text("—").font(.headline) }
                            Text("est. arrival").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if trip.state == .arrived {
                        Text("Route finished. Last location sent is here; simulation may remain until Stop spoofing succeeds.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if session.effectivePhase != .active {
                        Text("Waiting for a fresh connection confirmation. ETA is unavailable.")
                            .font(.caption).foregroundStyle(LocusTheme.statusWarn)
                    }
                    if showsControls { RoutePlaybackControls() }
                }
            }
        }
    }

    private func metric(_ value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.headline.monospacedDigit())
            Text(caption).font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// Shared labels and behavior on the map and in the route sheet.
struct RoutePlaybackControls: View {
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dynamicTypeSize) private var typeSize
    var compact = false
    var includeStopSpoofing = false
    var hidePause = false
    var onStop: () -> Void = {}

    private var pauseTitle: String {
        if session.journey?.state == .pausing { return "Pausing…" }
        return session.routePaused ? "Continue route" : "Pause route"
    }

    var body: some View {
        VStack(spacing: 8) {
            ArrivalControls()
            RouteExtrasControls()
            if !compact && session.routeRerouting {
                HStack {
                    ProgressView("Finding a new route…")
                    Spacer()
                    Button { session.cancelReroute() } label: {
                        Text("Cancel").padding(.horizontal, 8).frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }.font(.caption)
            }
            let controlLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
            controlLayout {
                if !hidePause && session.routeActive && !session.routeStopping {
                    Button { session.toggleRoutePause() } label: {
                        Label(pauseTitle, systemImage: session.routePaused ? "play.fill" : "pause.fill")
                            .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 46).contentShape(Rectangle())
                    }
                    .buttonStyle(ShiftActionStyle())
                    .disabled(!session.canEditRouteMovement || session.journey?.state == .pausing || (session.routePaused && session.effectivePhase != .active))
                }
                Button {
                    session.stopRoute()
                    onStop()
                } label: {
                    Label(session.routeStopping ? "Ending route…" : "End route", systemImage: "stop.fill")
                        .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 46).contentShape(Rectangle())
                }
                .buttonStyle(ShiftActionStyle(kind: .secondary))
                .disabled(session.isBusy || session.routeStopping)
                if includeStopSpoofing && session.hasSession {
                    StopSpoofingButton {
                        Label(session.stopButtonTitle, systemImage: "location.slash")
                            .font(.caption.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 46).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).foregroundStyle(LocusTheme.danger)
                    .background(LocusTheme.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    .disabled(session.status == .stopping)
                }
            }
            if !compact && !session.routeStopping {
                Text("End route holds the last location. Stop spoofing returns control to your iPhone.")
                    .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            if !compact && session.routeStopping {
                Text("Waiting for the last location update to finish.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct StopNetworkPath: Sendable {
    let status: NWPath.Status
    let usesCellular: Bool
    let usesWiFi: Bool
    let usesEthernet: Bool

    var usesCellularAlone: Bool {
        status == .satisfied && usesCellular && !usesWiFi && !usesEthernet
    }
}

#if ELSEPIN_UI_TESTING && targetEnvironment(simulator)
private struct StopNetworkPathOverrideKey: EnvironmentKey {
    static let defaultValue: StopNetworkPath? = nil
}

extension EnvironmentValues {
    var stopNetworkPathOverride: StopNetworkPath? {
        get { self[StopNetworkPathOverrideKey.self] }
        set { self[StopNetworkPathOverrideKey.self] = newValue }
    }
}
#endif

struct StopSpoofingButton<Label: View>: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.scenePhase) private var scenePhase
    #if ELSEPIN_UI_TESTING && targetEnvironment(simulator)
    @Environment(\.stopNetworkPathOverride) private var pathOverride
    #else
    private let pathOverride: StopNetworkPath? = nil
    #endif
    @State private var monitor: NWPathMonitor?
    @State private var pendingStop: Int?
    let isVisible: Bool
    let label: () -> Label

    init(isVisible: Bool = true, @ViewBuilder label: @escaping () -> Label) {
        self.isVisible = isVisible
        self.label = label
    }

    private var observesNetwork: Bool {
        isVisible && scenePhase == .active && session.hasSession && pathOverride == nil
    }

    private var canWarn: Bool {
        isVisible && scenePhase == .active && session.isSpoofing && session.simulated != nil && !session.joystickActive
    }

    private var cellularPath: Bool {
        if let pathOverride { return pathOverride.usesCellularAlone }
        guard let path = monitor?.currentPath else { return false }
        return StopNetworkPath(status: path.status, usesCellular: path.usesInterfaceType(.cellular),
                               usesWiFi: path.usesInterfaceType(.wifi),
                               usesEthernet: path.usesInterfaceType(.wiredEthernet)).usesCellularAlone
    }

    var body: some View {
        Button {
            if canWarn && cellularPath { pendingStop = session.commandGeneration }
            else { session.stop(pairing: pairing) }
        } label: { label() }
        .alert("Stop spoofing?", isPresented: Binding(
            get: { pendingStop != nil },
            set: { if !$0 { pendingStop = nil } }
        ), presenting: pendingStop) { generation in
            Button("Keep spoofing", role: .cancel) { pendingStop = nil }
            Button("Stop spoofing", role: .destructive) {
                pendingStop = nil
                guard session.commandGeneration == generation, session.hasSession, !session.isStopping else { return }
                session.stop(pairing: pairing)
            }
        } message: { _ in
            Text("You’re on cellular. Starting again may require Wi-Fi or a hotspot.")
        }
        .onAppear { updateMonitor() }
        .onChange(of: observesNetwork) { _, _ in updateMonitor() }
        .onChange(of: session.commandGeneration) { _, _ in pendingStop = nil }
        .onChange(of: canWarn) { _, canWarn in if !canWarn { pendingStop = nil } }
        .onDisappear {
            pendingStop = nil
            monitor?.cancel()
            monitor = nil
        }
    }

    private func updateMonitor() {
        guard observesNetwork else {
            monitor?.cancel()
            monitor = nil
            return
        }
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.start(queue: DispatchQueue(label: "locus.stop.network", qos: .utility))
        self.monitor = monitor
    }
}
