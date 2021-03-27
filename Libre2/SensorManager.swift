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
import LoopKit

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

        os_log("Init sensor manager", log: .sensorManager)

        managerQueue.sync {
            self.manager = CBCentralManager(delegate: self, queue: managerQueue, options: nil)
        }
    }

    deinit {
        os_log("Deinit sensor manager", log: .sensorManager)

        sensor = nil
        delegate = nil
    }

    private func scan() {
        dispatchPrecondition(condition: .notOnQueue(managerQueue))
        os_log("Scan", log: .sensorManager)

        managerQueue.sync {
            self.scanForPeripheral()
        }
    }
    
    private func scanForPeripheral() {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        os_log("Scan for peripheral", log: .sensorManager)
        
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
        os_log("Connect peripheral", log: .sensorManager)

        if manager.isScanning {
            manager.stopScan()
        }

        self.peripheral = peripheral

        manager.connect(peripheral, options: nil)
        state = .connecting
    }

    func disconnect(stayConnected: Bool) {
        dispatchPrecondition(condition: .notOnQueue(managerQueue))
        os_log("Disconnect peripheral", log: .sensorManager)

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
        os_log("Reset connection", log: .sensorManager)

        sensor?.resetConnection()
        sensor?.setupConnectionIfNeeded()
        
        disconnect(stayConnected: true)
    }

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        os_log("Did update state", log: .sensorManager)

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
        os_log("Did discover peripheral %{public}s", log: .sensorManager, peripheral.name?.description ?? SensorManager.unknownOutput)

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
        os_log("Did connect", log: .sensorManager)

        state = .connected
        peripheral.discoverServices(sensor?.serviceCharacteristicsUuid)
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        os_log("Did fail to connect", log: .sensorManager)
        
        if let error = error?.localizedDescription {
            os_log("Did fail to connect, error: %{public}s", log: .sensorManager, error)
        }

        if stayConnected {
            scanAfterDelay()
        }
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        os_log("Did disconnect peripheral", log: .sensorManager)
        
        if let error = error?.localizedDescription {
            os_log("Did disconnect peripheral, error: %{public}s", log: .sensorManager, error)
        }

        if stayConnected {
            scanAfterDelay()
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        os_log("Did discover services", log: .sensorManager)
        
        if let error = error?.localizedDescription {
            os_log("Did discover services, error: %{public}s", log: .sensorManager, error)
            
            return
        }

        sensor?.peripheral(peripheral)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        os_log("Did discover characteristics for", log: .sensorManager)
        
        if let error = error?.localizedDescription {
            os_log("Did discover characteristics for, error: %{public}s", log: .sensorManager, error)
            
            return
        }

        sensor?.peripheral(peripheral, didDiscoverCharacteristicsFor: service)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        os_log("Did update notification state for", log: .sensorManager)
        
        if let error = error?.localizedDescription {
            os_log("Did update notification state for, error: %{public}s", log: .sensorManager, error)
            
            return
        }

        state = .notifying
        sensor?.peripheral(peripheral, didUpdateNotificationStateFor: characteristic)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        os_log("Did update value for", log: .sensorManager)
        
        if let error = error?.localizedDescription {
            os_log("Did write value for, error: %{public}s", log: .sensorManager, error)
            
            return
        }

        sensor?.peripheral(peripheral, didUpdateValueFor: characteristic)
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        os_log("Did write value for", log: .sensorManager)
        
        if let error = error?.localizedDescription {
            os_log("Did write value for, error: %{public}s", log: .sensorManager, error)
            
            return
        }

        sensor?.peripheral(peripheral, didWriteValueFor: characteristic)
    }
}
