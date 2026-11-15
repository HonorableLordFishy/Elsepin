#if !ELSEPIN_UI_TESTING || !targetEnvironment(simulator)
#error("Map validation probes must never compile into a device app")
#endif
import SwiftUI

/// Records the production map's actual filtered pins. Counters advance only in
/// its continuous callback, never in its settled callback or synthetic engine.
@MainActor final class ValidationPinVisibilityProbe: ObservableObject {
    @Published var width: Double = 0
    @Published var pins = 0
    @Published var liveShows = 0
    @Published var liveHides = 0
    @Published var settled = 0
    func record(width: Double?, pins: Int, continuous: Bool) {
        if continuous {
            if self.pins == 0 && pins > 0 { liveShows += 1 }
            if self.pins > 0 && pins == 0 { liveHides += 1 }
        }
        let miles = (width ?? 0) / SavedPinVisibility.metersPerMile
        if self.width != miles { self.width = miles }
        if self.pins != pins { self.pins = pins }
    }
    func didSettle() { settled += 1 }
}

struct ValidationPinVisibilityControls: View {
    @ObservedObject var probe: ValidationPinVisibilityProbe
    let move: (String) -> Void
    var body: some View {
        VStack(spacing: 2) {
            Text("PIN TEST ONLY")
            Text(String(format: "%.3f", probe.width)).accessibilityIdentifier("validation.pinWidth")
            Text(String(probe.pins)).accessibilityIdentifier("validation.pinCount")
            Text(String(probe.liveShows)).accessibilityIdentifier("validation.pinLiveShows")
            Text(String(probe.liveHides)).accessibilityIdentifier("validation.pinLiveHides")
            Text(String(probe.settled)).accessibilityIdentifier("validation.pinSettled")
            ForEach(["near", "edge", "rotate"], id: \.self) { action in
                Button(action) { move(action) }.accessibilityIdentifier("validation.pin." + action)
                    .frame(minWidth: 54, minHeight: 44)
            }
        }.font(.system(size: 10)).padding(4).background(.yellow).foregroundStyle(.black)
    }
}
