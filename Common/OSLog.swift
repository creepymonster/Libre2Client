//
//  OSLog.swift
//  Libre2Client
//
//  Created by Reimar Metzen on 27.03.21.
//  Copyright © 2021 Reimar Metzen. All rights reserved.
//

import Foundation
import os.log

extension OSLog {
    private static var subsystem = Bundle.main.bundleIdentifier!
    
    static let sensor = OSLog(subsystem: subsystem, category: "sensor")
    static let sensorManager = OSLog(subsystem: subsystem, category: "SensorManager")
}
