import Flutter
import Security
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let channelName = "com.geumyi.gscm/secure_storage"
  private let defaultsSuite = "gscm_local_v2"
  private let keychainService = "com.geumyi.gscm"
  private let keychainAccount = "device-token-v1"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "SECURE_STORE", message: "AppDelegate unavailable", details: nil))
        return
      }

      do {
        switch call.method {
        case "deviceId":
          result(try self.deviceId())
        case "deviceName":
          result(self.deviceName())
        case "loadConnection":
          result(try self.loadConnection())
        case "saveConnection":
          guard let args = call.arguments as? [String: Any] else {
            throw SecureStoreError.invalidArguments
          }
          let host = (args["host"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
          let token = (args["token"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
          let deviceId = (args["deviceId"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
          let rawDeviceName = (args["deviceName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
          guard !host.isEmpty, !token.isEmpty, !deviceId.isEmpty else {
            throw SecureStoreError.invalidArguments
          }
          try self.saveConnection(
            host: host,
            token: token,
            deviceId: deviceId,
            deviceName: rawDeviceName.isEmpty ? self.deviceName() : rawDeviceName
          )
          result(nil)
        case "clearConnection":
          try self.clearConnection()
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(code: "SECURE_STORE", message: error.localizedDescription, details: nil))
      }
    }
  }

  private var defaults: UserDefaults {
    UserDefaults(suiteName: defaultsSuite) ?? .standard
  }

  private func deviceId() throws -> String {
    if let existing = defaults.string(forKey: "device_id")?.trimmingCharacters(in: .whitespacesAndNewlines), !existing.isEmpty {
      return existing
    }
    let created = "ios-\(UUID().uuidString.lowercased())"
    defaults.set(created, forKey: "device_id")
    return created
  }

  private func deviceName() -> String {
    let name = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? "iPhone" : name
  }

  private func saveConnection(host: String, token: String, deviceId: String, deviceName: String) throws {
    try writeToken(token)
    defaults.set(host, forKey: "host")
    defaults.set(deviceId, forKey: "device_id")
    defaults.set(deviceName, forKey: "device_name")
  }

  private func loadConnection() throws -> [String: String]? {
    let host = defaults.string(forKey: "host")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !host.isEmpty, let token = try readToken(), !token.isEmpty else {
      return nil
    }
    return [
      "host": host,
      "token": token,
      "deviceId": try deviceId(),
      "deviceName": defaults.string(forKey: "device_name")?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? deviceName()
    ]
  }

  private func clearConnection() throws {
    defaults.removeObject(forKey: "host")
    defaults.removeObject(forKey: "device_name")
    try deleteToken()
  }

  private func baseKeychainQuery() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: keychainAccount
    ]
  }

  private func writeToken(_ token: String) throws {
    let data = Data(token.utf8)
    var query = baseKeychainQuery()
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    ]

    let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if updateStatus == errSecSuccess { return }
    if updateStatus != errSecItemNotFound {
      throw SecureStoreError.keychain(updateStatus)
    }

    query.merge(attributes) { _, new in new }
    let addStatus = SecItemAdd(query as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
      throw SecureStoreError.keychain(addStatus)
    }
  }

  private func readToken() throws -> String? {
    var query = baseKeychainQuery()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else {
      throw SecureStoreError.keychain(status)
    }
    guard let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
      throw SecureStoreError.invalidKeychainData
    }
    return token.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func deleteToken() throws {
    let status = SecItemDelete(baseKeychainQuery() as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw SecureStoreError.keychain(status)
    }
  }
}

private enum SecureStoreError: LocalizedError {
  case invalidArguments
  case invalidKeychainData
  case keychain(OSStatus)

  var errorDescription: String? {
    switch self {
    case .invalidArguments:
      return "Invalid secure-storage arguments"
    case .invalidKeychainData:
      return "Invalid token data in Apple Keychain"
    case .keychain(let status):
      return "Apple Keychain error (OSStatus \(status))"
    }
  }
}

private extension String {
  var nonEmpty: String? { isEmpty ? nil : self }
}
