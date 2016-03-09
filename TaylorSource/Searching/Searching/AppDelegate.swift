//
//  AppDelegate.swift
//  Searching
//
//  Created by Daniel Thorpe on 09/03/2016.
//  Copyright © 2016 Daniel Thorpe. All rights reserved.
//

import UIKit
import YapDatabase
import YapDatabaseExtensions

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
}

/**
 - Example or registering some default YapDatabase views
let database = YapDB.databaseNamed("US_Cities") { db in
    let views = [ City.view, City.viewByState, City.searchResults ]
    views.forEach { $0.registerInDatabase(db) }
}
*/

let database = YapDB.databaseNamed("US_Cities")

