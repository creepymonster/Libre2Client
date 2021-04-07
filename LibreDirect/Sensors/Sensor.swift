//
//  Sensor.swift
//  LibreDirectClient
//
//  Created by Julian Groen on 11/05/2020.
//  Copyright © 2020 Julian Groen. All rights reserved. 
//

import Foundation
import CoreBluetooth
import os
import LoopKit

public func GetSensorLink() -> SensorLinkProtocol {
    return Libre2Link()
}

public protocol SensorLinkProtocol {
    func setupLink()
    func linkIsSetUp() -> Bool
    func resetLink()
    func createLinkedSensor(_ peripheral: CBPeripheral) -> Sensor?
    func isLinkedSensor(_ peripheral: CBPeripheral, _ advertisementData: [String: Any]) -> Bool
}

public typealias Sensor = (SensorProtocol & SensorClass)

public protocol SensorProtocol {
    var manufacturer: String { get }

    var serviceCharacteristicsUuid: [CBUUID] { get }
    var writeCharacteristicUuid: CBUUID { get }
    var readCharacteristicUuid: CBUUID { get }

    func peripheral(_ peripheral: CBPeripheral)
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService)
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic)
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic)
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic)
}

public class SensorClass {
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

    required init(with identifier: String) {
        self.identifier = identifier
        self.timestampLastPacket = Date()
        self.rxBuffer = Data()
    }

    deinit {
        delegate = nil
    }

    func writeValueToPeripheral(_ peripheral: CBPeripheral, value: Data, type: CBCharacteristicWriteType) -> Bool {
        Log.debug("Value: \(value.hex)", log: .sensor)

        if let characteristic = writeCharacteristic {
            peripheral.writeValue(value, for: characteristic, type: type)

            return true
        }

        return false
    }

    func reset() {
        Log.debug("Reset buffer", log: .sensor)

        rxBuffer = Data()
        timestampLastPacket = Date()
        resendPacketCounter = 0
    }
}
