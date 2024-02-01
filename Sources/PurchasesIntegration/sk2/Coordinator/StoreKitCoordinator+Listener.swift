import Foundation
import StoreKit

extension StoreKitCoordinator {
    func listenForTransactions() -> Task<Void, Error> {
        debugPrint("\(StoreKitCoordinator.identifier) listenForTransactions \(DebuggingIdentifiers.actionOrEventSucceded) Setup listener")
        return Task.detached {
            debugPrint("\(StoreKitCoordinator.identifier) listenForTransactions \(DebuggingIdentifiers.actionOrEventInProgress) Recieved updates... \(DebuggingIdentifiers.actionOrEventInProgress)")
            // Iterate through any transactions that don't come from a direct call to `purchase()`.
            for await result in Transaction.updates {
                do {
                    debugPrint("\(StoreKitCoordinator.identifier) listenForTransactions \(DebuggingIdentifiers.actionOrEventInProgress) Checking verification for transaction \(result.debugDescription) \(DebuggingIdentifiers.actionOrEventInProgress)")
                    let transaction = try self.checkVerified(result)
                    debugPrint("\(StoreKitCoordinator.identifier) listenForTransactions \(DebuggingIdentifiers.actionOrEventSucceded) Transaction Verified.")
                    // Deliver products to the user.
                    await self.updateCustomerProductStatus()
                    debugPrint("\(StoreKitCoordinator.identifier) listenForTransactions \(DebuggingIdentifiers.actionOrEventSucceded) Updated Customer Product Status.")
                    // Always finish a transaction - This removes transactions from the queue and it tells Apple that the customer has recieved their items or service.
                    await transaction.finish()
                    debugPrint("\(StoreKitCoordinator.identifier) listenForTransactions \(DebuggingIdentifiers.actionOrEventSucceded) Finished Transaction.")
                } catch {
                    // StoreKit has a transaction that fails verification. Don't deliver content to the user.
                    debugPrint("\(StoreKitCoordinator.identifier) listenForTransactions \(DebuggingIdentifiers.actionOrEventFailed) Transaction verification failed.")
                }
            }
        }
    }
}
