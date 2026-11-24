#if !ELSEPIN_UI_TESTING || !targetEnvironment(simulator)
#error("This fixture is for the isolated simulator app only")
#endif
import SwiftUI

struct ValidationJoystickPresets: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @State private var status = "Checking joystick speeds"

    var body: some View {
        Text(status).task {
            session.changeTravelMode(.walk)
            session.setSpeedMPH(2, for: .walk)
            session.setUsualSpeedMPH(4, for: .walk)
            guard session.teleport(to: ValidationFixture.points[0], pairing: pairing) else { return }
            for _ in 0..<100 where session.effectivePhase != .active || session.isBusy {
                try? await Task.sleep(for: .milliseconds(75))
            }
            guard session.startJoystick(pairing: pairing) == nil,
                  session.speedMPH(for: .walk) == 4 else { return }
            session.setSpeedMPH(3, for: .walk)
            guard session.speedMPH(for: .walk) == 3, session.usualSpeedMPH(for: .walk) == 4 else { return }
            session.setUsualSpeedMPH(5, for: .walk)
            guard session.speedMPH(for: .walk) == 5 else { return }
            session.setUsualSpeedMPH(22, for: .drive)
            session.changeTravelMode(.drive)
            guard session.speedMPH(for: .drive) == 22 else { return }
            session.setSpeedMPH(16, for: .drive)
            session.stopJoystick()
            guard session.startJoystick(pairing: pairing) == nil,
                  session.speedMPH(for: .drive) == 22 else { return }
            status = "Joystick presets passed"
        }
    }
}
