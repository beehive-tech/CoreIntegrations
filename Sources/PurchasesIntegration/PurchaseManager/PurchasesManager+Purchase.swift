//
//  File.swift
//  
//
//  Created by Anatolii Kanarskyi on 13/2/24.
//

import Foundation
import StoreKit

extension PurchasesManager {
    public func purchase(_ product: Product) async throws -> SKPurchaseResult {
        debugPrint("🏦 purchase ⚈ ⚈ ⚈ Purchasing product \(product.displayName)... ⚈ ⚈ ⚈")

        var options:Set<Product.PurchaseOption> = []
        if let userId = UUID(uuidString: self.userId) {
            options = [.appAccountToken(userId)]
        }
        let result = try await product.purchase(options: options)

        switch result {
        case .success(let verification):
            debugPrint("🏦 purchase ✅ Product Purchased.")
            debugPrint("🏦 purchase ⚈ ⚈ ⚈ Verifying... ⚈ ⚈ ⚈")
            let transaction = try checkVerified(verification)
            debugPrint("🏦 purchase ✅ Verified.")
            debugPrint("🏦 purchase ⚈ ⚈ ⚈ Updating Product status... ⚈ ⚈ ⚈")
            await updateProductStatus()
            debugPrint("🏦 purchase ✅ Updated product status.")
            await transaction.finish()
            debugPrint("🏦 purchase ✅ Finished transaction.")
            
            let purchaseInfo = SKPurchaseInfo(transaction: transaction, jsonRepresentation: transaction.jsonRepresentation, jwsRepresentation: verification.jwsRepresentation, originalID: "\(transaction.originalID)")
            return .success(transaction: purchaseInfo)
        case .pending:
            debugPrint("🏦 purchase ❌ Failed as the transaction is pending.")
            return .pending
        case .userCancelled:
            debugPrint("🏦 purchase ❌ Failed as the user cancelled the purchase.")
            return .userCancelled
        default:
            debugPrint("🏦 purchase ❌ Failed with result \(result).")
            return .unknown
        }
    }
    
    public func purchase(_ product: Product, promoOffer:PromoOffer) async throws -> SKPurchaseResult {
        debugPrint("🏦 purchase ⚈ ⚈ ⚈ Purchasing product \(product.displayName)... ⚈ ⚈ ⚈")

        var options:Set<Product.PurchaseOption> = []
        if let userId = UUID(uuidString: self.userId) {
            options = [.appAccountToken(userId), .promotionalOffer(offerID: promoOffer.offerID, keyID: promoOffer.keyID, nonce: promoOffer.nonce, signature: promoOffer.signature, timestamp: promoOffer.timestamp)]
        }else{
            options = [.promotionalOffer(offerID: promoOffer.offerID, keyID: promoOffer.keyID, nonce: promoOffer.nonce, signature: promoOffer.signature, timestamp: promoOffer.timestamp)]
        }
        
        let result = try await product.purchase(options: options)

        switch result {
        case .success(let verification):
            debugPrint("🏦 purchase ✅ Product Purchased.")
            debugPrint("🏦 purchase ⚈ ⚈ ⚈ Verifying... ⚈ ⚈ ⚈")
            let transaction = try checkVerified(verification)
            debugPrint("🏦 purchase ✅ Verified.")
            debugPrint("🏦 purchase ⚈ ⚈ ⚈ Updating Product status... ⚈ ⚈ ⚈")
            await updateProductStatus()
            debugPrint("🏦 purchase ✅ Updated product status.")
            await transaction.finish()
            debugPrint("🏦 purchase ✅ Finished transaction.")
            
            let purchaseInfo = SKPurchaseInfo(transaction: transaction, jsonRepresentation: transaction.jsonRepresentation, jwsRepresentation: verification.jwsRepresentation, originalID: "\(transaction.originalID)")
            return .success(transaction: purchaseInfo)
        case .pending:
            debugPrint("🏦 purchase ❌ Failed as the transaction is pending.")
            return .pending
        case .userCancelled:
            debugPrint("🏦 purchase ❌ Failed as the user cancelled the purchase.")
            return .userCancelled
        default:
            debugPrint("🏦 purchase ❌ Failed with result \(result).")
            return .unknown
        }
    }
    
    //This call displays a system prompt that asks users to authenticate with their App Store credentials.
    //Call this function only in response to an explicit user action, such as tapping a button.
    public func restore() async -> SKRestoreResult {
        do {
            try await AppStore.sync()
        }
        catch {
            return .error(error.localizedDescription)
        }
        return .success(consumables: self.purchasedConsumables,
                        nonConsumables: self.purchasedNonConsumables,
                        subscriptions: self.purchasedSubscriptions,
                        nonRenewables: self.purchasedNonRenewables)
    }
    
    public func verifyPremium() async -> PurchasesVerifyPremiumResult {
        var statuses:[VerifyPremiumStatus] = []
        
        if subscriptions.isEmpty {
            await updateProductStatus()
        }
        
        await subscriptions.asyncForEach { product in
            if proIdentifiers.contains(where: {$0 == product.id}) {
                if let state = await getSubscriptionStatus(product: product) {
                    let premiumStatus = VerifyPremiumStatus(product: product, state: state)
                    statuses.append(premiumStatus)
                }
            }
        }
        
        nonConsumables.forEach { product in
            if proIdentifiers.contains(where: {$0 == product.id}) {
                let premiumStatus = VerifyPremiumStatus(product: product, state: .subscribed)
                statuses.append(premiumStatus)
            }
        }
        
        if let premium = statuses.first(where: {$0.state == .subscribed}) {
            return .premium(purchase: Purchase(product: premium.product))
        }else{
            return .notPremium
        }
    }
    
    public func verifyAll() async -> PurchasesVerifyResult {
        await updateProductStatus()
        
        return .success(consumables: self.purchasedConsumables,
                        nonConsumables: self.purchasedNonConsumables,
                        subscriptions: self.purchasedSubscriptions,
                        nonRenewables: self.purchasedNonRenewables)
    }
}
