//
//  Sensor+Abbot.swift
//  LibreDirectClient
//
//  Created by Reimar Metzen on 05.03.21.
//  Copyright © 2021 Mark Wilson. All rights reserved.
//

import Foundation
import CoreBluetooth

public class Libre2Sensor: Sensor {
    private static let unknownOutput = "-"
    private static let expectedBufferSize = 46
    private static let maxWaitForpacketInSeconds = 60.0

    public var manufacturer: String = "Abbot"

    public var serviceCharacteristicsUuid: [CBUUID] = [CBUUID(string: "FDE3")]
    public var writeCharacteristicUuid: CBUUID = CBUUID(string: "F001")
    public var readCharacteristicUuid: CBUUID = CBUUID(string: "F002")

    required init(with identifier: String) {
        super.init(with: identifier)

        Log.debug("Init sensor", log: .sensor)
    }

    public func peripheral(_ peripheral: CBPeripheral) {
        Log.debug("Did discover services", log: .sensor)

        if let services = peripheral.services {
            for service in services {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService) {
        Log.debug("Did discover characteristics, service: \(service.uuid.uuidString)", log: .sensor)

        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                if characteristic.uuid == readCharacteristicUuid {
                    Log.debug(characteristic.uuid.uuidString, log: .sensor)

                    readCharacteristic = characteristic
                }

                if characteristic.uuid == writeCharacteristicUuid {
                    Log.debug(characteristic.uuid.uuidString, log: .sensor)

                    writeCharacteristic = characteristic
                    unlock(peripheral)
                }
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic) {
        Log.debug("Did update notification state, characteristic: \(characteristic.uuid.uuidString)", log: .sensor)

        reset()
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic) {
        if let value = characteristic.value {
            if value.count == 20 {
                Log.debug("Did update value, 1. block: \(value.hex)", log: .sensor)
            } else if value.count == 18 {
                Log.debug("Did update value, 2. block: \(value.hex)", log: .sensor)
            } else if value.count == 8 {
                Log.debug("Did update value, 3. block: \(value.hex)", log: .sensor)
            }

            // add new value to rxBuffer
            rxBuffer.append(value)

            if rxBuffer.count == Libre2Sensor.expectedBufferSize {
                guard let sensorUID = UserDefaults.standard.sensorUID, let patchInfo = UserDefaults.standard.sensorPatchInfo, let sensorCalibration = UserDefaults.standard.sensorCalibration, let sensorType = UserDefaults.standard.sensorType else {
                    return
                }

                guard sensorType == .libre2 else {
                    Log.debug("Did update value, SensorType: \(sensorType.description)", log: .sensor)
                    return
                }

                do {
                    let decryptedBLE = Data(try Libre2.decryptBLE(sensorUID: sensorUID, data: rxBuffer))
                    let measurements = Libre2.parseBLEData(decryptedBLE, calibration: sensorCalibration)

                    for historyMeasurement in measurements.history {
                        Log.debug("Did update value, History: \(historyMeasurement.description)", log: .sensor)
                    }
                    
                    for trendMeasurement in measurements.trend {
                        Log.debug("Did update value, Trend: \(trendMeasurement.description)", log: .sensor)
                    }

                    let sensorData = SensorData(bytes: decryptedBLE, sensorUID: sensorUID, patchInfo: patchInfo, calibration: sensorCalibration, wearTimeMinutes: measurements.wearTimeMinutes, trend: measurements.trend, history: measurements.history)
                    if let sensorData = sensorData {
                        delegate?.sensorManager(self, didUpdateSensorData: sensorData)
                    }

                    reset()
                } catch {
                    reset()
                }
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic) {
        Log.debug("Did write value, characteristic: \(characteristic.uuid.uuidString)", log: .sensor)

        if characteristic.uuid == writeCharacteristicUuid {
            peripheral.setNotifyValue(true, for: readCharacteristic!)
        }
    }

    private func unlock(_ peripheral: CBPeripheral) {
        Log.debug("Unlock", log: .sensor)

        guard let sensorUID = UserDefaults.standard.sensorUID else {
            return
        }

        guard let patchInfo = UserDefaults.standard.sensorPatchInfo else {
            return
        }

        let unlockCount = (UserDefaults.standard.sensorUnlockCount ?? 0) + 1
        UserDefaults.standard.sensorUnlockCount = unlockCount
        Log.debug("Unlock, UnlockCount: \(unlockCount.description)", log: .sensor)

        let unlockPayLoad = Data(Libre2.streamingUnlockPayload(sensorUID: sensorUID, info: patchInfo, enableTime: 42, unlockCount: unlockCount))
        Log.debug("Unlock, UnlockPayLoad: \(unlockPayLoad.hex)", log: .sensor)

        _ = writeValueToPeripheral(peripheral, value: unlockPayLoad, type: .withResponse)
    }
}
