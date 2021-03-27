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
import os.log

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

        os_log("Init sensor", log: .sensor)
    }

    public func resetConnection() {
        os_log("Reset connection", log: .sensor)

        UserDefaults.standard.sensorUID = nil
        UserDefaults.standard.sensorPatchInfo = nil
        UserDefaults.standard.sensorCalibration = nil
        UserDefaults.standard.sensorState = nil
    }

    public func received(sensorUID: Data, patchInfo: Data) {
        UserDefaults.standard.sensorUID = sensorUID
        UserDefaults.standard.sensorPatchInfo = patchInfo

        os_log("Received, sensorUID: %{public}s", log: .sensor, sensorUID.hex)
        os_log("Received, sensorPatchInfo: %{public}s", log: .sensor, patchInfo.hex)
    }

    public func received(fram: Data) {
        guard let sensorUID = UserDefaults.standard.sensorUID, let patchInfo = UserDefaults.standard.sensorPatchInfo else {
            return
        }

        let data = PreLibre.decryptFRAM(sensorUID, patchInfo, fram)

        UserDefaults.standard.sensorCalibration = Libre2.readFactoryCalibration(bytes: data)
        UserDefaults.standard.sensorState = SensorState(bytes: data)

        os_log("Received, calibration: %{public}s", log: .sensor, UserDefaults.standard.sensorCalibration?.description ?? Libre2Direct.unknownOutput)
        os_log("Received, state: %{public}s", log: .sensor, UserDefaults.standard.sensorState?.description ?? Libre2Direct.unknownOutput)
    }

    public func streamingEnabled(successful: Bool) {
        os_log("Streaming enabled: %{public}s", log: .sensor, successful)

        if successful {
            UserDefaults.standard.sensorUnlockCount = 0
        }
    }
    
    public func finished() {
        os_log("Finished NFC", log: .sensor)
        
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

                os_log("Can support peripheral, name: %{public}s", log: .sensor, peripheral.name?.lowercased() ?? Libre2Direct.unknownOutput)
                os_log("Can support peripheral, foundUID: %{public}s", log: .sensor, foundUID.hex)
                os_log("Can support peripheral, sensorUID: %{public}s", log: .sensor, sensorUID.hex)

                return foundUID == sensorUID && peripheral.name?.lowercased().starts(with: "abbott") ?? false
            }
        }

        return false
    }
    
    public func setupConnectionIfNeeded() {
        os_log("Setup connection", log: .sensor)
        
        if UserDefaults.standard.sensorUID == nil || UserDefaults.standard.sensorPatchInfo == nil || UserDefaults.standard.sensorCalibration == nil || UserDefaults.standard.sensorState == nil {
            scanNfc()
        }
    }

    public func canConnect() -> Bool {
        if let _ = UserDefaults.standard.sensorUID, let _ = UserDefaults.standard.sensorPatchInfo, let _ = UserDefaults.standard.sensorCalibration, let _ = UserDefaults.standard.sensorState {
            os_log("Can connect: true", log: .sensor)
            
            return true
        }

        os_log("Can connect: false", log: .sensor)
        
        return false
    }

    public func peripheral(_ peripheral: CBPeripheral) {
        os_log("Did discover services", log: .sensor)

        if let services = peripheral.services {
            for service in services {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService) {
        os_log("Did discover characteristics for service: %{public}s", log: .sensor, service.uuid.uuidString)

        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                if characteristic.uuid == readCharacteristicUuid {
                    os_log("Did discover characteristic: %{public}s", log: .sensor, characteristic.uuid.uuidString)

                    readCharacteristic = characteristic
                }

                if characteristic.uuid == writeCharacteristicUuid {
                    os_log("Did discover characteristic: %{public}s", log: .sensor, characteristic.uuid.uuidString)

                    writeCharacteristic = characteristic
                    unlock(peripheral)
                }
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic) {
        os_log("Update notification state, for characteristic %{public}s", log: .sensor, characteristic.uuid.uuidString)

        reset()
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic) {
        if let value = characteristic.value {
            if value.count == 20 {
                os_log("Did update value for 1. block: %{public}s", log: .sensor, value.hex)
            } else if value.count == 18 {
                os_log("Did update value for 2. block: %{public}s", log: .sensor, value.hex)
            } else if value.count == 8 {
                os_log("Did update value for 3. block: %{public}s", log: .sensor, value.hex)
            }

            // add new value to rxBuffer
            rxBuffer.append(value)

            if rxBuffer.count == Libre2Direct.expectedBufferSize {
                guard let sensorUID = UserDefaults.standard.sensorUID, let patchInfo = UserDefaults.standard.sensorPatchInfo, let sensorCalibration = UserDefaults.standard.sensorCalibration, let sensorType = UserDefaults.standard.sensorType else {
                    return
                }

                guard sensorType == .libre2 else {
                    return
                }

                do {
                    let decryptedBLE = Data(try Libre2.decryptBLE(sensorUID: sensorUID, data: rxBuffer))
                    let measurements = Libre2.parseBLEData(decryptedBLE, calibration: sensorCalibration)

                    for trendMeasurement in measurements.trend {
                        os_log("Update value, with trend %{public}s", log: .sensor, trendMeasurement.description)
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
        os_log("Did write value for: %{public}s", log: .sensor, characteristic.uuid.uuidString)

        if characteristic.uuid == writeCharacteristicUuid {
            peripheral.setNotifyValue(true, for: readCharacteristic!)
        }
    }

    private func scanNfc() {
        os_log("Scan NFC", log: .sensor)

        if libreNFC == nil {
            libreNFC = LibreNFC(libreNFCDelegate: self)
            libreNFC?.startSession()
        }
    }

    private func unlock(_ peripheral: CBPeripheral) {
        os_log("Unlock", log: .sensor)

        guard let sensorUID = UserDefaults.standard.sensorUID else {
            return
        }

        guard let patchInfo = UserDefaults.standard.sensorPatchInfo else {
            return
        }

        let unlockCount = (UserDefaults.standard.sensorUnlockCount ?? 0) + 1
        UserDefaults.standard.sensorUnlockCount = unlockCount
        os_log("Unlock, unlockCount: %{public}s", log: .sensor, unlockCount.description)

        let unlockPayLoad = Data(Libre2.streamingUnlockPayload(sensorUID: sensorUID, info: patchInfo, enableTime: 42, unlockCount: unlockCount))
        os_log("Unlock, unlockPayLoad: %{public}s", log: .sensor, unlockPayLoad.hex)

        _ = writeValueToPeripheral(peripheral, value: unlockPayLoad, type: .withResponse)
    }
}
