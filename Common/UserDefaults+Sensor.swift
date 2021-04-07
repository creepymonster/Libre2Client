//
//  UserDefaults+Sensor.swift
//  LibreDirectClient
//
//  Created by Reimar Metzen on 05.03.21.
//  Copyright © 2021 Mark Wilson. All rights reserved.
// 

import Foundation

extension UserDefaults {
    private enum Key: String, CaseIterable {
        case sensorUnlockCount = "com.LibreDirectClient.sensor.sensorUnlockCount"
        case sensorUID = "com.LibreDirectClient.sensor.sensorUID"
        case sensorPatchInfo = "com.LibreDirectClient.sensor.sensorPatchInfo"
        case sensorCalibration = "com.LibreDirectClient.sensor.sensorCalibrationInfo"
        case sensorState = "com.LibreDirectClient.sensor.sensorState"
        case lastSensorAge = "com.LibreDirectClient.sensor.lastSensorAge"
    }

    var sensorUnlockCount: UInt16? {
        get {
            return UInt16(integer(forKey: Key.sensorUnlockCount.rawValue))
        }
        set {
            if let newValue = newValue {
                set(newValue, forKey: Key.sensorUnlockCount.rawValue)
            } else {
                removeObject(forKey: Key.sensorUnlockCount.rawValue)
            }
        }
    }

    var sensorUID: Data? {
        get {
            return object(forKey: Key.sensorUID.rawValue) as? Data
        }
        set {
            if let newValue = newValue {
                set(newValue, forKey: Key.sensorUID.rawValue)
            } else {
                removeObject(forKey: Key.sensorUID.rawValue)
            }
        }
    }

    var sensorPatchInfo: Data? {
        get {
            return object(forKey: Key.sensorPatchInfo.rawValue) as? Data
        }
        set {
            if let newValue = newValue {
                set(newValue, forKey: Key.sensorPatchInfo.rawValue)
            } else {
                removeObject(forKey: Key.sensorPatchInfo.rawValue)
            }
        }
    }

    var sensorState: SensorState? {
        get {
            if let saved = object(forKey: Key.sensorState.rawValue) as? Data {
                let decoder = JSONDecoder()

                if let loaded = try? decoder.decode(SensorState.self, from: saved) {
                    return loaded
                }
            }

            return nil
        }
        set {
            let encoder = JSONEncoder()
            if let encoded = try? encoder.encode(newValue) {
                set(encoded, forKey: Key.sensorState.rawValue)
            } else {
                removeObject(forKey: Key.sensorState.rawValue)
            }
        }
    }

    var sensorCalibration: SensorCalibration? {
        get {
            if let saved = object(forKey: Key.sensorCalibration.rawValue) as? Data {
                let decoder = JSONDecoder()

                if let loaded = try? decoder.decode(SensorCalibration.self, from: saved) {
                    return loaded
                }
            }

            return nil
        }
        set {
            let encoder = JSONEncoder()
            if let encoded = try? encoder.encode(newValue) {
                set(encoded, forKey: Key.sensorCalibration.rawValue)
            } else {
                removeObject(forKey: Key.sensorCalibration.rawValue)
            }
        }
    }

    var lastSensorAge: Int? {
        get {
            return integer(forKey: Key.lastSensorAge.rawValue)
        }
        set {
            if let newValue = newValue {
                set(newValue, forKey: Key.lastSensorAge.rawValue)
            } else {
                removeObject(forKey: Key.lastSensorAge.rawValue)
            }
        }
    }

    var sensorType: SensorType? {
        get {
            if let patchInfo = UserDefaults.standard.sensorPatchInfo {
                return SensorType(patchInfo: patchInfo)
            }

            return nil
        }
    }

    var sensorRegion: SensorRegion? {
        get {
            if let patchInfo = UserDefaults.standard.sensorPatchInfo {
                return SensorRegion(patchInfo: patchInfo)
            }

            return nil
        }
    }

}
