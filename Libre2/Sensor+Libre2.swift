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

    required init(with identifier: String, name: String?) {
        super.init(with: identifier, name: name)

        let serial = String(name!.suffix(name!.count - 6))
        UserDefaults.standard.sensorSerial = serial
        
        if UserDefaults.standard.sensorUID == nil || UserDefaults.standard.sensorPatchInfo == nil || UserDefaults.standard.sensorCalibration == nil || UserDefaults.standard.sensorState == nil {
            self.scanNfc()
        }

        logger.log("Init sensor, with serial \(serial)")
    }
    
    public func resetConnection() {
        UserDefaults.standard.sensorUID = nil
        UserDefaults.standard.sensorPatchInfo = nil
        UserDefaults.standard.sensorCalibration = nil
        UserDefaults.standard.sensorState = nil
    }
    
    public func received(sensorUID: Data, patchInfo: Data) {
        UserDefaults.standard.sensorUID = sensorUID
        UserDefaults.standard.sensorPatchInfo = patchInfo
        
        logger.log("Received, for sensorUID \(sensorUID.hex)")
        logger.log("Received, for sensorPatchInfo \(patchInfo.hex)")
    }

    public func received(fram: Data) {
        guard let sensorUID = UserDefaults.standard.sensorUID, let patchInfo = UserDefaults.standard.sensorPatchInfo else {
            return
        }
        
        let data = PreLibre.decryptFRAM(sensorUID, patchInfo, fram)

        UserDefaults.standard.sensorCalibration = Libre2.readFactoryCalibration(bytes: data)
        UserDefaults.standard.sensorState = SensorState(bytes: data)
        
        logger.log("Received, for calibration \(UserDefaults.standard.sensorCalibration?.description ?? Libre2Direct.unknownOutput)")
        logger.log("Received, for state \(UserDefaults.standard.sensorState?.description ?? Libre2Direct.unknownOutput)")
    }

    public func streamingEnabled(successful: Bool) {
        logger.log("Streaming enabled: \(successful)")
        
        if successful {
            UserDefaults.standard.sensorUnlockCount = 0
        }
    }

    public func canConnect() -> Bool {
        if let _ = UserDefaults.standard.sensorUID, let _ = UserDefaults.standard.sensorPatchInfo, let _ = UserDefaults.standard.sensorCalibration, let _ = UserDefaults.standard.sensorState {
            logger.log("Can connect to sensor")
            return true
        }
        
        logger.log("Cannot connect to sensor")
        return false
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        logger.log("Discover services, with error \(error.debugDescription)")
        
        if let services = peripheral.services {
            for service in services {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService) {
        logger.log("Discover characteristics, for service \(service.uuid.uuidString)")
        
        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                if characteristic.uuid == readCharacteristicUuid {
                    logger.log("Discover characteristics, for service \(service.uuid.uuidString), with characteristic \(characteristic.uuid.uuidString)")
                    
                    readCharacteristic = characteristic
                }

                if characteristic.uuid == writeCharacteristicUuid {
                    logger.log("Discover characteristics, for service \(service.uuid.uuidString), with characteristic \(characteristic.uuid.uuidString)")
                    
                    writeCharacteristic = characteristic
                    unlock(peripheral)
                }
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        logger.log("Update notification state, for characteristic \(characteristic.uuid.uuidString), and error \(error.debugDescription)")
        
        reset()
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let value = characteristic.value {
            if value.count == 20 {
                logger.log("Update value, for 1. block")
            } else if value.count == 18 {
                logger.log("Update value, for 2. block")
            } else if value.count == 8 {
                logger.log("Update value, for 3. block")
            }
            
            // add new value to rxBuffer
            rxBuffer.append(value)
            
            if rxBuffer.count == Libre2Direct.expectedBufferSize {
                guard let sensorUID = UserDefaults.standard.sensorUID, let patchInfo = UserDefaults.standard.sensorPatchInfo, let sensorCalibration = UserDefaults.standard.sensorCalibration, let sensorType = UserDefaults.standard.sensorType else {
                    scanNfc()
                    return
                }
                
                guard sensorType == .libre2 else {
                    logger.log("Update value, with wrong sensor type \(sensorType.description)")
                    return
                }
                
                do {
                    let decryptedBLE = Data(try Libre2.decryptBLE(sensorUID: sensorUID, data: rxBuffer))
                    let measurements = Libre2.parseBLEData(decryptedBLE, calibration: sensorCalibration)
                    
                    logger.log("Update value, with crc \(measurements.crc.description)")
                    
                    for trendMeasurement in measurements.trend {
                        logger.log("Update value, with trend \(trendMeasurement.description)")
                    }
                    
                    let sensorData = SensorData(bytes: decryptedBLE, sensorUID: sensorUID, patchInfo: patchInfo, calibration: sensorCalibration, wearTimeMinutes: measurements.wearTimeMinutes, trend: measurements.trend, history: measurements.history)
                    if let sensorData = sensorData {
                        delegate?.sensorManager(self, didUpdateSensorData: sensorData)
                    }
                    
                    reset()
                } catch {
                    logger.log("Update value, with exception")
                    reset()
                }
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        logger.log("Write value, for characteristic \(characteristic.uuid.uuidString)")
        
        if characteristic.uuid == writeCharacteristicUuid {
            peripheral.setNotifyValue(true, for: readCharacteristic!)
        } else {
            logger.log("Write value, for unknown characteristic \(characteristic.uuid.uuidString)")
        }
    }

    public static func canSupportPeripheral(_ peripheral: CBPeripheral) -> Bool {
        peripheral.name?.lowercased().starts(with: "abbott") ?? false
    }
    
    private func scanNfc() {
        libreNFC = LibreNFC(libreNFCDelegate: self)
        libreNFC?.startSession()
    }
    
    private func unlock(_ peripheral: CBPeripheral) {
        logger.log("Unlock")
        
        guard let sensorUID = UserDefaults.standard.sensorUID else {
            logger.log("Unlock, no sensorUID set")
            return
        }
        
        guard let patchInfo = UserDefaults.standard.sensorPatchInfo else {
            logger.log("Unlock, no sensorPatchInfo set")
            return
        }
        
        let unlockCount = (UserDefaults.standard.sensorUnlockCount ?? 0) + 1
        UserDefaults.standard.sensorUnlockCount = unlockCount
        logger.log("Unlock, with unlockCount \(unlockCount)")
        
        let unlockPayLoad = Data(Libre2.streamingUnlockPayload(sensorUID: sensorUID, info: patchInfo, enableTime: 42, unlockCount: unlockCount))
        logger.log("Unlock, with unlockPayLoad \(unlockPayLoad.hex)")
        
        _ = writeValueToPeripheral(peripheral, value: unlockPayLoad, type: .withResponse)
    }
}
