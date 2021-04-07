//
//  LibreManagerSettingsViewController.swift
//  LibreDirectClientUI
//
//  Created by Julian Groen on 13/05/2020.
//  Copyright © 2020 Julian Groen. All rights reserved.
//

import LoopKit
import LoopKitUI
import LibreDirectClient
import UIKit
import HealthKit

public class LibreManagerSettingsViewController: UITableViewController, LibreDirectCGMManagerDelegate {
    public let cgmManager: LibreDirectCGMManager
    public let glucoseUnit: HKUnit
    public let allowsDeletion: Bool
    
    private lazy var glucoseFormatter: QuantityFormatter = {
        let formatter = QuantityFormatter()
        formatter.setPreferredNumberFormatter(for: glucoseUnit)
        return formatter
    }()

    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .long
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    public init(cgmManager: LibreDirectCGMManager, glucoseUnit: HKUnit, allowsDeletion: Bool) {
        self.cgmManager = cgmManager
        self.glucoseUnit = glucoseUnit
        self.allowsDeletion = allowsDeletion
        
        super.init(style: .grouped)
    }
    
    deinit {
        self.cgmManager.updateDelegate = nil
    }
    
    override public func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        tableView.reloadData()
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        title = cgmManager.localizedTitle

        tableView.rowHeight = UITableViewAutomaticDimension
        tableView.estimatedRowHeight = 44
        tableView.sectionHeaderHeight = UITableViewAutomaticDimension
        tableView.estimatedSectionHeaderHeight = 55

        tableView.register(SettingsTableViewCell.self, forCellReuseIdentifier: SettingsTableViewCell.className)
        tableView.register(TextButtonTableViewCell.self, forCellReuseIdentifier: TextButtonTableViewCell.className)
        tableView.register(SwitchTableViewCell.self, forCellReuseIdentifier: SwitchTableViewCell.className)

        let button = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneTapped(_:)))
        navigationItem.setRightBarButton(button, animated: false)
        
        self.cgmManager.updateDelegate = self
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    @objc func doneTapped(_ sender: Any) {
        complete()
    }

    private func complete() {
        if let nav = navigationController as? SettingsNavigationViewController {
            nav.notifyComplete()
        }
    }

    @objc func glucoseSyncChanged(_ sender: UISwitch) {
        UserDefaults.standard.glucoseSync = sender.isOn
    }
    
    public func cgmManagerUpdate() {
        tableView.reloadData()
    }

    // MARK: - UITableViewDataSource

    private enum Section: Int, CaseIterable {
        case latestReading
        case sensorInfo
        case calibrationInfo
        case configuration
        case actions
        case delete
    }

    private enum ActionsRow: Int, CaseIterable {
        case reloadView
        case resetConnection
    }

    private enum LatestReadingRow: Int, CaseIterable {
        case glucose
        case date
        case trend
    }

    private enum SensorRow: Int, CaseIterable {
        case connection
        case type
        case region
        case state
        case age
        case uid
        case patchInfo
    }

    private enum CalibrationRow: Int, CaseIterable {
        case i1
        case i2
        case i3
        case i4
        case i5
        case i6
    }

    override public func numberOfSections(in tableView: UITableView) -> Int {
        return allowsDeletion ? Section.allCases.count : Section.allCases.count - 1
    }

    override public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .latestReading:
            return LatestReadingRow.allCases.count

        case .sensorInfo:
            return SensorRow.allCases.count

        case .calibrationInfo:
            return CalibrationRow.allCases.count

        case .actions:
            return ActionsRow.allCases.count

        case .configuration, .delete:
            return 1

        }
    }

    override public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .latestReading:
            return LocalizedString("Latest Reading", comment: "")

        case .sensorInfo:
            return LocalizedString("Sensor Info", comment: "")

        case .calibrationInfo:
            return LocalizedString("Calibration", comment: "")

        case .configuration:
            return LocalizedString("Configuration", comment: "")

        case .actions:
            return LocalizedString("Actions", comment: "")

        case .delete:
            return " "

        }
    }

    override public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .latestReading:
            let cell = tableView.dequeueIdentifiableCell(cell: SettingsTableViewCell.self, for: indexPath)

            switch LatestReadingRow(rawValue: indexPath.row)! {
            case .glucose:
                cell.textLabel?.text = LocalizedString("Latest Reading Glucose", comment: "")

                if let quantity = cgmManager.latestReading?.quantity, let glucose = glucoseFormatter.string(from: quantity, for: glucoseUnit) {
                    cell.detailTextLabel?.text = glucose
                } else {
                    cell.detailTextLabel?.text = SettingsTableViewCell.NoValueString
                }

            case .date:
                cell.textLabel?.text = LocalizedString("Latest Reading Date", comment: "")

                if let startDate = cgmManager.latestReading?.startDate {
                    cell.detailTextLabel?.text = dateFormatter.string(from: startDate)
                } else {
                    cell.detailTextLabel?.text = SettingsTableViewCell.NoValueString
                }

            case .trend:
                cell.textLabel?.text = LocalizedString("Latest Reading Trend", comment: "")

                if let trend = cgmManager.latestReading?.trendType {
                    cell.detailTextLabel?.text = trend.localizedDescription
                } else {
                    cell.detailTextLabel?.text = SettingsTableViewCell.NoValueString
                }

            }
            cell.selectionStyle = .none

            return cell
        case .sensorInfo:
            let cell = tableView.dequeueIdentifiableCell(cell: SettingsTableViewCell.self, for: indexPath)

            switch SensorRow(rawValue: indexPath.row)! {
            case .connection:
                cell.textLabel?.text = LocalizedString("Sensor Connection", comment: "")

                if let connection = cgmManager.connection {
                    cell.detailTextLabel?.text = connection
                } else {
                    cell.detailTextLabel?.text = SettingsTableViewCell.NoValueString
                }

            case .age:
                cell.textLabel?.text = LocalizedString("Sensor Age", comment: "")

                if let sensorAge = cgmManager.latestReading?.sensorAge {
                    cell.detailTextLabel?.text = sensorAge
                } else {
                    cell.detailTextLabel?.text = SettingsTableViewCell.NoValueString
                }

            case .type:
                cell.textLabel?.text = LocalizedString("Sensor Type", comment: "")

                if let sensorType = UserDefaults.standard.sensorType {
                    cell.detailTextLabel?.text = sensorType.rawValue
                } else {
                    cell.detailTextLabel?.text = SettingsTableViewCell.NoValueString
                }

            case .region:
                cell.textLabel?.text = LocalizedString("Sensor Region", comment: "")

                if let sensorRegion = UserDefaults.standard.sensorRegion {
                    cell.detailTextLabel?.text = sensorRegion.rawValue
                } else {
                    cell.detailTextLabel?.text = SettingsTableViewCell.NoValueString
                }

            case .state:
                cell.textLabel?.text = LocalizedString("Sensor State", comment: "")

                if let sensorState = UserDefaults.standard.sensorState {
                    cell.detailTextLabel?.text = sensorState.rawValue
                } else {
                    cell.detailTextLabel?.text = SettingsTableViewCell.NoValueString
                }

            case .uid:
                cell.textLabel?.text = LocalizedString("Sensor UID", comment: "")

                if let sensorUID = UserDefaults.standard.sensorUID {
                    cell.detailTextLabel?.text = sensorUID.hex.uppercased()
                } else {
                    cell.detailTextLabel?.text = SettingsTableViewCell.NoValueString
                }

            case .patchInfo:
                cell.textLabel?.text = LocalizedString("Sensor PatchInfo", comment: "")

                if let sensorPatchInfo = UserDefaults.standard.sensorPatchInfo {
                    cell.detailTextLabel?.text = sensorPatchInfo.hex.uppercased()
                } else {
                    cell.detailTextLabel?.text = SettingsTableViewCell.NoValueString
                }

            }

            cell.selectionStyle = .none

            return cell
        case .calibrationInfo:
            let cell = tableView.dequeueIdentifiableCell(cell: SettingsTableViewCell.self, for: indexPath)

            switch CalibrationRow(rawValue: indexPath.row)! {
            case .i1:
                cell.textLabel?.text = LocalizedString("Calibration: i1", comment: "")

                if let i1 = UserDefaults.standard.sensorCalibration?.i1 {
                    cell.detailTextLabel?.text = i1.description
                } else {
                    cell.detailTextLabel?.text = SettingsTableViewCell.NoValueString
                }

            case .i2:
                cell.textLabel?.text = LocalizedString("Calibration: i2", comment: "")

                if let i2 = UserDefaults.standard.sensorCalibration?.i2 {
                    cell.detailTextLabel?.text = i2.description
                } else {
                    cell.detailTextLabel?.text = SettingsTableViewCell.NoValueString
                }

            case .i3:
                cell.textLabel?.text = LocalizedString("Calibration: i3", comment: "")

                if let i3 = UserDefaults.standard.sensorCalibration?.i3 {
                    cell.detailTextLabel?.text = i3.description
                } else {
                    cell.detailTextLabel?.text = SettingsTableViewCell.NoValueString
                }

            case .i4:
                cell.textLabel?.text = LocalizedString("Calibration: i4", comment: "")

                if let i4 = UserDefaults.standard.sensorCalibration?.i4 {
                    cell.detailTextLabel?.text = i4.description
                } else {
                    cell.detailTextLabel?.text = SettingsTableViewCell.NoValueString
                }

            case .i5:
                cell.textLabel?.text = LocalizedString("Calibration: i5", comment: "")

                if let i5 = UserDefaults.standard.sensorCalibration?.i5 {
                    cell.detailTextLabel?.text = i5.description
                } else {
                    cell.detailTextLabel?.text = SettingsTableViewCell.NoValueString
                }

            case .i6:
                cell.textLabel?.text = LocalizedString("Calibration: i6", comment: "")

                if let i6 = UserDefaults.standard.sensorCalibration?.i6 {
                    cell.detailTextLabel?.text = i6.description
                } else {
                    cell.detailTextLabel?.text = SettingsTableViewCell.NoValueString
                }

            }

            cell.selectionStyle = .none

            return cell
        case .configuration:
            let cell = tableView.dequeueIdentifiableCell(cell: SwitchTableViewCell.self, for: indexPath)

            cell.textLabel?.text = LocalizedString("Nightscout Upload", comment: "")
            cell.selectionStyle = .none
            cell.switch?.addTarget(self, action: #selector(glucoseSyncChanged(_:)), for: .valueChanged)
            cell.switch?.isOn = UserDefaults.standard.glucoseSync

            return cell
        case .actions:
            let cell = tableView.dequeueIdentifiableCell(cell: TextButtonTableViewCell.self, for: indexPath)

            switch ActionsRow(rawValue: indexPath.row)! {
            case .resetConnection:
                cell.textLabel?.text = LocalizedString("Reset Connection", comment: "")
                cell.textLabel?.textAlignment = .center
                cell.isEnabled = true
                
            case .reloadView:
                cell.textLabel?.text = LocalizedString("Reload View", comment: "")
                cell.textLabel?.textAlignment = .center
                cell.isEnabled = true
            }

            return cell

        case .delete:
            let cell = tableView.dequeueIdentifiableCell(cell: TextButtonTableViewCell.self, for: indexPath)

            cell.textLabel?.text = LocalizedString("Delete CGM", comment: "")
            cell.textLabel?.textAlignment = .center
            cell.tintColor = .delete
            cell.isEnabled = true

            return cell
        }
    }

    override public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch Section(rawValue: indexPath.section)! {
        case .delete:
            let controller = UIAlertController() {
                self.cgmManager.notifyDelegateOfDeletion {
                    DispatchQueue.main.async {
                        self.complete()
                    }
                }
            }

            present(controller, animated: true) {
                tableView.deselectRow(at: indexPath, animated: true)
            }

        case .actions:
            switch ActionsRow(rawValue: indexPath.row)! {
            case .resetConnection:
                let rescanNfcAlert = UIAlertController(title: LocalizedString("Alert title: Reset Connection", comment: ""), message: LocalizedString("Alert message: Reset Connection", comment: ""), preferredStyle: UIAlertControllerStyle.alert)

                rescanNfcAlert.addAction(UIAlertAction(title: LocalizedString("Ok", comment: ""), style: .default, handler: { (action: UIAlertAction!) in
                    self.cgmManager.resetConnection()
                }))

                rescanNfcAlert.addAction(UIAlertAction(title: LocalizedString("Cancel", comment: ""), style: .cancel))

                present(rescanNfcAlert, animated: true) {
                    tableView.deselectRow(at: indexPath, animated: true)
                }
            
            case .reloadView:
                tableView.reloadData()
                
            }

        case .sensorInfo, .calibrationInfo, .latestReading, .configuration:
            break
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }
}

fileprivate extension UIAlertController {
    convenience init(cgmDeletionHandler handler: @escaping () -> Void) {
        self.init(title: nil, message: LocalizedString("Are you sure you want to delete this CGM?", comment: ""), preferredStyle: .actionSheet)
        addAction(UIAlertAction(title: LocalizedString("Delete CGM", comment: ""), style: .destructive) { _ in handler() })
        addAction(UIAlertAction(title: LocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
    }
}
