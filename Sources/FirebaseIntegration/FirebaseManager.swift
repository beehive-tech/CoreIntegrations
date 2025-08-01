
import FirebaseAnalytics
import FirebaseCore
import FirebaseRemoteConfig

public class FirebaseManager {
    public private(set) var remoteConfigResult: [String: String]? = nil
    public private(set) var internalConfigResult: [String: String]? = nil
    public private(set) var install_server_path: String? = nil
    public private(set) var purchase_server_path: String? = nil
    
    private let kInstallURL = "install_server_path"
    private let kPurchaseURL = "purchase_server_path"
    
    public init() {
        
    }
    
    public static var externalConfiguration: (() -> ())?
    
    public func configure(completion: @escaping () -> Void) {
        Self.externalConfiguration?() ?? FirebaseApp.configure()
        Analytics.logEvent("Firebase Init", parameters: nil)
        
        completion()
    }
    
    public func setUserID(_ id: String) {
        Analytics.setUserID(id)
    }
    
    public func fetchRemoteConfig(_ appConfigurables: [any FirebaseConfigurable], completion: @escaping () -> Void) {
        let remoteConfig = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        
        settings.minimumFetchInterval = 0
        
        remoteConfig.configSettings = settings
        remoteConfig.fetchAndActivate { status, error in
            guard error == nil else {
                completion()
                return
            }
            
            let allKeys = appConfigurables.map { $0.key }
            let configResult = allKeys.reduce(into: [String: String]()) { partialResult, key in
                let configValue = remoteConfig.configValue(forKey: key).stringValue
                if configValue != nil && configValue != "" {
                    partialResult[key] = configValue
                }
            }
            
            self.install_server_path = remoteConfig.configValue(forKey: self.kInstallURL).stringValue
            self.purchase_server_path = remoteConfig.configValue(forKey: self.kPurchaseURL).stringValue
            
            self.internalConfigResult = remoteConfig.keys(withPrefix: "").reduce(into: [String:String](), { partialResult, key in
                let configValue = remoteConfig.configValue(forKey: key).stringValue
                if configValue != nil && configValue != "" {
                    partialResult[key] = configValue
                }
            })
            
            self.remoteConfigResult = configResult
            completion()
        }
    }
}
