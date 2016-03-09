//
//  Domain.swift
//  Searching
//
//  Created by Daniel Thorpe on 09/03/2016.
//  Copyright © 2016 Daniel Thorpe. All rights reserved.
//

import Foundation
import YapDatabase
import ValueCoding
import YapDatabaseExtensions
import TaylorSource

// MARK: - Domain

struct State {
    let name: String
}

struct City {
    let name: String
    let population: Int
    let capital: Bool
    let stateId: Identifier
}

class CitySearch: YapDB.Search {

    static let name = "Search for Cities by Name"

    static let handler: YapDB.SearchResults.Handler = {
        return .ByObject({ dictionary, collection, key, object in
            if collection == City.collection, let city = City.decode(object) {
                dictionary.setObject(city.name, forKey: "name")
            }
        })
    }()

    init(db: YapDatabase) {
        // Note the * - this is very important
        super.init(db: db, views: [City.searchResults], query: { "name:\($0)*" })
    }
}

extension City {

    static let view: YapDB.Fetch = {

        let grouping: YapDB.View.Grouping = .ByObject({ (_, collection, key, object) -> String! in
            if collection == City.collection, let city = City.decode(object) {
                return collection
            }
            return nil
        })

        let sorting: YapDB.View.Sorting = .ByObject({ (_, group, collection1, key1, object1, collection2, key2, object2) -> NSComparisonResult in
            if let city1 = City.decode(object1), city2 = City.decode(object2) {
                return city1.compare(city2)
            }
            return .OrderedSame
        })

        return .View(YapDB.View(name: "Cities", grouping: grouping, sorting: sorting, collections: [collection]))
    }()

    static let viewByState: YapDB.Fetch = {

        let grouping: YapDB.View.Grouping = .ByObject({ (_, collection, key, object) -> String! in
            if collection == City.collection, let city = City.decode(object) {
                return city.stateId
            }
            return nil
        })

        let sorting: YapDB.View.Sorting = .ByObject({ (_, group, collection1, key1, object1, collection2, key2, object2) -> NSComparisonResult in
            if let city1 = City.decode(object1), city2 = City.decode(object2) {
                return city1.compare(city2)
            }
            return .OrderedSame
        })

        return .View(YapDB.View(name: "Cities by State ID", grouping: grouping, sorting: sorting, collections: [collection]))
    }()

    static let searchResults: YapDB.Fetch = {
        return .Search(YapDB.SearchResults(name: "Cities by Name Search Results", parent: viewByState, search: CitySearch.name, columnNames: ["name"], handler: CitySearch.handler, collections: [collection]))
    }()

    static func viewCities(byState: Bool = true, abovePopulationThreshold threshold: Int = 0) -> YapDB.Fetch {
        let parent = byState ? viewByState : view
        if threshold > 0 {

            let filtering = YapDB.Filter.Filtering.ByObject({ (_, group, collection, key, object) -> Bool in
                if collection == City.collection, let city = City.decode(object) {
                    return city.population >= threshold
                }
                return false
            })

            let name = "\(parent.name), above population threshold: \(threshold)"
            return .Filter(YapDB.Filter(name: name, parent: parent, filtering: filtering, collections: [collection]))
        }
        return parent
    }

    static func cities(byState: Bool = true, abovePopulationThreshold threshold: Int = 0, mappingBlock: YapDB.FetchConfiguration.MappingsConfigurationBlock? = .None) -> TaylorSource.Configuration<City> {
        let config = YapDB.FetchConfiguration(fetch: viewCities(byState, abovePopulationThreshold: threshold), block: mappingBlock)
        return TaylorSource.Configuration(fetch: config, itemMapper: City.decode)
    }

    static func searchResults(mappingBlock: YapDB.FetchConfiguration.MappingsConfigurationBlock? = .None) -> TaylorSource.Configuration<City> {
        let config = YapDB.FetchConfiguration(fetch: searchResults, block: mappingBlock)
        return TaylorSource.Configuration(fetch: config, itemMapper: City.decode)
    }
}

// MARK: - Persistable

extension State: Persistable {

    static let collection: String = "States"

    var identifier: Identifier {
        return name
    }
}


extension City: Persistable {

    static let collection: String = "Cities"

    var identifier: Identifier {
        return name
    }
}

// MARK: - Equatable

extension State: Equatable { }

func == (lhs: State, rhs: State) -> Bool {
    return lhs.name == rhs.name
}

extension City: Equatable { }

func == (lhs: City, rhs: City) -> Bool {
    return (lhs.name == rhs.name) && (lhs.population == rhs.population) && (lhs.capital == rhs.capital) && (lhs.stateId == rhs.stateId)
}

// MARK: - Comparable

extension City: Comparable {

    func compare(other: City) -> NSComparisonResult {
        if self == other {
            return .OrderedSame
        }
        else if self < other {
            return .OrderedAscending
        }
        return .OrderedDescending
    }
}

func < (lhs: City, rhs: City) -> Bool {
    switch (lhs.capital, rhs.capital) {
    case (true, false):
        return true
    case (false, true):
        return false
    default:
        if lhs.population == rhs.population {
            return lhs.name < rhs.name
        }
        return lhs.population < rhs.population
    }
}


// MARK: - ValueCoding

extension State: ValueCoding {
    typealias Coder = StateCoder
}

extension City: ValueCoding {
    typealias Coder = CityCoder
}

// MARK: - Coders

class StateCoder: NSObject, NSCoding, CodingType {

    let value: State

    required init(_ v: State) {
        value = v
    }

    required init(coder aDecoder: NSCoder) {
        let name = aDecoder.decodeObjectForKey("name") as? String
        value = State(name: name!)
    }

    func encodeWithCoder(aCoder: NSCoder) {
        aCoder.encodeObject(value.name, forKey: "name")
    }
}

class CityCoder: NSObject, NSCoding, CodingType {

    let value: City

    required init(_ v: City) {
        value = v
    }

    required init(coder aDecoder: NSCoder) {
        let name = aDecoder.decodeObjectForKey("name") as? String
        let population = aDecoder.decodeIntegerForKey("population")
        let capital = aDecoder.decodeBoolForKey("capital")
        let stateId = aDecoder.decodeObjectForKey("stateId") as? String
        value = City(name: name!, population: population, capital: capital, stateId: stateId!)
    }

    func encodeWithCoder(aCoder: NSCoder) {
        aCoder.encodeObject(value.name, forKey: "name")
        aCoder.encodeInteger(value.population, forKey: "population")
        aCoder.encodeBool(value.capital, forKey: "capital")
        aCoder.encodeObject(value.stateId, forKey: "stateId")
    }
}

