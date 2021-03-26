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

public typealias Sensor = (SensorProtocol & SensorClass)

public protocol SensorProtocol {
    var manufacturer: String { get }

    var serviceCharacteristicsUuid: [CBUUID] { get }
    var writeCharacteristicUuid: CBUUID { get }
    var readCharacteristicUuid: CBUUID { get }

    func resetConnection()
    func canSupportPeripheral(_ peripheral: CBPeripheral, _ advertisementData: [String: Any]) -> Bool
    func setupConnection()
    func canConnect() -> Bool

    func peripheral(_ peripheral: CBPeripheral)
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService)
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic)
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic)
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic)
}

public class SensorClass {
    var logger: Logger = Logger(subsystem: "Libre2Client", category: "Sensor")

    var readCharacteristic: CBCharacteristic?
    var writeCharacteristic: CBCharacteristic?
    var rxBuffer: Data
    var resendPacketCounter: Int = 0
    var timestampLastPacket: Date
    let maxWaitForNextPacket = 60.0
    let maxPacketResendRequests = 3
    var sensorType: SensorType?

    weak var delegate: SensorManagerDelegate?

    required init() {
        self.timestampLastPacket = Date()
        self.rxBuffer = Data()
    }

    deinit {
        delegate = nil
    }

    func writeValueToPeripheral(_ peripheral: CBPeripheral, value: Data, type: CBCharacteristicWriteType) -> Bool {
        logger.log("Write value to peripheral, value: \(value.hex)")

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
