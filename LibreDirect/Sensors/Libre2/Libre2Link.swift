//
//  Libre2Link.swift
//  LibreDirectClient
//
//  Created by Reimar Metzen on 29.03.21.
//  Copyright © 2021 Reimar Metzen. All rights reserved.
//

import Foundation
import CoreBluetooth

public class Libre2Link: SensorLinkProtocol, LibreNFCDelegate {
    private static let unknownOutput = "-"

    var libreNFC: LibreNFC?

    public func setupLink() {
        Log.debug("Setup link", log: .sensorLink)

        if UserDefaults.standard.sensorUID == nil || UserDefaults.standard.sensorPatchInfo == nil || UserDefaults.standard.sensorCalibration == nil || UserDefaults.standard.sensorState == nil {
            scanNfc()
        }
    }

    public func linkIsSetUp() -> Bool {
        if let _ = UserDefaults.standard.sensorUID, let _ = UserDefaults.standard.sensorPatchInfo, let _ = UserDefaults.standard.sensorCalibration, let _ = UserDefaults.standard.sensorState {
            Log.debug("Link is set up: true", log: .sensorLink)

            return true
        }

        Log.debug("Link is set up: false", log: .sensorLink)

        return false
    }

    public func resetLink() {
        Log.debug("Reset link", log: .sensorLink)

        UserDefaults.standard.sensorUID = nil
        UserDefaults.standard.sensorPatchInfo = nil
        UserDefaults.standard.sensorCalibration = nil
        UserDefaults.standard.sensorState = nil
    }

    public func createLinkedSensor(_ peripheral: CBPeripheral) -> Sensor? {
        Log.debug("Create linked sensor", log: .sensorLink)

        return Libre2Sensor.init(with: peripheral.identifier.uuidString)
    }

    public func isLinkedSensor(_ peripheral: CBPeripheral, _ advertisementData: [String: Any]) -> Bool {
        Log.debug("Is linked sensor", log: .sensorLink)

        guard let sensorUID = UserDefaults.standard.sensorUID else {
            Log.debug("Is linked sensor: sensorUID not found", log: .sensorLink)
            
            return false
        }

        if let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            if manufacturerData.count == 8 {
                var foundUID = manufacturerData.subdata(in: 2..<8)
                foundUID.append(contentsOf: [0x07, 0xe0])

                Log.debug("Is linked sensor, name: \(peripheral.name ?? Libre2Link.unknownOutput)", log: .sensorLink)
                Log.debug("Is linked sensor, foundUID: \(foundUID.hex.uppercased())", log: .sensorLink)
                Log.debug("Is linked sensor, sensorUID: \(sensorUID.hex.uppercased())", log: .sensorLink)

                let result = foundUID == sensorUID && peripheral.name?.lowercased().starts(with: "abbott") ?? false
                
                Log.debug("Is linked sensor: \(result)", log: .sensorLink)
                
                return result
            }
        }

        return false
    }

    public func received(sensorUID: Data, patchInfo: Data) {
        Log.debug("Received", log: .sensorLink)

        UserDefaults.standard.sensorUID = sensorUID
        UserDefaults.standard.sensorPatchInfo = patchInfo

        Log.debug("Received SensorUID: \(sensorUID.hex.uppercased())", log: .sensorLink)
        Log.debug("Received PatchInfo: \(patchInfo.hex.uppercased())", log: .sensorLink)
    }

    public func received(fram: Data) {
        Log.debug("Received", log: .sensorLink)

        guard let sensorUID = UserDefaults.standard.sensorUID, let patchInfo = UserDefaults.standard.sensorPatchInfo else {
            return
        }

        let data = PreLibre.decryptFRAM(sensorUID, patchInfo, fram)

        UserDefaults.standard.sensorCalibration = Libre2.readFactoryCalibration(bytes: data)
        UserDefaults.standard.sensorState = SensorState(bytes: data)

        Log.debug("Received SensorCalibration: \(UserDefaults.standard.sensorCalibration?.description ?? Libre2Link.unknownOutput)", log: .sensorLink)
        Log.debug("Received SensorState: \(UserDefaults.standard.sensorState?.description ?? Libre2Link.unknownOutput)", log: .sensorLink)
    }

    public func streamingEnabled(successful: Bool) {
        Log.debug("StreamingEnabled: \(successful.description)", log: .sensorLink)

        if successful {
            UserDefaults.standard.sensorUnlockCount = 0
        }
    }

    public func finished() {
        Log.debug("Finished", log: .sensorLink)

        libreNFC = nil
    }

    private func scanNfc() {
        Log.debug("Scan NFC, libreNFC is nil: \(libreNFC == nil)", log: .sensorLink)

        if libreNFC == nil {
            libreNFC = LibreNFC(libreNFCDelegate: self)
            libreNFC?.startSession()
        }
    }
}
