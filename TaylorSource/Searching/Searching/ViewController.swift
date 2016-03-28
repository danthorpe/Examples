//
//  ViewController.swift
//  Searching
//
//  Created by Daniel Thorpe on 09/03/2016.
//  Copyright © 2016 Daniel Thorpe. All rights reserved.
//

import UIKit
import Operations
import YapDatabase
import YapDatabaseExtensions
import TaylorSource

class CityCell: UITableViewCell {

    override required init(style: UITableViewCellStyle, reuseIdentifier: String?) {
        super.init(style: UITableViewCellStyle.Value1, reuseIdentifier: reuseIdentifier)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    class func configuration(formatter: NSNumberFormatter) -> CitiesDatasource.Datasource.FactoryType.CellConfiguration {
        return { cell, city, index in
            cell.textLabel!.font = UIFont.preferredFontForTextStyle(city.capital ? UIFontTextStyleHeadline : UIFontTextStyleBody)
            cell.textLabel!.text = city.name
            cell.detailTextLabel!.font = UIFont.preferredFontForTextStyle(UIFontTextStyleBody)
            cell.detailTextLabel!.text = formatter.stringFromNumber(NSNumber(integer: city.population))
        }
    }
}

struct CitiesDatasource: DatasourceProviderType {
    
    typealias Factory = YapDBFactory<City, CityCell, UITableViewHeaderFooterView, UITableView>
    typealias Datasource = YapDBDatasource<Factory>

    enum Kind {
        case All, SearchResults

        func configurationWithThreshold(threshold: Int) -> TaylorSource.Configuration<City> {
            switch self {
            case .All:
                return City.cities(abovePopulationThreshold: threshold)
            case .SearchResults:
                return City.searchResults()
            }
        }
    }

    let kind: Kind
    let readWriteConnection: YapDatabaseConnection
    let formatter: NSNumberFormatter
    let editor = NoEditor()
    var datasource: Datasource

    init(db: YapDatabase, view: Factory.ViewType, kind k: Kind = .All, threshold: Int = 0) {
        kind = k
        formatter = NSNumberFormatter()
        formatter.numberStyle = .DecimalStyle
        formatter.perMillSymbol = ","
        formatter.allowsFloats = false
        readWriteConnection = db.newConnection()

        datasource = Datasource(id: "cities datasource", database: db, factory: Factory(), processChanges: view.processChanges, configuration: kind.configurationWithThreshold(threshold))
        datasource.factory.registerCell(.ClassWithIdentifier(CityCell.self, "cell"), inView: view, configuration: CityCell.configuration(formatter))
        datasource.factory.registerHeaderText { index in
            if let state: State = index.transaction.readByKey(index.group) {
                return state.name
            }
            return .None
        }
    }
}

class USCitiesViewController: UITableViewController {

    var kind: CitiesDatasource.Kind = .All
    var wrapper: TableViewDataSourceProvider<CitiesDatasource>!

    override func viewDidLoad() {
        super.viewDidLoad()
        configureDataSource()
    }

    func configureDataSource() {
        wrapper = createWrapperWithKind(kind)
        tableView.dataSource = wrapper.tableViewDataSource
        tableView.reloadData()
    }

    func createWrapperWithKind(kind: CitiesDatasource.Kind) -> TableViewDataSourceProvider<CitiesDatasource> {
        return TableViewDataSourceProvider(CitiesDatasource(db: database, view: tableView, kind: kind))
    }
}

class SearchableUSCitiesViewController: USCitiesViewController {
    
    let queue = OperationQueue()
    let loadUSCities = LoadUSCitiesOperation(db: database)

    let search = CitySearch(db: database)
    var searchController: UISearchController!
    var searchResultsController: USCitiesViewController!

    override func viewDidLoad() {
        super.viewDidLoad()
        configureSearchController()
    }

    override func configureDataSource() {

        func configureTableView(tableView: UITableView, withDatasource dataSource: UITableViewDataSource) -> Operation {
            return BlockOperation {
                tableView.dataSource = dataSource
                tableView.reloadData()
            }
        }

        wrapper = createWrapperWithKind(kind)

        let reloadTableView = configureTableView(tableView, withDatasource: wrapper.tableViewDataSource)
        reloadTableView.addDependency(loadUSCities)
        queue.addOperations(loadUSCities, reloadTableView)
    }

    func configureSearchController() {
        searchResultsController = USCitiesViewController(style: .Plain)
        searchResultsController.kind = .SearchResults

        searchController = UISearchController(searchResultsController: UINavigationController(rootViewController: searchResultsController))
        searchController.searchResultsUpdater = self
        searchController.searchBar.delegate = self

        var frame = searchController.searchBar.frame
        frame.size.height = 44
        searchController.searchBar.frame = frame
        tableView.tableHeaderView = searchController.searchBar
        definesPresentationContext = true
    }
}

extension SearchableUSCitiesViewController: UISearchResultsUpdating {

    func updateSearchResultsForSearchController(searchController: UISearchController) {
        search.usingTerm(searchController.searchBar.text ?? "")
    }
}

extension SearchableUSCitiesViewController: UISearchBarDelegate {

    func searchBarCancelButtonClicked(searchBar: UISearchBar) {
        tableView.reloadData()
    }
}

class LoadUSCitiesOperation: GroupOperation {

    enum Error: ErrorType {
        case UnableToLoadPlist
    }

    class USCitiesData: Operation {

        let resource = "USStatesAndCities"
        var data: NSDictionary? = .None

        override init() {
            super.init()
            name = "Load Data from Plist"
        }

        override func execute() {
            guard let
                path = NSBundle(forClass: LoadUSCitiesOperation.self).pathForResource(resource, ofType: "plist"),
                data = NSDictionary(contentsOfFile: path)
            else {
                finish(Error.UnableToLoadPlist)
                return
            }
            self.data = data
            finish()
        }

        var stateNames: [String]? {
            return data?.allKeys as? [String]
        }

        func cityDataForState(stateName: String) -> [NSDictionary]? {
            return (data?[stateName] as? NSDictionary).flatMap { $0["StateCities"] as? [NSDictionary] }
        }
    }

    class AddStateAndCitiesToDatabase: Operation {
        let connection: YapDatabaseConnection
        let stateName: String
        let getCityDataForState: String -> [NSDictionary]?

        init(connection: YapDatabaseConnection, stateName: String, getCityData: String -> [NSDictionary]?) {
            self.connection = connection
            self.stateName = stateName
            self.getCityDataForState = getCityData
            super.init()
            name = "Add \(stateName) & Cities to Database"
        }

        override func execute() {
            let state = State(name: stateName)
            let cities = getCityDataForState(stateName)?.flatMap { data -> City? in
                guard let
                    name = data["CityName"] as? String,
                    population = (data["CityPopulation"] as? NSNumber)?.integerValue
                else {
                    return .None
                }

                let isCapital = (data["isCapital"] as? NSNumber)?.boolValue ?? false
                return City(name: name, population: population, capital: isCapital, stateId: state.identifier)
            }

            connection.write {
                $0.write(state)
                if let cities = cities {
                    $0.write(cities)
                }
            }

            finish()
        }
    }

    let database: YapDatabase
    let data: USCitiesData

    init(db: YapDatabase) {
        database = db
        data = USCitiesData()
        super.init(operations: [data])
        name = "Load US Cities"
        // Uncomment this to see what is happening with the data load.
//        log.severity = .Verbose
    }

    func addAnyMissingCities() {
        let block = BlockOperation { [unowned self] (finish: BlockOperation.ContinuationBlockType) in
            let connection = self.database.newConnection()
            let existingStates: [State] = connection.readAll()
            let existingStateNames = existingStates.map { $0.name }
            if let allStateNames = self.data.stateNames {
                let remainingStateNames = allStateNames.filter { !existingStateNames.contains($0) }
                if remainingStateNames.count > 0 {
                    let get = self.data.cityDataForState
                    self.addOperations(remainingStateNames.map { AddStateAndCitiesToDatabase(connection: connection, stateName: $0, getCityData: get) })
                }
            }
            finish(error: nil)
        }
        addOperation(block)
    }

    override func willFinishOperation(operation: NSOperation, withErrors errors: [ErrorType]) {
        if errors.isEmpty && operation == data {
            addAnyMissingCities()
        }
    }
}



