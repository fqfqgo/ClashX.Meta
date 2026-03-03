//
//  RemoteConfigManager.swift
//  ClashX
//
//  Created by yicheng on 2018/11/6.
//  Copyright © 2018 west2online. All rights reserved.
//

import Alamofire
import Cocoa

class RemoteConfigManager {
    var configs: [RemoteConfigModel] = []
    var refreshActivity: NSBackgroundActivityScheduler?

    static let shared = RemoteConfigManager()

    private init() {
        if let savedConfigs = UserDefaults.standard.object(forKey: "kRemoteConfigs") as? Data {
            let decoder = JSONDecoder()
            if let loadedConfig = try? decoder.decode([RemoteConfigModel].self, from: savedConfigs) {
                configs = loadedConfig
            } else {
                assertionFailure()
            }
        }
        migrateOldRemoteConfig()
        setupAutoUpdateTimer()
    }

    func saveConfigs() {
        Logger.log("Saving Remote Config Setting")
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(configs) {
            UserDefaults.standard.set(encoded, forKey: "kRemoteConfigs")
        }
    }

    func migrateOldRemoteConfig() {
        if let url = UserDefaults.standard.string(forKey: "kRemoteConfigUrl"),
           let name = URL(string: url)?.host {
            configs.append(RemoteConfigModel(url: url, name: name))
            UserDefaults.standard.removeObject(forKey: "kRemoteConfigUrl")
            saveConfigs()
        }
    }

    func setupAutoUpdateTimer() {
        refreshActivity?.invalidate()
        refreshActivity = nil
        guard RemoteConfigManager.autoUpdateEnable else {
            Logger.log("autoUpdateEnable did not enable,autoUpateTimer invalidated.")
            return
        }
        Logger.log("set up autoUpateTimer")

        refreshActivity = NSBackgroundActivityScheduler(identifier: "com.ClashX.configupdate")
        refreshActivity?.repeats = true
        refreshActivity?.interval = 60 * 60 * 2 // Two hour
        refreshActivity?.tolerance = 60 * 60

        refreshActivity?.schedule { [weak self] completionHandler in
            self?.autoUpdateCheck()
            completionHandler(NSBackgroundActivityScheduler.Result.finished)
        }
    }

    static var autoUpdateEnable: Bool {
        get {
            return UserDefaults.standard.object(forKey: "kAutoUpdateEnable") as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "kAutoUpdateEnable")
            RemoteConfigManager.shared.setupAutoUpdateTimer()
        }
    }

    @objc func autoUpdateCheck() {
        guard RemoteConfigManager.autoUpdateEnable else { return }
        Logger.log("Tigger config auto update check")
        updateCheck()
    }

    func updateCheck(ignoreTimeLimit: Bool = false, showNotification: Bool = false) {
        let currentConfigName = ConfigManager.selectConfigName

        let group = DispatchGroup()

        for config in configs {
            if config.updating { continue }
            let timeLimitNoMantians = Date().timeIntervalSince(config.updateTime ?? Date(timeIntervalSince1970: 0)) < Settings.configAutoUpdateInterval

            if timeLimitNoMantians && !ignoreTimeLimit {
                Logger.log("[Auto Upgrade] Bypassing \(config.name) due to time check")
                continue
            }
            Logger.log("[Auto Upgrade] Requesting \(config.name)")
            let isCurrentConfig = config.name == currentConfigName
            config.updating = true
            group.enter()
            RemoteConfigManager.updateConfig(config: config) {
                [weak config] error in
                guard let config = config else { return }

                config.updating = false
                group.leave()
                if error == nil {
                    config.updateTime = Date()
                }

                if isCurrentConfig {
                    if let error = error {
                        // Fail
                        if showNotification {
							UserNotificationCenter.shared.post(title: NSLocalizedString("Remote Config Update Fail", comment: ""),
                                      info: "\(config.name): \(error)")
                        }

                    } else {
                        // Success
                        if showNotification {
                            let info = "\(config.name): \(NSLocalizedString("Succeed!", comment: ""))"
							UserNotificationCenter.shared.post(title: NSLocalizedString("Remote Config Update", comment: ""), info: info)
                        }
                        AppDelegate.shared.updateConfig(showNotification: false)
                    }
                }
                Logger.log("[Auto Upgrade] Finish \(config.name) result: \(error ?? "succeed")")
            }
        }

        group.notify(queue: .main) {
            [weak self] in
            self?.saveConfigs()
        }
    }

    /// Fetches remote config. If response has Subscription-Encryption: true, decrypts with password (or keychain).
    /// - Parameters:
    ///   - config: Remote config model
    ///   - password: Password from UI when adding; nil will use keychain for existing config
    ///   - complete: (content, suggestedFilename, errorMessage). If errorMessage != nil, content is nil.
    static func getRemoteConfigData(config: RemoteConfigModel, password: String? = nil, complete: @escaping ((String?, String?, String?) -> Void)) {
        guard var urlRequest = try? URLRequest(url: config.url, method: .get) else {
            Logger.log("[getRemoteConfigData] url incorrect, \(config.name) \(config.url)")
            complete(nil, nil, NSLocalizedString("Invalid URL", comment: ""))
            return
        }
        urlRequest.cachePolicy = .reloadIgnoringCacheData

        AF.request(urlRequest)
            .validate()
            .responseData { res in
                switch res.result {
                case .failure(let err):
                    complete(nil, nil, err.localizedDescription)
                    return
                case .success(let data):
                    let suggestedFilename = res.response?.suggestedFilename
                    let encHeader = (res.response as? HTTPURLResponse)?.value(forHTTPHeaderField: kSubscriptionEncryptionHeader)
                    if isSubscriptionEncrypted(headerValue: encHeader) {
                        let pwd = password?.isEmpty == false ? password : SubscriptionPasswordStorage.getPassword(forConfigName: config.name)
                        if pwd == nil || pwd?.isEmpty == true {
                            complete(nil, nil, NSLocalizedString("Subscription encrypted, please enter website login password", comment: ""))
                            return
                        }
                        guard let decrypted = tryDecryptSubscription(password: pwd!, base64Data: data),
                              let str = String(data: decrypted, encoding: .utf8) else {
                            complete(nil, nil, NSLocalizedString("Decryption failed, please check password", comment: ""))
                            return
                        }
                        complete(str, suggestedFilename, nil)
                    } else {
                        if let str = String(data: data, encoding: .utf8) {
                            complete(str, suggestedFilename, nil)
                        } else {
                            complete(nil, nil, NSLocalizedString("Download fail", comment: ""))
                        }
                    }
                }
            }
    }

    static func updateConfig(config: RemoteConfigModel, password: String? = nil, complete: ((String?) -> Void)? = nil) {
        if let pwd = password, !pwd.isEmpty {
            SubscriptionPasswordStorage.savePassword(pwd, forConfigName: config.name)
        }
        getRemoteConfigData(config: config, password: password) { configString, suggestedFilename, errorMessage in
            if let err = errorMessage {
                complete?(err)
                return
            }
            guard let newConfig = configString else {
                complete?(NSLocalizedString("Download fail", comment: ""))
                return
            }

            let verifyRes = verifyConfig(string: newConfig)
            if let error = verifyRes {
                complete?(NSLocalizedString("Remote Config Format Error", comment: "") + ": " + error)
                return
            }

            if let suggestName = suggestedFilename, config.isPlaceHolderName {
                let name = URL(fileURLWithPath: suggestName).deletingPathExtension().lastPathComponent
                if !shared.configs.contains(where: { $0.name == name }) {
                    config.name = name
                }
            }
            config.isPlaceHolderName = false

            if ICloudManager.shared.useiCloud.value {
                ConfigFileManager.shared.stopWatchConfigFile()
            }
            if config.name == ConfigManager.selectConfigName {
                ConfigFileManager.shared.pauseForNextChange()
            }

            let saveAction: ((String) -> Void) = {
                savePath in
                do {
                    if FileManager.default.fileExists(atPath: savePath) {
                        try FileManager.default.removeItem(atPath: savePath)
                    }
                    try newConfig.write(to: URL(fileURLWithPath: savePath), atomically: true, encoding: .utf8)
                    complete?(nil)
                } catch let err {
                    complete?(err.localizedDescription)
                }
            }

            if ICloudManager.shared.useiCloud.value {
                ICloudManager.shared.getUrl { url in
                    guard let url = url else { return }
                    let saveUrl = url.appendingPathComponent(Paths.configFileName(for: config.name))
                    saveAction(saveUrl.path)
                }
            } else {
                let savePath = Paths.localConfigPath(for: config.name)
                saveAction(savePath)
            }
        }
    }

    static func createCacheConfig(string: String) -> String? {
		let path = Paths.tempPath() + "/cacheConfigs"
        let confPath = path + "/\(UUID().uuidString).yaml"

        let fm = FileManager.default
        try? fm.createDirectory(atPath: path, withIntermediateDirectories: true)

        if fm.fileExists(atPath: confPath) {
            try? fm.removeItem(atPath: confPath)
        }

        guard fm.createFile(atPath: confPath, contents: string.data(using: .utf8)) else {
            return nil
        }
        return confPath
    }

    static func verifyConfig(string: String) -> ErrorString? {
        guard let confPath = createCacheConfig(string: string) else {
            return "Create verify config file failed"
        }
		
        return (NSApplication.shared.delegate as? AppDelegate)?.clashProcess.verify(kConfigFolderPath, confFilePath: confPath)
    }

    static func showAdd() {
        let alertView = NSAlert()
        alertView.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alertView.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        alertView.messageText = NSLocalizedString("Update remote config update interval", comment: "")
        let setupView = RemoteConfigUpdateIntervalSettingView()
        setupView.frame = NSRect(x: 0, y: 0, width: 100, height: 22)
        alertView.accessoryView = setupView
        let response = alertView.runModal()

        guard response == .alertFirstButtonReturn else { return }
        let stringValue = setupView.textfield.stringValue
        guard let intValue = Int(stringValue), intValue > 0 else {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.informativeText = NSLocalizedString("Should be a least 1 hour", comment: "")
            alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
            alert.runModal()
            return
        }
        Settings.configAutoUpdateInterval = TimeInterval(intValue * 60 * 60)
        RemoteConfigManager.shared.autoUpdateCheck()
    }
}
