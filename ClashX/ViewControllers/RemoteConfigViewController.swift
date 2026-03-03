//
//  RemoteConfigViewController.swift
//  ClashX
//
//  Created by yicheng on 2019/7/28.
//  Copyright © 2019 west2online. All rights reserved.
//

import Cocoa
import RxSwift

class RemoteConfigViewController: NSViewController {
    @IBOutlet var tableView: NSTableView!
    @IBOutlet var deleteButton: NSButton!
    @IBOutlet var updateButton: NSButton!

    private var latestAddedConfig: RemoteConfigModel?

    let disposeBag = DisposeBag()

    deinit {
        print("RemoteConfigViewController deinit")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        updateButtonStatus()
        tableView.doubleAction = #selector(tableViewDidDoubleClick(tableView:))

        NotificationCenter.default
            .rx.notification(Notification.Name("didGetUrl")).bind {
                [weak self] note in
                guard let self = self else { return }
                guard let url = note.userInfo?["url"] as? String else { return }

                let name = note.userInfo?["name"] as? String
                self.showAdd(defaultUrl: url, name: name, allowAlt: true)
            }.disposed(by: disposeBag)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        view.window?.level = .floating
        NSApp.activate(ignoringOtherApps: true)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        RemoteConfigManager.shared.saveConfigs()
    }

    // MARK: Actions

    @IBAction func actionAdd(_ sender: Any) {
        showAdd()
    }

    @IBAction func actionDelete(_ sender: Any) {
        RemoteConfigManager.shared.configs.safeRemove(at: tableView.selectedRow)
        tableView.reloadData()
        updateButtonStatus()
    }

    @IBAction func actionUpdate(_ sender: Any) {
        guard let model = RemoteConfigManager.shared.configs[safe: tableView.selectedRow] else { return }
        requestUpdate(config: model)
        tableView.reloadDataKeepingSelection()
    }
}

extension RemoteConfigViewController {
    func updateButtonStatus() {
        let selectIdx = tableView.selectedRow
        if selectIdx == -1 {
            deleteButton.isEnabled = false
            updateButton.isEnabled = false
            return
        }

        guard let config = RemoteConfigManager.shared.configs[safe: selectIdx] else { return }
        deleteButton.isEnabled = true
        updateButton.isEnabled = !config.updating
    }

    func showAdd(defaultUrl: String? = nil,
                 defaultName: String? = nil,
                 name: String? = nil,
                 allowAlt: Bool = false) {
        let alertView = NSAlert()
        alertView.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alertView.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        alertView.messageText = NSLocalizedString("Add a remote config", comment: "")
        let remoteConfigInputView = RemoteConfigAddView.createFromNib()
        if let defaultUrl = defaultUrl {
            remoteConfigInputView.setUrl(string: defaultUrl, name: name, defaultName: defaultName)
        }
        alertView.accessoryView = remoteConfigInputView
        let response = alertView.runModal()

        guard response == .alertFirstButtonReturn else { return }
        guard remoteConfigInputView.isVaild() else {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Invalid input", comment: "")
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        let configName = remoteConfigInputView.getConfigName().0
        let isPlaceHolderName = remoteConfigInputView.getConfigName().1
        let configUrl = remoteConfigInputView.getUrlString()
        let password = remoteConfigInputView.getPassword()

        if let existed = RemoteConfigManager.shared.configs.first(where: { $0.name == configName }) {
            guard allowAlt else {
                NSAlert.alert(with: NSLocalizedString("The remote config name is duplicated", comment: ""))
                return
            }
            existed.url = configUrl
            latestAddedConfig = existed
            requestUpdate(config: existed, password: password.isEmpty ? nil : password)
        } else {
            let remoteConfig = RemoteConfigModel(url: configUrl,
                                                 name: configName,
                                                 updateTime: nil)
            remoteConfig.isPlaceHolderName = !isPlaceHolderName
            RemoteConfigManager.shared.configs.append(remoteConfig)
            latestAddedConfig = remoteConfig
            requestUpdate(config: remoteConfig, password: password.isEmpty ? nil : password)
        }

        tableView.reloadData()
        updateButtonStatus()
    }

    func requestUpdate(config: RemoteConfigModel, password: String? = nil) {
        guard !config.updating else { return }
        config.updating = true
        RemoteConfigManager.updateConfig(config: config, password: password) {
            [weak self, weak config] errorString in
            guard let self = self, let config = config else { return }
            config.updating = false
            if let errorString = errorString {
                let errLower = errorString.lowercased()
                let isDecryptError = errLower.contains("password") || errLower.contains("encrypt") || errLower.contains("decrypt") || errorString.contains("解密")
                if isDecryptError {
                    self.showDecryptPasswordPrompt(config: config, errorMessage: errorString) { [weak self] enteredPassword in
                        guard let self = self else { return }
                        if let pwd = enteredPassword, !pwd.isEmpty {
                            self.requestUpdate(config: config, password: pwd)
                        } else {
                            if config == self.latestAddedConfig {
                                RemoteConfigManager.shared.configs.removeAll { $0.name == config.name }
                                RemoteConfigManager.shared.saveConfigs()
                                self.latestAddedConfig = nil
                            }
                            self.tableView.reloadData()
                            self.updateButtonStatus()
                        }
                    }
                } else {
                    if config == self.latestAddedConfig {
                        RemoteConfigManager.shared.configs.removeAll { $0.name == config.name }
                        RemoteConfigManager.shared.saveConfigs()
                        self.latestAddedConfig = nil
                        self.tableView.reloadData()
                        self.updateButtonStatus()
                    }
                    let alert = NSAlert()
                    alert.messageText = errorString
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            } else {
                config.updateTime = Date()
                RemoteConfigManager.shared.saveConfigs()

                if config == self.latestAddedConfig {
                    AppDelegate.shared.updateConfig(configName: config.name)
                } else if config.name == ConfigManager.selectConfigName {
                    AppDelegate.shared.updateConfig()
                }
            }
            self.tableView.reloadDataKeepingSelection()
        }
    }

    /// 加密/解密错误时弹出输入密码对话框，用户可输入后重试或取消
    private func showDecryptPasswordPrompt(config: RemoteConfigModel, errorMessage: String, completion: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = errorMessage
        alert.alertStyle = .warning
        alert.informativeText = NSLocalizedString("Enter website login password and tap Retry.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Retry", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))

        let label = NSTextField(labelWithString: NSLocalizedString("Website login password:", comment: "Add remote config dialog"))
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.frame = NSRect(x: 0, y: 28, width: 140, height: 18)

        let passwordField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 22))
        passwordField.placeholderString = NSLocalizedString("Website login password:", comment: "")
        passwordField.font = .systemFont(ofSize: NSFont.systemFontSize)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 52))
        container.addSubview(label)
        container.addSubview(passwordField)

        alert.accessoryView = container
        DispatchQueue.main.async {
            alert.window?.makeFirstResponder(passwordField)
        }
        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            let pwd = passwordField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            completion(pwd.isEmpty ? nil : pwd)
        } else {
            completion(nil)
        }
    }
}

extension RemoteConfigViewController: NSTableViewDelegate {
    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtonStatus()
    }

    @objc func tableViewDidDoubleClick(tableView: NSTableView) {
        let row = tableView.clickedRow
        guard let config = RemoteConfigManager.shared.configs[safe: row] else { return }
        if config.isPlaceHolderName {
            showAdd(defaultUrl: config.url, defaultName: config.name, name: nil, allowAlt: true)
        } else {
            showAdd(defaultUrl: config.url, defaultName: nil, name: config.name, allowAlt: true)
        }
    }
}

extension RemoteConfigViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return RemoteConfigManager.shared.configs.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let config = RemoteConfigManager.shared.configs[safe: row] else { return nil }

        func setupCell(withIdentifier: String, string: String, textFieldtag: Int = 1) -> NSView? {
            let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: withIdentifier), owner: nil)
            if let textField = cell?.viewWithTag(1) as? NSTextField {
                textField.stringValue = string
            } else {
                assertionFailure()
            }

            return cell
        }

        switch tableColumn?.identifier.rawValue ?? "" {
        case "url":
            return setupCell(withIdentifier: "urlCell", string: config.url)
        case "configName":
            return setupCell(withIdentifier: "nameCell", string: config.name)
        case "updateTime":
            return setupCell(withIdentifier: "timeCell", string: config.displayingTimeString())

        default: assertionFailure()
        }
        return nil
    }
}

class RemoteConfigAddView: NSView, NibLoadable {
    @IBOutlet private var urlTextField: NSTextField!
    @IBOutlet private var configNameTextField: NSTextField!
    @IBOutlet private(set) var passwordLabel: NSTextField!
    @IBOutlet private(set) var passwordSecureField: NSSecureTextField!
    @IBOutlet private(set) var passwordPlainField: NSTextField!
    @IBOutlet private(set) var showPasswordButton: NSButton!

    private var isPasswordVisible = false

    override func awakeFromNib() {
        super.awakeFromNib()
        passwordLabel.stringValue = NSLocalizedString("Website login password:", comment: "Add remote config dialog")
        showPasswordButton.title = NSLocalizedString("Show", comment: "Password field")
    }

    func getUrlString() -> String {
        return urlTextField.stringValue
    }

    /// Get the config name
    /// - Returns: return (name, isUserInput)
    func getConfigName() -> (String, Bool) {
        if !configNameTextField.stringValue.isEmpty {
            return (configNameTextField.stringValue, true)
        }
        return (configNameTextField.placeholderString ?? "", false)
    }

    func getPassword() -> String {
        if isPasswordVisible {
            return passwordPlainField.stringValue
        }
        return passwordSecureField.stringValue
    }

    func isVaild() -> Bool {
        return urlTextField.stringValue.isUrlVaild() && !getConfigName().0.isEmpty
    }

    /// Call to make password field first responder (e.g. when decrypt error)
    func focusPasswordField() {
        window?.makeFirstResponder(isPasswordVisible ? passwordPlainField : passwordSecureField)
    }

    @IBAction func togglePasswordVisibility(_ sender: Any) {
        isPasswordVisible.toggle()
        if isPasswordVisible {
            passwordPlainField.stringValue = passwordSecureField.stringValue
            passwordPlainField.isHidden = false
            passwordSecureField.isHidden = true
            showPasswordButton.title = NSLocalizedString("Hide", comment: "Password field")
        } else {
            passwordSecureField.stringValue = passwordPlainField.stringValue
            passwordSecureField.isHidden = false
            passwordPlainField.isHidden = true
            showPasswordButton.title = NSLocalizedString("Show", comment: "Password field")
        }
    }

    func setUrl(string: String, name: String? = nil, defaultName: String?) {
        urlTextField.stringValue = string

        if let name = name, !name.isEmpty {
            configNameTextField.stringValue = name
        }

        if let defaultName = defaultName, !defaultName.isEmpty {
            configNameTextField.placeholderString = defaultName
        }

        if name == nil && defaultName == nil {
            updateConfigName()
        }
    }

    private func updateConfigName() {
        guard urlTextField.stringValue.isUrlVaild() else { return }
        let urlString = urlTextField.stringValue
        configNameTextField.placeholderString = URL(string: urlString)?.host ?? "unknown"
    }
}

extension RemoteConfigAddView: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        updateConfigName()
    }
}
