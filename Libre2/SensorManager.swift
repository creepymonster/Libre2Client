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

public protocol SensorSetupManagerDelegate: class {
    func sensorManager(_ peripheral: CBPeripheral?, didDiscoverPeripherals peripherals: [CBPeripheral])
}

// MARK: - SensorManager

public class SensorManager: NSObject {
    private static let unknownOutput = "-"
    
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
    
    private var stayConnected = true
    
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
        
        managerQueue.sync {
            self.manager = CBCentralManager(delegate: self, queue: managerQueue, options: nil)
        }
    }
    
    deinit {
        sensor = nil
        delegate = nil
    }
    
    private func scanForSensor() {
        dispatchPrecondition(condition: .onQueue(managerQueue))

        guard manager.state == .poweredOn else {
            return
        }
        
        manager.scanForPeripherals(withServices: sensor?.serviceCharacteristicsUuid, options: nil) //
        state = .scanning
    }
    
    private func connect(_ peripheral: CBPeripheral, instantiate: Bool = false) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        
        if manager.isScanning {
            manager.stopScan()
        }
    
        self.peripheral = peripheral
        
        if instantiate {
            guard let sensor = SensorFromPeripheral(peripheral) else {
                return
            }
            
            self.sensor = sensor
        }
        
        if self.sensor?.canConnect() ?? false {
            manager.connect(peripheral, options: nil)
            state = .connecting
        } else {
            reconnect(delay: 30)
        }
    }
    
    private func reconnect(delay: Double = 7) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            Thread.sleep(forTimeInterval: delay)
            
            self?.managerQueue.sync {
                if let peripheral = self?.peripheral  {
                    self?.connect(peripheral)
                }
            }
        }
    }
    
    func disconnect() {
        dispatchPrecondition(condition: .notOnQueue(managerQueue))

        managerQueue.sync {
            if manager.isScanning {
                manager.stopScan()
            }
            
            if let connection = peripheral {
                manager.cancelPeripheralConnection(connection)
            }
        }
        
        stayConnected = false
    }
}

// MARK: - Extension SensorManager

extension SensorManager: CBCentralManagerDelegate, CBPeripheralDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        
        switch manager.state {
        case .poweredOff:
            state = .powerOff
        case .poweredOn:
            scanForSensor()
        default:
            if manager.isScanning {
                manager.stopScan()
            }
            state = .unassigned
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        logger.debug("Discover: \(peripheral.name ?? SensorManager.unknownOutput)")
        
        guard peripheral.name?.lowercased() != nil, let sensorID = UserDefaults.standard.sensorID else {
            return
        }
        
        if peripheral.identifier.uuidString == sensorID {
            connect(peripheral, instantiate: (peripheral.identifier.uuidString != sensor?.identifier))
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        logger.debug("Connect: \(peripheral.name ?? SensorManager.unknownOutput)")
        
        state = .connected
        peripheral.discoverServices(sensor?.serviceCharacteristicsUuid)
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        logger.debug("Fail to Connect: \(peripheral.name ?? SensorManager.unknownOutput)")
        
        guard let sensorID = UserDefaults.standard.sensorID else {
            return
        }
        
        if peripheral.identifier.uuidString == sensorID {
            manager.connect(peripheral, options: nil)
            state = .connecting
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        logger.debug("Disconnect Peripheral: \(peripheral.name ?? SensorManager.unknownOutput)")
        
        guard let sensorID = UserDefaults.standard.sensorID else {
            return
        }
        
        if peripheral.identifier.uuidString == sensorID {
            manager.connect(peripheral, options: nil)
            state = .connecting
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        logger.debug("Discover Services: \(peripheral.name ?? SensorManager.unknownOutput)")
        
        sensor?.peripheral(peripheral, didDiscoverServices: error)
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        logger.debug("Discover Characteristics: \(peripheral.name ?? SensorManager.unknownOutput)")
        
        sensor?.peripheral(peripheral, didDiscoverCharacteristicsFor: service)
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        logger.debug("Update Notification State: \(peripheral.name ?? SensorManager.unknownOutput)")
        
        state = .notifying
        sensor?.peripheral(peripheral, didUpdateNotificationStateFor: characteristic, error: error)
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        logger.debug("Update Value: \(peripheral.name ?? SensorManager.unknownOutput)")

        sensor?.peripheral(peripheral, didUpdateValueFor: characteristic, error: error)
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        logger.debug("Write Value: \(peripheral.name ?? SensorManager.unknownOutput)")

        sensor?.peripheral(peripheral, didWriteValueFor: characteristic, error: error)
    }
}

// MARK: - SensorSetupManager

public class SensorSetupManager: NSObject {
    private var manager: CBCentralManager! = nil
    private var peripherals = [CBPeripheral]()
    
    public weak var delegate: SensorSetupManagerDelegate?
    
    public override init() {
        super.init()
        manager = CBCentralManager(delegate: self, queue: nil, options: nil)
    }
    
    deinit {
        delegate = nil
    }
    
    public func disconnect() {
        if manager.isScanning {
            manager.stopScan()
        }
    }
    
}

// MARK: - Extension SensorSetupManager

extension SensorSetupManager: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if manager.state == .poweredOn && !manager.isScanning {
                manager.scanForPeripherals(withServices: nil, options: nil)
            }
        default:
            return
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard peripheral.name?.lowercased() != nil else {
            return
        }
        
        if peripheral.compatible == true || UserDefaults.standard.debugModeActivated {
            peripherals.append(peripheral)
            peripherals.removeDuplicates()
            
            delegate?.sensorManager(peripheral, didDiscoverPeripherals: peripherals)
        }
    }
}
