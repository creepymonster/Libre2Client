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

        Log.debug("Init sensor manager", log: .sensorManager)

        managerQueue.sync {
            self.manager = CBCentralManager(delegate: self, queue: managerQueue, options: nil)
        }
    }

    deinit {
        Log.debug("Deinit sensor manager", log: .sensorManager)

        sensor = nil
        delegate = nil
    }

    private func scan() {
        dispatchPrecondition(condition: .notOnQueue(managerQueue))
        Log.debug("Scan", log: .sensorManager)

        managerQueue.sync {
            self.scanForPeripheral()
        }
    }
    
    private func scanForPeripheral() {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        Log.debug("Scan for peripheral", log: .sensorManager)
        
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
        Log.debug("Scan after delay", log: .sensorManager)
        
        DispatchQueue.global(qos: .utility).async {
            Thread.sleep(forTimeInterval: 30)

            self.scan()
        }
    }

    private func connect(_ peripheral: CBPeripheral) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        Log.debug("Connect peripheral", log: .sensorManager)

        if manager.isScanning {
            manager.stopScan()
        }

        self.peripheral = peripheral

        manager.connect(peripheral, options: nil)
        state = .connecting
    }

    func disconnect(stayConnected: Bool) {
        dispatchPrecondition(condition: .notOnQueue(managerQueue))
        Log.debug("Disconnect peripheral", log: .sensorManager)

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
        Log.debug("Reset connection", log: .sensorManager)

        sensor?.resetConnection()
        sensor?.setupConnectionIfNeeded()
        
        disconnect(stayConnected: true)
    }

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        Log.debug("Did update state", log: .sensorManager)

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
        Log.debug(peripheral.name?.description ?? SensorManager.unknownOutput, log: .sensorManager)

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
        Log.debug("Did connect", log: .sensorManager)

        state = .connected
        peripheral.discoverServices(sensor?.serviceCharacteristicsUuid)
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        Log.debug("Did fail to connect", log: .sensorManager)
        
        if let error = error?.localizedDescription {
            Log.error(error, log: .sensorManager)
        }

        manager.connect(peripheral, options: nil)
        state = .connecting
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        Log.debug("Did disconnect peripheral", log: .sensorManager)
        
        if let error = error?.localizedDescription {
            Log.error(error, log: .sensorManager)
            
            manager.connect(peripheral, options: nil)
            state = .connecting
        } else if stayConnected {
            scanAfterDelay()
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        Log.debug("Did discover services", log: .sensorManager)
        
        if let error = error?.localizedDescription {
            Log.error(error, log: .sensorManager)
            
            return
        }

        sensor?.peripheral(peripheral)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        Log.debug("Did discover characteristics", log: .sensorManager)
        
        if let error = error?.localizedDescription {
            Log.error(error, log: .sensorManager)
            
            return
        }

        sensor?.peripheral(peripheral, didDiscoverCharacteristicsFor: service)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        Log.debug("Did update notification state", log: .sensorManager)
        
        if let error = error?.localizedDescription {
            Log.error(error, log: .sensorManager)
            
            return
        }

        state = .notifying
        sensor?.peripheral(peripheral, didUpdateNotificationStateFor: characteristic)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        Log.debug("Did update value", log: .sensorManager)
        
        if let error = error?.localizedDescription {
            Log.error(error, log: .sensorManager)
            
            return
        }

        sensor?.peripheral(peripheral, didUpdateValueFor: characteristic)
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        Log.debug("Did write value", log: .sensorManager)
        
        if let error = error?.localizedDescription {
            Log.error(error, log: .sensorManager)
            
            return
        }

        sensor?.peripheral(peripheral, didWriteValueFor: characteristic)
    }
}
