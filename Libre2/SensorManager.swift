//
//  SensorManager.swift
//  Libre2Client
//
//  Created by Julian Groen on 11/05/2020.
//  Copyright © 2020 Julian Groen. All rights reserved.
//

import Foundation
import CoreBluetooth
import HealthKit
import os.log

public protocol SensorManagerDelegate: class {
    func sensorManager(_ sensor: Sensor?, didChangeSensorConnectionState state: SensorConnectionState)
    func sensorManager(_ sensor: Sensor?, didUpdateSensorData data: SensorData)
}

// MARK: - SensorManager

public class SensorManager: NSObject {
    private static let unknownOutput = "-"

    private var stayConnected = true
    private var manager: CBCentralManager! = nil
    private let managerQueue = DispatchQueue(label: "com.libre2client.bluetooth.queue", qos: .unspecified)

    weak var delegate: SensorManagerDelegate?
    var logger: Logger = Logger(subsystem: "Libre2Client", category: "SensorManager")

    private var peripheral: CBPeripheral? {
        didSet {
            oldValue?.delegate = nil
            peripheral?.delegate = self
        }
    }

    public private(set) var sensor: Sensor? = nil {
        didSet {
            oldValue?.delegate = nil
            sensor?.delegate = delegate
        }
    }

    public private(set) var state: SensorConnectionState = .unassigned {
        didSet {
            delegate?.sensorManager(sensor, didChangeSensorConnectionState: state)
        }
    }

    override init() {
        super.init()

        logger.log("Init sensor manager")

        managerQueue.sync {
            self.manager = CBCentralManager(delegate: self, queue: managerQueue, options: nil)
        }
    }

    deinit {
        logger.log("Deinit sensor manager")

        sensor = nil
        delegate = nil
    }

    private func scan() {
        dispatchPrecondition(condition: .notOnQueue(managerQueue))
        logger.log("Scan")

        managerQueue.sync {
            self.scanForPeripheral()
        }
    }
    
    private func scanForPeripheral() {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        logger.log("Scan for peripheral")
        
        guard manager.state == .poweredOn else {
            return
        }

        if sensor == nil {
            sensor = Libre2Direct()
        }
        
        sensor!.setupConnectionIfNeeded()

        manager.scanForPeripherals(withServices: nil, options: nil) // sensor?.serviceCharacteristicsUuid
        state = .scanning
    }

    private func scanAfterDelay() {
        DispatchQueue.global(qos: .utility).async {
            Thread.sleep(forTimeInterval: 30)

            self.scan()
        }
    }

    private func connect(_ peripheral: CBPeripheral) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        logger.log("Connect peripheral")

        if manager.isScanning {
            manager.stopScan()
        }

        self.peripheral = peripheral

        manager.connect(peripheral, options: nil)
        state = .connecting
    }

    func disconnect(stayConnected: Bool) {
        dispatchPrecondition(condition: .notOnQueue(managerQueue))
        logger.log("Disconnect peripheral")

        managerQueue.sync {
            if manager.isScanning {
                manager.stopScan()
            }

            if let connection = peripheral {
                manager.cancelPeripheralConnection(connection)
            }
        }
        
        self.stayConnected = stayConnected
    }
}

// MARK: - Extension SensorManager

extension SensorManager: CBCentralManagerDelegate, CBPeripheralDelegate {
    public func resetConnection() {
        logger.log("Reset connection")

        sensor?.resetConnection()
        sensor?.setupConnectionIfNeeded()
        
        disconnect(stayConnected: true)
    }

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        logger.log("Did update state, manager.state: \(self.manager.state.rawValue)")

        switch manager.state {
        case .poweredOff:
            state = .powerOff

        case .poweredOn:
            scanForPeripheral()

        default:
            if manager.isScanning {
                manager.stopScan()
            }

            state = .unassigned
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        logger.log("Did discover peripheral \(peripheral.name ?? SensorManager.unknownOutput)")

        guard peripheral.name?.lowercased() != nil else {
            return
        }

        guard sensor?.canSupportPeripheral(peripheral, advertisementData) ?? false else {
            return
        }

        connect(peripheral)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        logger.log("Did connect")

        state = .connected
        peripheral.discoverServices(sensor?.serviceCharacteristicsUuid)
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        logger.log("Did fail to connect, error: \(error?.localizedDescription ?? SensorManager.unknownOutput)")

        if stayConnected {
            scanAfterDelay()
        }
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        logger.log("Did disconnect peripheral, error: \(error?.localizedDescription ?? SensorManager.unknownOutput)")

        if stayConnected {
            scanAfterDelay()
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        logger.log("Did discover services, error: \(error?.localizedDescription ?? SensorManager.unknownOutput)")

        sensor?.peripheral(peripheral)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        logger.log("Did discover characteristics for, error: \(error?.localizedDescription ?? SensorManager.unknownOutput)")

        sensor?.peripheral(peripheral, didDiscoverCharacteristicsFor: service)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        logger.log("Did update notification state for, error: \(error?.localizedDescription ?? SensorManager.unknownOutput)")

        state = .notifying
        sensor?.peripheral(peripheral, didUpdateNotificationStateFor: characteristic)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        logger.log("Did update value for, error: \(error?.localizedDescription ?? SensorManager.unknownOutput)")

        sensor?.peripheral(peripheral, didUpdateValueFor: characteristic)
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        logger.log("Did write value for, error: \(error?.localizedDescription ?? SensorManager.unknownOutput)")

        sensor?.peripheral(peripheral, didWriteValueFor: characteristic)
    }
}
