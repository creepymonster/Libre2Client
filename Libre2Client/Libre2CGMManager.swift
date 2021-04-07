//
//  Libre2CGMManager.swift
//  Libre2Client
//
//  Created by Julian Groen on 11/05/2020.
//  Copyright © 2020 Julian Groen. All rights reserved.
//

import Foundation
import LoopKit
import LoopKitUI
import HealthKit

public protocol Libre2CGMManagerDelegate: class {
    func cgmManagerUpdate()
}

public class Libre2CGMManager: CGMManager, SensorManagerDelegate {
    private lazy var bluetoothManager: SensorManager? = SensorManager()

    public static let localizedTitle = LocalizedString("Libre 2", comment: "")
    public static var managerIdentifier = "Libre2Client"
    public let appURL: URL? = nil
    public let providesBLEHeartbeat = true
    public var managedDataInterval: TimeInterval? = nil
    public let delegate = WeakSynchronizedDelegate<CGMManagerDelegate>()
    public weak var updateDelegate: Libre2CGMManagerDelegate?

    public var shouldSyncToRemoteService: Bool {
        return UserDefaults.standard.glucoseSync
    }

    public var sensorState: SensorDisplayable? {
        return latestReading
    }

    public private(set) var latestReading: Glucose? {
        didSet {
            if let currentGlucose = latestReading {
                update(glucose: Int(currentGlucose.glucose))
            }
        }
    }

    public var cgmManagerDelegate: CGMManagerDelegate? {
        get {
            return delegate.delegate
        }
        set {
            delegate.delegate = newValue
        }
    }

    public var delegateQueue: DispatchQueue! {
        get {
            return delegate.queue
        }
        set {
            delegate.queue = newValue
        }
    }

    public var rawState: CGMManager.RawStateValue {
        return [:]
    }

    public init() {
        bluetoothManager?.delegate = self
    }

    public required convenience init?(rawState: RawStateValue) {
        self.init()
    }

    deinit {
        updateDelegate = nil
        
        bluetoothManager?.disconnect(stayConnected: false)
        bluetoothManager?.delegate = nil
    }

    public func resetConnection() {
        bluetoothManager?.resetConnection()
        update()
    }

    public func fetchNewDataIfNeeded(_ completion: @escaping (CGMResult) -> Void) {
        completion(.noData)
    }

    // MARK: - SensorManagerDelegate

    public func sensorManager(_ sensor: Sensor?, didChangeSensorConnectionState state: SensorConnectionState) {
        update()
    }

    public func sensorManager(_ sensor: Sensor?, didUpdateSensorData data: SensorData) {
        NotificationManager.sendSensorExpireNotificationIfNeeded(data)

        guard let glucose = readingToGlucose(data), glucose.count > 0 else {
            delegateQueue.async {
                self.cgmManagerDelegate?.cgmManager(self, didUpdateWith: .noData)
            }

            return
        }

        let startDate = latestReading?.startDate.addingTimeInterval(1)
        let glucoseSamples = glucose.filterDateRange(startDate, nil).filter({ $0.isStateValid }).map { glucose -> NewGlucoseSample in
            return NewGlucoseSample(date: glucose.startDate, quantity: glucose.quantity, isDisplayOnly: false, syncIdentifier: glucose.date.timeIntervalSince1970.description, device: device)
        }

        delegateQueue.async {
            self.cgmManagerDelegate?.cgmManager(self, didUpdateWith: (glucoseSamples.isEmpty ? .noData : .newData(glucoseSamples)))
        }
        
        latestReading = glucose.filter({ $0.isStateValid }).max { $0.startDate < $1.startDate }
    }
    
    private func update(glucose: Int? = nil) {
        DispatchQueue.main.async {
            if let glucose = glucose {
                UIApplication.shared.applicationIconBadgeNumber = glucose
            }
            
            self.updateDelegate?.cgmManagerUpdate()
        }
    }

    private func readingToGlucose(_ data: SensorData) -> [Glucose]? {
        var entries = [Glucose]()

        var lastGlucose: Glucose? = nil
        for measurement in data.trend {
            var glucose = Glucose(glucose: Double(measurement.value), trend: .flat, wearTimeMinutes: data.wearTimeMinutes, state: UserDefaults.standard.sensorState ?? .unknown, date: measurement.date)
            glucose.trend = TrendCalculation.calculateTrend(current: glucose, last: lastGlucose)

            entries.append(glucose)
            lastGlucose = glucose
        }

        return entries.reversed()
    }

    public var debugDescription: String {
        return [
            "## \(String(describing: type(of: self)))",
            "latestReading: \(String(describing: latestReading))",
            "connectionState: \(String(describing: connection))",
            "shouldSyncToRemoteService: \(String(describing: shouldSyncToRemoteService))",
            "providesBLEHeartbeat: \(String(describing: providesBLEHeartbeat))",
            ""
        ].joined(separator: "\n")
    }
}

// MARK: - Libre2CGMManager

extension Libre2CGMManager {  
    public var manufacturer: String? {
        return bluetoothManager?.sensor?.manufacturer
    }

    public var connection: String? {
        return bluetoothManager?.state.rawValue
    }

    public var identifier: String? {
        return bluetoothManager?.sensor?.identifier
    }

    public var hardwareVersion: String? {
        return UserDefaults.standard.sensorType?.rawValue
    }

    public var device: HKDevice? {
        return HKDevice(
            name: "Libre2Client",
            manufacturer: manufacturer,
            model: hardwareVersion,
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: nil,
            localIdentifier: identifier,
            udiDeviceIdentifier: nil
        )
    }
}

extension UserDefaults {
    public var debugModeActivated: Bool {
        return false
    }
}
