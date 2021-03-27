//
//  Sensor+Abbot.swift
//  Libre2Client
//
//  Created by Reimar Metzen on 05.03.21.
//  Copyright © 2021 Mark Wilson. All rights reserved.
//

import CoreBluetooth
import Foundation
import UIKit
import CoreNFC

@available(iOS 14.0, *)
public class Libre2Direct: Sensor & LibreNFCDelegate {
    private static let unknownOutput = "-"
    private static let expectedBufferSize = 46
    private static let maxWaitForpacketInSeconds = 60.0

    public var manufacturer: String = "Abbot"

    public var serviceCharacteristicsUuid: [CBUUID] = [CBUUID(string: "FDE3")]
    public var writeCharacteristicUuid: CBUUID = CBUUID(string: "F001")
    public var readCharacteristicUuid: CBUUID = CBUUID(string: "F002")

    var libreNFC: LibreNFC?

    required init() {
        super.init()

        Log.debug("Init sensor", log: .sensor)
    }

    public func resetConnection() {
        Log.debug("Reset connection", log: .sensor)

        UserDefaults.standard.sensorUID = nil
        UserDefaults.standard.sensorPatchInfo = nil
        UserDefaults.standard.sensorCalibration = nil
        UserDefaults.standard.sensorState = nil
    }

    public func received(sensorUID: Data, patchInfo: Data) {
        UserDefaults.standard.sensorUID = sensorUID
        UserDefaults.standard.sensorPatchInfo = patchInfo

        Log.debug("SensorUID: \(sensorUID.hex)", log: .sensor)
        Log.debug("PatchInfo: \(patchInfo.hex)", log: .sensor)
    }

    public func received(fram: Data) {
        guard let sensorUID = UserDefaults.standard.sensorUID, let patchInfo = UserDefaults.standard.sensorPatchInfo else {
            return
        }

        let data = PreLibre.decryptFRAM(sensorUID, patchInfo, fram)

        UserDefaults.standard.sensorCalibration = Libre2.readFactoryCalibration(bytes: data)
        UserDefaults.standard.sensorState = SensorState(bytes: data)

        Log.debug("SensorCalibration: \(UserDefaults.standard.sensorCalibration?.description ?? Libre2Direct.unknownOutput)", log: .sensor)
        Log.debug("SensorState: \(UserDefaults.standard.sensorState?.description ?? Libre2Direct.unknownOutput)", log: .sensor)
    }

    public func streamingEnabled(successful: Bool) {
        Log.debug("StreamingEnabled: \(successful.description)", log: .sensor)

        if successful {
            UserDefaults.standard.sensorUnlockCount = 0
        }
    }
    
    public func finished() {
        Log.debug("Finished NFC", log: .sensor)
        
        libreNFC = nil
    }

    public func canSupportPeripheral(_ peripheral: CBPeripheral, _ advertisementData: [String: Any]) -> Bool {
        guard let sensorUID = UserDefaults.standard.sensorUID else {
            return false
        }

        if let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            if manufacturerData.count == 8 {
                var foundUID = manufacturerData.subdata(in: 2..<8)
                foundUID.append(contentsOf: [0x07, 0xe0])

                Log.debug(peripheral.name?.lowercased() ?? Libre2Direct.unknownOutput, log: .sensor)
                Log.debug(foundUID.hex, log: .sensor)
                Log.debug(sensorUID.hex, log: .sensor)

                return foundUID == sensorUID && peripheral.name?.lowercased().starts(with: "abbott") ?? false
            }
        }

        return false
    }
    
    public func setupConnectionIfNeeded() {
        Log.debug("Setup connection", log: .sensor)
        
        if UserDefaults.standard.sensorUID == nil || UserDefaults.standard.sensorPatchInfo == nil || UserDefaults.standard.sensorCalibration == nil || UserDefaults.standard.sensorState == nil {
            scanNfc()
        }
    }

    public func canConnect() -> Bool {
        if let _ = UserDefaults.standard.sensorUID, let _ = UserDefaults.standard.sensorPatchInfo, let _ = UserDefaults.standard.sensorCalibration, let _ = UserDefaults.standard.sensorState {
            Log.debug("Can connect: true", log: .sensor)
            
            return true
        }

        Log.debug("Can connect: false", log: .sensor)
        
        return false
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
        Log.debug(service.uuid.uuidString, log: .sensor)

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
        Log.debug(characteristic.uuid.uuidString, log: .sensor)

        reset()
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic) {
        if let value = characteristic.value {
            if value.count == 20 {
                Log.debug("1. block: \(value.hex)", log: .sensor)
            } else if value.count == 18 {
                Log.debug("2. block: \(value.hex)", log: .sensor)
            } else if value.count == 8 {
                Log.debug("3. block: \(value.hex)", log: .sensor)
            }

            // add new value to rxBuffer
            rxBuffer.append(value)

            if rxBuffer.count == Libre2Direct.expectedBufferSize {
                guard let sensorUID = UserDefaults.standard.sensorUID, let patchInfo = UserDefaults.standard.sensorPatchInfo, let sensorCalibration = UserDefaults.standard.sensorCalibration, let sensorType = UserDefaults.standard.sensorType else {
                    return
                }

                guard sensorType == .libre2 else {
                    Log.debug("SensorType: \(sensorType.description)", log: .sensor)
                    return
                }

                do {
                    let decryptedBLE = Data(try Libre2.decryptBLE(sensorUID: sensorUID, data: rxBuffer))
                    let measurements = Libre2.parseBLEData(decryptedBLE, calibration: sensorCalibration)

                    for trendMeasurement in measurements.trend {
                        Log.debug("Trend: \(trendMeasurement.description)", log: .sensor)
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
        Log.debug(characteristic.uuid.uuidString, log: .sensor)

        if characteristic.uuid == writeCharacteristicUuid {
            peripheral.setNotifyValue(true, for: readCharacteristic!)
        }
    }

    private func scanNfc() {
        Log.debug("Scan NFC", log: .sensor)

        if libreNFC == nil {
            libreNFC = LibreNFC(libreNFCDelegate: self)
            libreNFC?.startSession()
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
        Log.debug("UnlockCount: \(unlockCount.description)", log: .sensor)

        let unlockPayLoad = Data(Libre2.streamingUnlockPayload(sensorUID: sensorUID, info: patchInfo, enableTime: 42, unlockCount: unlockCount))
        Log.debug("UnlockPayLoad: \(unlockPayLoad.hex)", log: .sensor)

        _ = writeValueToPeripheral(peripheral, value: unlockPayLoad, type: .withResponse)
    }
}
