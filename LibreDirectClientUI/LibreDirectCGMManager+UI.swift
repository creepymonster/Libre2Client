//
//  Libre2CGMManager+UI.swift
//  LibreDirectClientUI
//
//  Created by Julian Groen on 13/05/2020.
//  Copyright © 2020 Julian Groen. All rights reserved.
//

import HealthKit
import LoopKitUI
import LibreDirectClient

extension LibreDirectCGMManager: CGMManagerUI {
    public static func setupViewController() -> (UIViewController & CGMManagerSetupViewController & CompletionNotifying)? {
        return nil
    }

    public func settingsViewController(for glucoseUnit: HKUnit) -> (UIViewController & CompletionNotifying) {
        let settings = LibreManagerSettingsViewController(cgmManager: self, glucoseUnit: glucoseUnit, allowsDeletion: true)
        let navigation = SettingsNavigationViewController(rootViewController: settings)

        UserDefaults.standard.glucoseUnit = glucoseUnit

        return navigation
    }

    public var smallImage: UIImage? {
        return nil
    }
}
