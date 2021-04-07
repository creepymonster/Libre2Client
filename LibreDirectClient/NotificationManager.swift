//
//  NotificationManager.swift
//  LibreDirectClient
//
//  Created by Julian Groen on 18/05/2020. 
//  Copyright © 2020 Julian Groen. All rights reserved.
//

import Foundation
import LoopKit
import UserNotifications
import AudioToolbox

struct NotificationManager {
    enum Identifier: String {
        case sensorExpire = "com.LibreDirectClient.notifications.sensorExpire"
        case sensorConnection = "com.LibreDirectClient.notifications.sensorConnection"
    }

    private static func add(identifier: Identifier, content: UNMutableNotificationContent) {
        let center = UNUserNotificationCenter.current()
        let request = UNNotificationRequest(identifier: identifier.rawValue, content: content, trigger: nil)

        center.removeDeliveredNotifications(withIdentifiers: [identifier.rawValue])
        center.removePendingNotificationRequests(withIdentifiers: [identifier.rawValue])
        center.add(request)
    }

    private static func ensureCanSendNotification(_ completion: @escaping (_ canSend: Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if #available (iOSApplicationExtension 12.0, *) {
                guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                    completion(false)
                    return
                }
            } else {
                guard settings.authorizationStatus == .authorized else {
                    completion(false)
                    return
                }
            }
            completion(true)
        }
    }

    public static func sendSensorConnectedNotification() {
        ensureCanSendNotification { ensured in
            guard ensured else {
                return
            }

            let notification = UNMutableNotificationContent()
            notification.title = LocalizedString("Notification Title: Sensor connected", comment: "")
            notification.body = LocalizedString("Notification Body: Sensor connected", comment: "")
            notification.sound = .none

            add(identifier: .sensorConnection, content: notification)
        }
    }

    public static func sendSensorDisconnectedNotification() {
        playAlarm()

        ensureCanSendNotification { ensured in
            guard ensured else {
                return
            }

            let notification = UNMutableNotificationContent()
            notification.title = LocalizedString("Notification Title: Sensor disconnected", comment: "")
            notification.body = LocalizedString("Notification Body: Sensor disconnected", comment: "")
            notification.sound = .none
            notification.categoryIdentifier = "alarm"

            add(identifier: .sensorConnection, content: notification)
        }
    }

    public static func sendSensorDisconnectedNotification(error: String) {
        playAlarm()

        ensureCanSendNotification { ensured in
            guard ensured else {
                return
            }

            let notification = UNMutableNotificationContent()
            notification.title = LocalizedString("Notification Title: Sensor connection lost", comment: "")
            notification.body = String(format: LocalizedString("Notification Body: Sensor connection lost, the following error occurred: '%@'", comment: ""), error)
            notification.sound = .none
            notification.categoryIdentifier = "alarm"

            add(identifier: .sensorConnection, content: notification)
        }
    }

    public static func sendSensorExpireNotificationIfNeeded(_ data: SensorData) {
        switch data.wearTimeMinutes {
        case let x where x >= 15840 && !(UserDefaults.standard.lastSensorAge ?? 0 >= 15840): // three days
            sendSensorExpiringNotification(body: String(format: LocalizedString("Notification Body: Replace sensor in %1$@ days", comment: ""), "3"))
        case let x where x >= 17280 && !(UserDefaults.standard.lastSensorAge ?? 0 >= 17280): // two days
            sendSensorExpiringNotification(body: String(format: LocalizedString("Notification Body: Replace sensor in %1$@ days", comment: ""), "2"))
        case let x where x >= 18720 && !(UserDefaults.standard.lastSensorAge ?? 0 >= 18720): // one day
            sendSensorExpiringNotification(body: String(format: LocalizedString("Notification Body: Replace sensor in %1$@ day", comment: ""), "1"))
        case let x where x >= 19440 && !(UserDefaults.standard.lastSensorAge ?? 0 >= 19440): // twelve hours
            sendSensorExpiringNotification(body: String(format: LocalizedString("Notification Body: Replace sensor in %1$@ hours", comment: ""), "12"))
        case let x where x >= 20100 && !(UserDefaults.standard.lastSensorAge ?? 0 >= 20100): // one hour
            sendSensorExpiringNotification(body: String(format: LocalizedString("Notification Body: Replace sensor in %1$@ hour", comment: ""), "1"))
        case let x where x >= 20160: // expired
            sendSensorExpiredNotification()
        default:
            break
        }

        UserDefaults.standard.lastSensorAge = data.wearTimeMinutes
    }

    private static func sendSensorExpiringNotification(body: String) {
        ensureCanSendNotification { ensured in
            guard ensured else {
                return
            }

            let notification = UNMutableNotificationContent()
            notification.title = LocalizedString("Notification Title: Sensor ending soon", comment: "")
            notification.body = body
            notification.sound = .default

            add(identifier: .sensorExpire, content: notification)
        }
    }

    private static func sendSensorExpiredNotification() {
        ensureCanSendNotification { ensured in
            guard ensured else {
                return
            }

            let notification = UNMutableNotificationContent()
            notification.title = LocalizedString("Notification Title: Sensor expired", comment: "")
            notification.body = LocalizedString("Notification Body: Please replace your old sensor as soon as possible", comment: "")
            notification.sound = .default

            add(identifier: .sensorExpire, content: notification)
        }
    }
    
    private static func playVibrate() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
    
    private static func playAlarm() {
        AudioServicesPlaySystemSound(1304)
    }
}
