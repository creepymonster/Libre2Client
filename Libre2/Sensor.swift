//
//  Sensor.swift
//  Libre2Client
//
//  Created by Julian Groen on 11/05/2020.
//  Copyright © 2020 Julian Groen. All rights reserved.
//

import Foundation
import CoreBluetooth
import os

public let allSensors: [Sensor.Type] = [
    Libre2Direct.self
]

public func SensorFromPeripheral(_ peripheral: CBPeripheral) -> Sensor? {
    guard let sensorType = peripheral.type else {
        return nil
    }

    return sensorType.init(with: peripheral.identifier.uuidString, name: peripheral.name)
}

public typealias Sensor = (SensorProtocol & SensorClass)

public protocol SensorProtocol {
    var manufacturer: String { get }

    var serviceCharacteristicsUuid: [CBUUID] { get }
    var writeCharacteristicUuid: CBUUID { get }
    var readCharacteristicUuid: CBUUID { get }
    
    func resetConnection()
    func canConnect() -> Bool
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService)
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?)

    static func canSupportPeripheral(_ peripheral: CBPeripheral) -> Bool
}

public class SensorClass {
    var logger: Logger = Logger(subsystem: "Libre2Client", category: "Sensor")
    var identifier: String
    var readCharacteristic: CBCharacteristic?
    var writeCharacteristic: CBCharacteristic?
    var rxBuffer: Data
    var resendPacketCounter: Int = 0
    var timestampLastPacket: Date
    let maxWaitForNextPacket = 60.0
    let maxPacketResendRequests = 3
    var sensorType: SensorType?

    weak var delegate: SensorManagerDelegate?
    
    required init(with identifier: String, name: String?) {
        self.identifier = identifier
        self.timestampLastPacket = Date()
        self.rxBuffer = Data()
    }
    
    deinit {
        delegate = nil
    }
    
    func writeValueToPeripheral(_ peripheral: CBPeripheral, value: Data, type: CBCharacteristicWriteType) -> Bool {
        logger.log("Write value to peripheral \(value.hex)")
        
        if let characteristic = writeCharacteristic {
            peripheral.writeValue(value, for: characteristic, type: type)
            
            return true
        }
        
        return false
    }
    
    func reset() {
        logger.log("Reset buffer")
        
        rxBuffer = Data()
        timestampLastPacket = Date()
        resendPacketCounter = 0
    }
}
