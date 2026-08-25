import Foundation
import CoreLocation

enum LocationAuth: Equatable {
    case notDetermined, denied, authorized

    static func from(_ status: CLAuthorizationStatus) -> LocationAuth {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        case .authorized, .authorizedAlways: return .authorized
        @unknown default: return .denied
        }
    }
}

@MainActor
final class LocationPermission: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var status: LocationAuth = .notDetermined
    var onChange: (@MainActor (LocationAuth) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        status = LocationAuth.from(manager.authorizationStatus)
    }

    func requestIfNeeded() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let mapped = LocationAuth.from(manager.authorizationStatus)
        Task { @MainActor in
            self.status = mapped
            self.onChange?(mapped)
        }
    }
}
