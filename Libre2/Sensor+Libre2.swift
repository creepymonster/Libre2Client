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
import Combine

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

        logger.log("Init sensor")
    }

    public func resetConnection() {
        logger.log("Reset connection")

        UserDefaults.standard.sensorUID = nil
        UserDefaults.standard.sensorPatchInfo = nil
        UserDefaults.standard.sensorCalibration = nil
        UserDefaults.standard.sensorState = nil
    }

    public func received(sensorUID: Data, patchInfo: Data) {
        UserDefaults.standard.sensorUID = sensorUID
        UserDefaults.standard.sensorPatchInfo = patchInfo

        logger.log("Received, sensorUID: \(sensorUID.hex)")
        logger.log("Received, sensorPatchInfo: \(patchInfo.hex)")
    }

    public func received(fram: Data) {
        guard let sensorUID = UserDefaults.standard.sensorUID, let patchInfo = UserDefaults.standard.sensorPatchInfo else {
            return
        }

        let data = PreLibre.decryptFRAM(sensorUID, patchInfo, fram)

        UserDefaults.standard.sensorCalibration = Libre2.readFactoryCalibration(bytes: data)
        UserDefaults.standard.sensorState = SensorState(bytes: data)

        logger.log("Received, calibration: \(UserDefaults.standard.sensorCalibration?.description ?? Libre2Direct.unknownOutput)")
        logger.log("Received, state: \(UserDefaults.standard.sensorState?.description ?? Libre2Direct.unknownOutput)")
    }

    public func streamingEnabled(successful: Bool) {
        logger.log("Streaming enabled: \(successful)")

        if successful {
            UserDefaults.standard.sensorUnlockCount = 0
        }
    }
    
    public func finished() {
        logger.log("Finished NFC")
        
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

                logger.log("Can support peripheral, name: \(peripheral.name?.lowercased() ?? Libre2Direct.unknownOutput)")
                logger.log("Can support peripheral, foundUID: \(foundUID.hex)")
                logger.log("Can support peripheral, sensorUID: \(sensorUID.hex)")

                return foundUID == sensorUID && peripheral.name?.lowercased().starts(with: "abbott") ?? false
            }
        }

        return false
    }
    
    public func setupConnectionIfNeeded() {
        logger.log("Setup connection")
        
        if UserDefaults.standard.sensorUID == nil || UserDefaults.standard.sensorPatchInfo == nil || UserDefaults.standard.sensorCalibration == nil || UserDefaults.standard.sensorState == nil {
            scanNfc()
        }
    }

    public func canConnect() -> Bool {
        if let _ = UserDefaults.standard.sensorUID, let _ = UserDefaults.standard.sensorPatchInfo, let _ = UserDefaults.standard.sensorCalibration, let _ = UserDefaults.standard.sensorState {
            logger.log("Can connect: true")
            
            return true
        }

        logger.log("Can connect: false")
        
        return false
    }

    public func peripheral(_ peripheral: CBPeripheral) {
        logger.log("Did discover services")

        if let services = peripheral.services {
            for service in services {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService) {
        logger.log("Did discover characteristics for service: \(service.uuid.uuidString)")

        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                if characteristic.uuid == readCharacteristicUuid {
                    logger.log("Did discover characteristic: \(characteristic.uuid.uuidString)")

                    readCharacteristic = characteristic
                }

                if characteristic.uuid == writeCharacteristicUuid {
                    logger.log("Did discover characteristic: \(characteristic.uuid.uuidString)")

                    writeCharacteristic = characteristic
                    unlock(peripheral)
                }
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic) {
        logger.log("Update notification state, for characteristic \(characteristic.uuid.uuidString)")

        reset()
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic) {
        if let value = characteristic.value {
            if value.count == 20 {
                logger.log("Did update value for 1. block: \(value.hex)")
            } else if value.count == 18 {
                logger.log("Did update value for 2. block: \(value.hex)")
            } else if value.count == 8 {
                logger.log("Did update value for 3. block: \(value.hex)")
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
                        logger.log("Update value, with trend \(trendMeasurement.description)")
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
        logger.log("Did write value for: \(characteristic.uuid.uuidString)")

        if characteristic.uuid == writeCharacteristicUuid {
            peripheral.setNotifyValue(true, for: readCharacteristic!)
        }
    }

    private func scanNfc() {
        logger.log("Scan NFC")

        if libreNFC == nil {
            libreNFC = LibreNFC(libreNFCDelegate: self)
            libreNFC?.startSession()
        }
    }

    private func unlock(_ peripheral: CBPeripheral) {
        logger.log("Unlock")

        guard let sensorUID = UserDefaults.standard.sensorUID else {
            return
        }

        guard let patchInfo = UserDefaults.standard.sensorPatchInfo else {
            return
        }

        let unlockCount = (UserDefaults.standard.sensorUnlockCount ?? 0) + 1
        UserDefaults.standard.sensorUnlockCount = unlockCount
        logger.log("Unlock, unlockCount: \(unlockCount)")

        let unlockPayLoad = Data(Libre2.streamingUnlockPayload(sensorUID: sensorUID, info: patchInfo, enableTime: 42, unlockCount: unlockCount))
        logger.log("Unlock, unlockPayLoad: \(unlockPayLoad.hex)")

        _ = writeValueToPeripheral(peripheral, value: unlockPayLoad, type: .withResponse)
    }
}
