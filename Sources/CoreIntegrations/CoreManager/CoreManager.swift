
import UIKit
#if !COCOAPODS
import AppsflyerIntegration
import FacebookIntegration
import AttributionServerIntegration
import PurchasesIntegration
import AnalyticsIntegration
import FirebaseIntegration
import SentryIntegration
import AttestationIntegration
#endif
import AppTrackingTransparency
import Foundation
import StoreKit

/*
    I think it would be good to split CoreManager into different manager parts - for default configuration, for additional configurations like analytics, test_distribution etc, and for purchases and purchases attribution part
 */
public class CoreManager {
    public static var shared: CoreManagerProtocol = internalShared
    static var internalShared = CoreManager()
        
    public static var uniqueUserID: String? {
        return AttributionServerManager.shared.uniqueUserID
    }
    
    public static var sentry:PublicSentryManagerProtocol {
        return SentryManager.shared
    }
    
    var attAnswered: Bool = false
    var isConfigured: Bool = false
    
    var configuration: CoreConfigurationProtocol?
    var appsflyerManager: AppfslyerManagerProtocol?
    var facebookManager: FacebookManagerProtocol?
    var purchaseManager: PurchasesManagerProtocol?
    
    var remoteConfigManager: CoreRemoteConfigManager?
    var analyticsManager: AnalyticsManager?
    var sentryManager: InternalSentryManagerProtocol = SentryManager.shared
    
    var delegate: CoreManagerDelegate?
    
    var configurationResultManager = ConfigurationResultManager()
    
    
    func configureAll(configuration: CoreConfigurationProtocol) {
        guard isConfigured == false else {
            return
        }
        isConfigured = true
        
        let environmentVariables = ProcessInfo.processInfo.environment
        if let _ = environmentVariables["xctest_skip_config"] {
            
            let xc_network = environmentVariables["xctest_network"] ?? "organic"
            let xc_activePaywallName = environmentVariables["xctest_activePaywallName"] ?? "none"
            
            if let xc_screen_style_full = environmentVariables["xc_screen_style_full"] {
                let screen_style_full = configuration.remoteConfigDataSource.allConfigs.first(where: {$0.key == "subscription_screen_style_full"})
                screen_style_full?.updateValue(xc_screen_style_full)
            }
            
            if let xc_screen_style_h = environmentVariables["xc_screen_style_h"] {
                let hardPaywall = configuration.remoteConfigDataSource.allConfigs.first(where: {$0.key == "subscription_screen_style_h"})
                hardPaywall?.updateValue(xc_screen_style_h)
            }
            
            let result = CoreManagerResult(userSource: CoreUserSource(rawValue: xc_network),
                                           activePaywallName: xc_activePaywallName,
                                           organicPaywallName: xc_activePaywallName,
                                           asaPaywallName: xc_activePaywallName,
                                           facebookPaywallName: xc_activePaywallName,
                                           googlePaywallName: xc_activePaywallName,
                                           googleGDNPaywallName: xc_activePaywallName,
                                           googleDemGenPaywallName: xc_activePaywallName,
                                           googleYouTubePaywallName: xc_activePaywallName,
                                           googlePMaxPaywallName: xc_activePaywallName,
                                           snapchatPaywallName: xc_activePaywallName,
                                           tiktokPaywallName: xc_activePaywallName,
                                           instagramPaywallName: xc_activePaywallName,
                                           bingPaywallName: xc_activePaywallName,
                                           molocoPaywallName: xc_activePaywallName,
                                           applovinPaywallName: xc_activePaywallName)
            
            purchaseManager = PurchasesManager.shared
            purchaseManager?.initialize(allIdentifiers: configuration.paywallDataSource.allPurchaseIDs, proIdentifiers: configuration.paywallDataSource.allProPurchaseIDs)
            
            self.delegate?.coreConfigurationFinished(result: result)
            return
        }
        
        self.configuration = configuration
        
        if let sentryDataSource = configuration.sentryConfigDataSource {
            let sentryConfig = SentryConfigData(dsn: sentryDataSource.dsn,
                                                debug: sentryDataSource.debug,
                                                tracesSampleRate: sentryDataSource.tracesSampleRate,
                                                profilesSampleRate: sentryDataSource.profilesSampleRate,
                                                shouldCaptureHttpRequests: sentryDataSource.shouldCaptureHttpRequests,
                                                httpCodesRange: sentryDataSource.httpCodesRange,
                                                handledDomains: sentryDataSource.handledDomains,
                                                diagnosticLevel: sentryDataSource.diagnosticLevel)
            sentryManager.configure(sentryConfig)
        }

        analyticsManager = AnalyticsManager.shared
        
        let amplitudeCustomURL = configuration.amplitudeDataSource.customServerURL
        analyticsManager?.configure(appKey: configuration.appSettings.amplitudeSecret, 
                                    cnConfig: AppEnvironment.isChina,
                                    customURL: amplitudeCustomURL)
        
        sendStoreCountryUserProperty()
        configuration.appSettings.launchCount += 1
        if configuration.appSettings.isFirstLaunch {
            sendAppEnvironmentProperty()
            sendFirstLaunchEvent()
        }
        
        let allConfigurationEvents: [any ConfigurationEvent] = InternalConfigurationEvent.allCases + (configuration.initialConfigurationDataSource?.allEvents ?? [])
        let configurationEventsModel = CoreConfigurationModel(allConfigurationEvents: allConfigurationEvents)
        AppConfigurationManager.shared = AppConfigurationManager(model: configurationEventsModel,
                                                                 isFirstStart: configuration.appSettings.isFirstLaunch,
                                                                 timeout: configuration.configurationTimeout)
        
        appsflyerManager = AppfslyerManager(config: configuration.appsflyerConfig)
        appsflyerManager?.delegate = self
        
        facebookManager = FacebookManager()
        
        purchaseManager = PurchasesManager.shared
        
        let attributionToken = configuration.appSettings.attributionServerSecret
        let facebookData = AttributionFacebookModel(fbUserId: facebookManager?.userID ?? "",
                                                    fbUserData: facebookManager?.userData ?? "",
                                                    fbAnonId: facebookManager?.anonUserID ?? "")
        let appsflyerToken = appsflyerManager?.appsflyerID
        
        purchaseManager?.initialize(allIdentifiers: configuration.paywallDataSource.allPurchaseIDs, proIdentifiers: configuration.paywallDataSource.allProPurchaseIDs)

        remoteConfigManager = CoreRemoteConfigManager(cnConfig: AppEnvironment.isChina)
        
        let installPath = "/install-application"
        let purchasePath = "/subscribe"
        let installURLPath = configuration.attributionServerDataSource.installPath
        let purchaseURLPath = configuration.attributionServerDataSource.purchasePath
        
        let attributionConfiguration = AttributionConfigData(authToken: attributionToken,
                                                             installServerURLPath: installURLPath,
                                                             purchaseServerURLPath: purchaseURLPath,
                                                             installPath: installPath,
                                                             purchasePath: purchasePath,
                                                             appsflyerID: appsflyerToken,
                                                             appEnvironment: AppEnvironment.current.rawValue,
                                                             facebookData: facebookData)
        
        AttributionServerManager.shared.configure(config: attributionConfiguration)
        
        if configuration.useDefaultATTRequest {
            configureATT()
        }

        handleConfigurationEndCallback()
        
        handleAttributionInstall()
    }
    
    func configureATT() {
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification,
                                               object: nil)
    }
    
    @objc public func applicationDidBecomeActive() {
        let savedIDFV = AttributionServerManager.shared.installResultData?.idfv
        let uuid = AttributionServerManager.shared.savedUserUUID
       
        let id: String?
        if savedIDFV != nil {
            id = AttributionServerManager.shared.uniqueUserID
        } else {
            id = uuid ?? AttributionServerManager.shared.uniqueUserID
        }
        if let id, id != "" {
            appsflyerManager?.customerUserID = id
            appsflyerManager?.startAppsflyer()
            purchaseManager?.setUserID(id)
            self.facebookManager?.userID = id
            sentryManager.setUserID(id)
            
            self.remoteConfigManager?.configure(id: id) { [weak self] in
                guard let self = self else {return}
                remoteConfigManager?.fetchRemoteConfig(configuration?.remoteConfigDataSource.allConfigurables ?? []) {
                    InternalConfigurationEvent.remoteConfigLoaded.markAsCompleted()
                }
            }
            
            self.analyticsManager?.setUserID(id)
        }
        
        if configuration?.useDefaultATTRequest == true {
            requestATT()
        }
        
        Task {
            await purchaseManager?.updateProductStatus()
        }
    }
    
    public static var attAnsweredHandler: ((ATTrackingManager.AuthorizationStatus) -> ())?
    func requestATT() {
        let attStatus = ATTrackingManager.trackingAuthorizationStatus
        guard attStatus == .notDetermined else {
            self.sendATTProperty(answer: attStatus == .authorized)
            
            guard attAnswered == false else { return }
            attAnswered = true
            
            handleATTAnswered(attStatus)
            
            return
        }
                
        /*
         This stupid thing is made to be sure, that we'll handle ATT anyways, 100%
         And it looks like that apple has a bug, at least in sandbox, when ATT == .notDetermined
         but ATT alert for some reason not showing up, so it keeps unhandled and configuration never ends also
         The only problem this solution brings - if user really don't unswer ATT for more than 5 seconds -
         then we would think he didn't answer and the result would be false, even if he would answer true
         in more than 3 seconds
         */
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
            guard self?.attAnswered == false else { return }
            self?.attAnswered = true
            
            self?.sendAttEvent(answer: false)
            let status = ATTrackingManager.trackingAuthorizationStatus
            self?.handleATTAnswered(status)
        }
            
        ATTrackingManager.requestTrackingAuthorization { [weak self] status in
            guard self?.attAnswered == false else { return }
            self?.attAnswered = true
            
            self?.sendAttEvent(answer: status == .authorized)
            self?.handleATTAnswered(status)
        }
    }
    
    func handleATTAnswered(_ status: ATTrackingManager.AuthorizationStatus) {
        AppConfigurationManager.shared?.startTimoutTimer()
        
        InternalConfigurationEvent.attConcentGiven.markAsCompleted()
        if let configurationManager = AppConfigurationManager.shared {
            configurationManager.startTimoutTimer()
        } else {
            assertionFailure()
        }
        facebookManager?.configureATT(isAuthorized: status == .authorized)
        
        Self.attAnsweredHandler?(status)
    }
    
    func handleAttributionInstall() {
        guard let configurationManager = AppConfigurationManager.shared else {
            assertionFailure()
            return
        }
    
        configurationManager.signForAttAndConfigLoaded {
            let installPath = "/install-application"
            let purchasePath = "/subscribe"
            
            if let installURLPath = self.remoteConfigManager?.install_server_path,
               let purchaseURLPath = self.remoteConfigManager?.purchase_server_path,
               installURLPath != "",
               purchaseURLPath != "" {
                let attributionConfiguration = AttributionConfigURLs(installServerURLPath: installURLPath,
                                                                     purchaseServerURLPath: purchaseURLPath,
                                                                     installPath: installPath,
                                                                     purchasePath: purchasePath)
                
                AttributionServerManager.shared.configureURLs(config: attributionConfiguration)
            }else{
                if let serverDataSource = self.configuration?.attributionServerDataSource {
                    let installURLPath = serverDataSource.installPath
                    let purchaseURLPath = serverDataSource.purchasePath
                    
                    let attributionConfiguration = AttributionConfigURLs(installServerURLPath: installURLPath,
                                                                         purchaseServerURLPath: purchaseURLPath,
                                                                         installPath: installPath,
                                                                         purchasePath: purchasePath)
                    
                    AttributionServerManager.shared.configureURLs(config: attributionConfiguration)
                }
            }
            
            AttributionServerManager.shared.syncOnAppStart { result in
                InternalConfigurationEvent.attributionServerHandled.markAsCompleted()
            }
        }

    }
    
    func sendPurchaseToAttributionServer(_ details: PurchaseDetails) {
        let tlmamDetals = AttributionPurchaseModel(details)
        AttributionServerManager.shared.syncPurchase(data: tlmamDetals)
    }
    
    func sendPurchaseToFacebook(_ purchase: PurchaseDetails) {
        guard facebookManager != nil else {
            return
        }
       
        let isTrial = purchase.product.subscription?.introductoryOffer != nil
        let trialPrice = CGFloat(NSDecimalNumber(decimal: purchase.product.subscription?.introductoryOffer?.price ?? 0).floatValue)//introductoryPrice?.price.doubleValue ?? 0
        let price = CGFloat(NSDecimalNumber(decimal: purchase.product.price).floatValue)
        let currencyCode = purchase.product.priceFormatStyle.currencyCode
        let analData = FacebookPurchaseData(isTrial: isTrial,
                                            subcriptionID: purchase.product.id,
                                            trialPrice: trialPrice, price: price,
                                            currencyCode: currencyCode)
        self.facebookManager?.sendPurchaseAnalytics(analData)
    }
    
    func sendPurchaseToAppsflyer(_ purchase: PurchaseDetails) {
        guard appsflyerManager != nil else {
            return
        }
        
        let isTrial = purchase.product.subscription?.introductoryOffer != nil
        if isTrial {
            self.appsflyerManager?.logTrialPurchase()
        }
    }
    
    func handleConfigurationEndCallback() {
        guard let configurationManager = AppConfigurationManager.shared else {
            assertionFailure()
            return
        }
        
        configurationManager.signForConfigurationEnd { configurationResult in
            
            let result = self.getConfigurationResult(isFirstConfiguration: true)
            self.delegate?.coreConfigurationFinished(result: result)
            
            // calculate attribution
            // calculate correct paywall name
            // return everything to the app
        }
    }
    
    func handleConfigurationUpdate() {
        guard let configurationManager = AppConfigurationManager.shared else {
            assertionFailure()
            return
        }
        
        if configurationManager.configurationFinishHandled {
            let result = getConfigurationResult(isFirstConfiguration: false)
            self.delegate?.coreConfigurationUpdated(newResult: result)
        }
    }
    
    func getConfigurationResult(isFirstConfiguration: Bool) -> CoreManagerResult {
        let abTests = self.configuration?.remoteConfigDataSource.allABTests ?? InternalRemoteABTests.allCases
        let remoteResult = self.remoteConfigManager?.remoteConfigResult ?? [:]
        let asaResult = AttributionServerManager.shared.installResultData
        let isIPAT = asaResult?.isIPAT ?? false
        let deepLinkResult = self.appsflyerManager?.deeplinkResult ?? [:]
        let isASA = (asaResult?.asaAttribution["campaignName"] as? String != nil) ||
        (asaResult?.asaAttribution["campaign_name"] as? String != nil)
        
        var isRedirect = false
        var networkSource: CoreUserSource = .unknown
        
        if let networkValue = deepLinkResult["network"] {
            if networkValue.lowercased().contains("web2app_fb") ||
                networkValue.lowercased().contains("metaweb_int") ||
                networkValue.lowercased().contains("facebook_int") {
                networkSource = .facebook
            } else if networkValue.lowercased().contains("google_storeredirect") {
                networkSource = .google
            } else if networkValue.lowercased().contains("google_gdn") {
                networkSource = .google_gdn
            } else if networkValue.lowercased().contains("google_demgen") {
                networkSource = .google_demgen
            } else if networkValue.lowercased().contains("google_youtube") {
                networkSource = .google_youtube
            } else if networkValue.lowercased().contains("google_pmax") {
                networkSource = .google_pmax
            } else if networkValue.lowercased().contains("instagram") {
                networkSource = .instagram
            } else if networkValue.lowercased().contains("snapchat") {
                networkSource = .snapchat
            } else if networkValue.lowercased().contains("bing") {
                networkSource = .bing
            } else if networkValue.lowercased().contains("moloco_int") {
                networkSource = .moloco
            } else if networkValue.lowercased().contains("applovin_int") {
                networkSource = .applovin
            } else if networkValue == "Full_Access" {
                networkSource = .test_premium
            } else if networkValue.lowercased() == "tiktok_full_access" {
                let tiktok_config = self.remoteConfigManager?.internalConfigResult?["tiktok_full_access"] == "true"
                networkSource = tiktok_config ? .tiktok_full_access : .organic
            } else if networkValue.contains("tiktok") {
                networkSource = .tiktok
            } else if networkValue == "restricted" {
                if let fixedSource = self.configuration?.appSettings.paywallSourceForRestricted {
                    networkSource = fixedSource
                }
            } else if networkValue.lowercased() == "asa_test" {
                networkSource = .asa
            }
            else {
                networkSource = .unknown
            }
            
            isRedirect = true
        }
        
        var userSource: CoreUserSource
        
        if isIPAT {
            userSource = .ipat
        }else if isRedirect {
            userSource = networkSource
        }else if isASA {
            userSource = .asa
        }else {
            userSource = .organic
        }
        
        if isFirstConfiguration {
            let allConfigs = self.configuration?.remoteConfigDataSource.allConfigurables ?? []
            self.saveRemoteConfig(attribution: userSource, allConfigs: allConfigs, remoteResult: remoteResult)
                        
            self.sendABTestsUserProperties(abTests: abTests, userSource: userSource)
            self.sendTestDistributionEvent(abTests: abTests, deepLinkResult: deepLinkResult, userSource: userSource)
        } else {
            let allConfigs = InternalRemoteABTests.allCases
            self.saveRemoteConfig(attribution: userSource, allConfigs: allConfigs, remoteResult: remoteResult)
            self.sendABTestsUserProperties(abTests: abTests, userSource: userSource)
        }
        
        self.configurationResultManager.userSource = userSource
        self.configurationResultManager.deepLinkResult = deepLinkResult
        self.configurationResultManager.asaAttributionResult = asaResult?.asaAttribution
        
        let result = self.configurationResultManager.calculateResult()
        return result
    }
    
    func saveRemoteConfig(attribution: CoreUserSource, allConfigs: [any CoreFirebaseConfigurable],
                          remoteResult: [String: String]) {
        allConfigs.forEach { config in
            let remoteValue = remoteResult[config.key]
            
            guard let remoteValue else {
                return
            }
            
            let value: String
            if config.activeForSources.contains(attribution) {
                value = remoteValue
                config.updateValue(value)
            }
        }
    }
}

class ConfigurationResultManager {
    var userSource: CoreUserSource = .organic
    var asaAttributionResult: [String: String]?
    var deepLinkResult: [String: String]?
    
    func calculateResult() -> CoreManagerResult {
        // get appsflyer info
        
        let facebookPaywallName = self.getPaywallNameFromConfig(InternalRemoteABTests.ab_paywall_fb.value)
        let googlePaywallName = self.getPaywallNameFromConfig(InternalRemoteABTests.ab_paywall_google.value)
        let googleGDNPaywallName = self.getPaywallNameFromConfig(InternalRemoteABTests.ab_paywall_google_gdn.value)
        let googleDemGenPaywallName = self.getPaywallNameFromConfig(InternalRemoteABTests.ab_paywall_google_demgen.value)
        let googleYTPaywallName = self.getPaywallNameFromConfig(InternalRemoteABTests.ab_paywall_google_youtube.value)
        let googlePMaxPaywallName = self.getPaywallNameFromConfig(InternalRemoteABTests.ab_paywall_google_pmax.value)
        let asaPaywallName = self.getPaywallNameFromConfig(InternalRemoteABTests.ab_paywall_asa.value)
        let snapchatPaywallName = self.getPaywallNameFromConfig(InternalRemoteABTests.ab_paywall_snapchat.value)
        let tiktokPaywallName = self.getPaywallNameFromConfig(InternalRemoteABTests.ab_paywall_tiktok.value)
        let instagramPaywallName = self.getPaywallNameFromConfig(InternalRemoteABTests.ab_paywall_instagram.value)
        let bingPaywallName = self.getPaywallNameFromConfig(InternalRemoteABTests.ab_paywall_bing.value)
        let organicPaywallName = self.getPaywallNameFromConfig(InternalRemoteABTests.ab_paywall_organic.value)
        let molocoPaywallName = self.getPaywallNameFromConfig(InternalRemoteABTests.ab_paywall_moloco.value)
        let applovinPaywallName = self.getPaywallNameFromConfig(InternalRemoteABTests.ab_paywall_applovin.value)

        let activePaywallName: String
        var userSourceInfo: [String: String]? = deepLinkResult
        
        if let deepLinkValue: String = deepLinkResult?["deep_link_value"], deepLinkValue != "none", deepLinkValue != "",
           let firebaseValue = CoreManager.internalShared.remoteConfigManager?.internalConfigResult?[deepLinkValue] {
                activePaywallName = getPaywallNameFromConfig(firebaseValue)
            userSourceInfo = deepLinkResult
        }else{
            switch userSource {
            case .organic, .ipat, .test_premium, .tiktok_full_access, .unknown:
                activePaywallName = organicPaywallName
            case .asa:
                activePaywallName = asaPaywallName
                userSourceInfo = asaAttributionResult
            case .facebook:
                activePaywallName = facebookPaywallName
            case .google:
                activePaywallName = googlePaywallName
            case .google_gdn:
                activePaywallName = googleGDNPaywallName
            case .google_demgen:
                activePaywallName = googleDemGenPaywallName
            case .google_youtube:
                activePaywallName = googleYTPaywallName
            case .google_pmax:
                activePaywallName = googlePMaxPaywallName
            case .snapchat:
                activePaywallName = snapchatPaywallName
            case .tiktok:
                activePaywallName = tiktokPaywallName
            case .instagram:
                activePaywallName = instagramPaywallName
            case .bing:
                activePaywallName = bingPaywallName
            case .moloco:
                activePaywallName = molocoPaywallName
            case .applovin:
                activePaywallName = applovinPaywallName
            }
        }
        
        let coreManagerResult = CoreManagerResult(userSource: userSource,
                                                  userSourceInfo: userSourceInfo,
                                                  activePaywallName: activePaywallName,
                                                  organicPaywallName: organicPaywallName,
                                                  asaPaywallName: asaPaywallName,
                                                  facebookPaywallName: facebookPaywallName,
                                                  googlePaywallName: googlePaywallName,
                                                  googleGDNPaywallName: googleGDNPaywallName,
                                                  googleDemGenPaywallName: googleDemGenPaywallName,
                                                  googleYouTubePaywallName: googleYTPaywallName,
                                                  googlePMaxPaywallName: googlePMaxPaywallName,
                                                  snapchatPaywallName: snapchatPaywallName,
                                                  tiktokPaywallName: tiktokPaywallName,
                                                  instagramPaywallName: instagramPaywallName,
                                                  bingPaywallName: bingPaywallName,
                                                  molocoPaywallName: molocoPaywallName,
                                                  applovinPaywallName: applovinPaywallName)
        
        return coreManagerResult
    }
    
    private func getPaywallNameFromConfig(_ config: String) -> String {
        let paywallName: String
        let value = config
        if value.hasPrefix("none_") {
            paywallName = String(value.dropFirst("none_".count))
        } else {
            paywallName = value
        }
        return paywallName
    }
}

typealias PaywallName = String
enum PaywallDefaultType {
    case organic
    case web2app
    case fb_google_redirect
    
    var defaultPaywallName: PaywallName {
        return "default"
    }
}
