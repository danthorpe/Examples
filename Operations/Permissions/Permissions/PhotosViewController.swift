//
//  PhotosViewController.swift
//  Permissions
//
//  Created by Daniel Thorpe on 14/04/2016.
//  Copyright © 2016 Daniel Thorpe. All rights reserved.
//

import Foundation
import Photos
import Operations

class PhotosViewController: PermissionViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("Photos", comment: "Address Book")

        permissionNotDetermined.informationLabel.text = "We haven't yet asked permission to access your Photo Library."
        permissionGranted.instructionLabel.text = "Perform an operation with the Photos Library"
        permissionGranted.button.setTitle("Do something with the library", forState: .Normal)
        operationResults.informationLabel.text = "These are the results of our Photos Operation"
    }

    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        determineAuthorizationStatus()
    }

    override func conditionsForState(state: State, silent: Bool) -> [OperationCondition] {
        return configureConditionsForState(state, silent: silent)(AuthorizedFor(Capability.Photos()))
    }

    func photosEnabled(enabled: Bool, withAuthorization status: PHAuthorizationStatus) {
        switch (enabled, status) {
        case (false, _):
            print("Photos Library are not enabled")

        case (true, .Authorized):
            self.state = .Authorized

        case (true, .Restricted), (true, .Denied):
            self.state = .Denied

        default:
            self.state = .Unknown
        }
    }

    func determineAuthorizationStatus() {
        let status = GetAuthorizationStatus(Capability.Photos(), completion: photosEnabled)
        queue.addOperation(status)
    }

    override func requestPermission() {
        let authorize = Authorize(Capability.Photos(), completion: photosEnabled)
        queue.addOperation(authorize)
    }

    override func performOperation() {

        let block = BlockOperation { (continueWithError: BlockOperation.ContinuationBlockType) in
            print("It's now safe to use the Photos Library.")
        }
        queue.addOperation(block)
    }
}
