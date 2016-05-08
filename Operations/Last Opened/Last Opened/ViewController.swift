//
//  ViewController.swift
//  Last Opened
//
//  Created by Daniel Thorpe on 11/01/2016.
//  Copyright © 2016 Daniel Thorpe. All rights reserved.
//

import UIKit
import CloudKit
import Operations

class ViewController: UIViewController {

    let queue = OperationQueue()
    let container = CKContainer.defaultContainer()

    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)

        let zones = fetchZones()
        let records = fetchRecords()
        records.addDependency(zones)
        queue.addOperations(zones, records)
    }

    func fetchZones() -> Operation {

        // Fetch (all) Record Zones CloudKit Operation
        let operation = CloudKitOperation { CKFetchRecordZonesOperation.fetchAllRecordZonesOperation() }

        operation.addCondition(AuthorizedFor(Capability.Cloud(permissions: [.UserDiscoverability], containerId: container.containerIdentifier)))

        // Configure the container & database
        operation.container = container
        operation.database = container.privateCloudDatabase

        operation.setFetchRecordZonesCompletionBlock { zonesByID in
            if let zonesByID = zonesByID {
                for (zoneID, zone) in zonesByID {
                    print("ID: \(zoneID), Zone: \(zone)")
                }
            }
        }

        return operation
    }

    func fetchRecords() -> Operation {

        // Discover all contacts operation
        let operation = CloudKitOperation { CKFetchRecordsOperation.fetchCurrentUserRecordOperation() }

        operation.addCondition(AuthorizedFor(Capability.Cloud()))

        // Configure the container & database
        operation.container = container
        operation.database = container.privateCloudDatabase

        operation.setFetchRecordsCompletionBlock { recordsByID in
            print("Records by id: \(recordsByID)")
        }

        return operation
    }

    func modifySubscriptions(toSave: [CKSubscription]? = .None, toDelete: [String]? = .None) -> Operation {

        let operation = CloudKitOperation { CKModifySubscriptionsOperation() }

        operation.addCondition(AuthorizedFor(Capability.Cloud()))

        // Configure the container & database
        operation.container = container
        operation.database = container.privateCloudDatabase

        operation.subscriptionsToSave = toSave
        operation.subscriptionIDsToDelete = toDelete

        operation.setErrorHandlerForCode(.LimitExceeded) { [unowned operation] error, log, suggested in

            log.warning("Received CloudKit Limit Exceeded error: \(error)")

            // Create a new operation to bisect the remaining data
            let lhs = CloudKitOperation { CKModifySubscriptionsOperation() }

            // Setup basic configuration such as container & database
            lhs.addConfigureBlock(suggested.configure)

            // Define variables for right hand side
            var rhsSubscriptionsToSave: [CKSubscription]? = .None

            if let subscriptionsToSave = operation.subscriptionsToSave?.filter({ !(error.saved ?? []).contains($0) }) {
                let numberOfSubscriptionsToSave = subscriptionsToSave.count
                lhs.subscriptionsToSave = Array(subscriptionsToSave.prefixUpTo(numberOfSubscriptionsToSave/2))
                rhsSubscriptionsToSave = Array(subscriptionsToSave.suffixFrom(numberOfSubscriptionsToSave/2))
            }

            var rhsSubscriptionIDsToDelete: [String]? = .None

            if let subscriptionsToDelete = operation.subscriptionIDsToDelete?.filter({ !(error.deleted ?? []).contains($0) }) {
                let numberOfSubscriptionsToDelete = subscriptionsToDelete.count
                lhs.subscriptionIDsToDelete = Array(subscriptionsToDelete.prefixUpTo(numberOfSubscriptionsToDelete/2))
                rhsSubscriptionIDsToDelete = Array(subscriptionsToDelete.suffixFrom(numberOfSubscriptionsToDelete/2))
            }

            let configure = { (rhs: OPRCKOperation<CKModifySubscriptionsOperation>) in

                // Apple the suggest configuration to rhs, will include container, database etc
                suggested.configure(rhs)

                // Set the properies for the subscriptions to save/delete
                rhs.subscriptionsToSave = rhsSubscriptionsToSave
                rhs.subscriptionIDsToDelete = rhsSubscriptionIDsToDelete

                // Add the left half as a child of the original operation
                // which will be retried
                rhs.addDependency(lhs)
            }

            // Add the lhs operation as a child of the original operation
            operation.addOperation(lhs)

            return (suggested.delay, configure)
        }

        return operation
    }


}






