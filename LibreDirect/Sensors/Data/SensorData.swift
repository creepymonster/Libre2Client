//
//  SensorData.swift
//  LibreDirectClient
//
//  Created by Julian Groen on 11/05/2020.
//  Copyright © 2020 Julian Groen. All rights reserved.
//

import Foundation

public struct SensorData {
    let bytes: Data
    let sensorUID: Data
    let patchInfo: Data
    let calibration: SensorCalibration
    let wearTimeMinutes: Int
    let trend: [SensorMeasurement]
    let history: [SensorMeasurement]

    init?(bytes: Data, sensorUID: Data, patchInfo: Data, calibration: SensorCalibration, wearTimeMinutes: Int, trend: [SensorMeasurement], history: [SensorMeasurement]) {
        self.bytes = bytes
        self.sensorUID = sensorUID
        self.patchInfo = patchInfo
        self.calibration = calibration
        self.wearTimeMinutes = wearTimeMinutes
        self.trend = trend
        self.history = history
    }

    func trend(reversed: Bool = false) -> [SensorMeasurement] {
        return (reversed ? trend.reversed() : trend)
    }

    func history(reversed: Bool = false) -> [SensorMeasurement] {
        return (reversed ? history.reversed() : history)
    }

    public var description: String {
        return "(\(bytes.hex))"
    }
}
