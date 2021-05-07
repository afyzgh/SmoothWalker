//
//  WalkingSpeedTableViewController.swift
//  SmoothWalker
//
//  Created by William on 5/7/21.
//  Copyright © 2021 Apple. All rights reserved.
//

import UIKit
import HealthKit

// Statistics timeline
enum WalkingSpeedTimeline {
    case daily
    case weekly
    case monthly
}

class WalkingSpeedTableViewController: UITableViewController {
    
    static let cellIdentifier = "DataTypeTableViewCell"
    let calendar: Calendar = .current
    let healthStore = HealthData.healthStore
    let dateFormatter = DateFormatter()
    
    var dataTypeIdentifier: String
    var query: HKStatisticsCollectionQuery?
    var quantityTypeIdentifier: HKQuantityTypeIdentifier {
        return HKQuantityTypeIdentifier(rawValue: dataTypeIdentifier)
    }
    var quantityType: HKQuantityType {
        return HKQuantityType.quantityType(forIdentifier: quantityTypeIdentifier)!
    }
    var dataValueList: [[HealthDataTypeValue]] = [[HealthDataTypeValue]](repeating: [HealthDataTypeValue](), count: 3)
    
    // MARK: Initializers
    
    init(dataTypeIdentifier: String) {
        self.dataTypeIdentifier = dataTypeIdentifier
        super.init(style: .insetGrouped)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: View Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setUpNavigationController()
        setUpViewController()
        setUpTableView()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateNavigationItem()
        if query != nil { return }
        
        // Request authorization.
        let dataTypeValues = Set([quantityType])
        
        print("Requesting HealthKit authorization...")
        
        self.healthStore.requestAuthorization(toShare: dataTypeValues, read: dataTypeValues) { (success, error) in
            if success {
                self.calculateDailyQuantitySamplesForPastWeek()
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if let query = query {
            self.healthStore.stop(query)
        }
    }
    
    func setUpNavigationController() {
        navigationController?.navigationBar.prefersLargeTitles = true
    }
    
    func setUpViewController() {
        title = tabBarItem.title
        dateFormatter.dateStyle = .medium
    }
    
    func setUpTableView() {
        tableView.register(DataTypeTableViewCell.self, forCellReuseIdentifier: Self.cellIdentifier)
    }
    
    private var emptyDataView: EmptyDataBackgroundView {
        return EmptyDataBackgroundView(message: "No Data")
    }
    
    // MARK: - Data Life Cycle
    
    func reloadData() {
        self.dataValueList.isEmpty ? self.setEmptyDataView() : self.removeEmptyDataView()
        for i in 0 ..< dataValueList.count {
            dataValueList[i].sort { $0.startDate > $1.startDate }
        }
        self.tableView.reloadData()
        self.tableView.refreshControl?.endRefreshing()
    }
    
    func updateNavigationItem() {
        navigationItem.title = getDataTypeName(for: dataTypeIdentifier)
    }
    
    func calculateDailyQuantitySamplesForPastWeek() {
        performQuery {
            DispatchQueue.main.async { [weak self] in
                self?.reloadData()
            }
        }
        performQuery(timeline: .weekly) {
            DispatchQueue.main.async { [weak self] in
                self?.reloadData()
            }
        }
        performQuery(timeline: .monthly) {
            DispatchQueue.main.async { [weak self] in
                self?.reloadData()
            }
        }
    }
    
    private func setEmptyDataView() {
        tableView.backgroundView = emptyDataView
    }
    
    private func removeEmptyDataView() {
        tableView.backgroundView = nil
    }
}


// MARK: - Query Working Speed Data Source
extension WalkingSpeedTableViewController {
    
    func performQuery(timeline: WalkingSpeedTimeline = .daily, completion: @escaping () -> Void) {
        
        let statisticsOptions = getStatisticsOptions(for: dataTypeIdentifier)
        var predicate = createLastWeekPredicate()
        var anchorDate = createAnchorDate()
        var dailyInterval = DateComponents(day: 1)
        var startDate = getLastWeekStartDate()
        var dataListIndex = 0
        
        switch timeline {
        case .weekly:
            predicate = createFourWeekPredicate()
            anchorDate = createAnchorDateToday()
            dailyInterval = DateComponents(day: 7)
            startDate = getFourWeekStartDate()
            dataListIndex = 1
        case .monthly:
            predicate = createLastWeekPredicate()
            anchorDate = createAnchorDateToday()
            dailyInterval = DateComponents(day: 30)
            startDate = getThreeMonthStartDate()
            dataListIndex = 2
        default:
            predicate = createLastWeekPredicate()
            anchorDate = createAnchorDate()
            dailyInterval = DateComponents(day: 1)
            startDate = getLastWeekStartDate()
            dataListIndex = 0
        }
        
        let query = HKStatisticsCollectionQuery(quantityType: quantityType,
                                                quantitySamplePredicate: predicate,
                                                options: statisticsOptions,
                                                anchorDate: anchorDate,
                                                intervalComponents: dailyInterval)
        
        // The handler block for the HKStatisticsCollection object.
        let updateInterfaceWithStatistics: (HKStatisticsCollection) -> Void = { statisticsCollection in
            var dataValues = [HealthDataTypeValue]()
            
            let endDate = Date()
            
            statisticsCollection.enumerateStatistics(from: startDate, to: endDate) { [weak self] (statistics, stop) in
                var dataValue = HealthDataTypeValue(startDate: statistics.startDate,
                                                    endDate: statistics.endDate,
                                                    value: 0)
                if let quantity = getStatisticsQuantity(for: statistics, with: statisticsOptions),
                   let identifier = self?.dataTypeIdentifier,
                   let unit = preferredUnit(for: identifier) {
                    dataValue.value = quantity.doubleValue(for: unit)
                    print(dataValue.value)
                }
                
                dataValues.append(dataValue)
                self?.dataValueList[dataListIndex] = dataValues
            }
            
            completion()
        }
        
        query.initialResultsHandler = { query, statisticsCollection, error in
            if let statisticsCollection = statisticsCollection {
                updateInterfaceWithStatistics(statisticsCollection)
            }
        }
        
        query.statisticsUpdateHandler = { [weak self] query, statistics, statisticsCollection, error in
            // Ensure we only update the interface if the visible data type is updated
            if let statisticsCollection = statisticsCollection, query.objectType?.identifier == self?.dataTypeIdentifier {
                updateInterfaceWithStatistics(statisticsCollection)
            }
        }
        
        self.healthStore.execute(query)
        self.query = query
    }
    
    
    func performQueryWeekly(completion: @escaping () -> Void) {
        let predicate = createFourWeekPredicate()
        let anchorDate = createAnchorDateToday()
        let dailyInterval = DateComponents(day: 7)
        let statisticsOptions = getStatisticsOptions(for: dataTypeIdentifier)
        
        let query = HKStatisticsCollectionQuery(quantityType: quantityType,
                                                quantitySamplePredicate: predicate,
                                                options: statisticsOptions,
                                                anchorDate: anchorDate,
                                                intervalComponents: dailyInterval)
        
        // The handler block for the HKStatisticsCollection object.
        let updateInterfaceWithStatistics: (HKStatisticsCollection) -> Void = { statisticsCollection in
            var dataValues = [HealthDataTypeValue]()
            
            let now = Date()
            let startDate = getFourWeekStartDate()
            let endDate = now
            
            statisticsCollection.enumerateStatistics(from: startDate, to: endDate) { [weak self] (statistics, stop) in
                print(statistics.startDate)
                print(statistics.endDate)
                var dataValue = HealthDataTypeValue(startDate: statistics.startDate,
                                                    endDate: statistics.endDate,
                                                    value: 0)
                if let quantity = getStatisticsQuantity(for: statistics, with: statisticsOptions),
                   let identifier = self?.dataTypeIdentifier,
                   let unit = preferredUnit(for: identifier) {
                    dataValue.value = quantity.doubleValue(for: unit)
                    print(dataValue.value)
                }
                
                dataValues.append(dataValue)
                self?.dataValueList[1] = dataValues
            }
            
            completion()
        }
        
        query.initialResultsHandler = { query, statisticsCollection, error in
            if let statisticsCollection = statisticsCollection {
                updateInterfaceWithStatistics(statisticsCollection)
            }
        }
        
        query.statisticsUpdateHandler = { [weak self] query, statistics, statisticsCollection, error in
            // Ensure we only update the interface if the visible data type is updated
            if let statisticsCollection = statisticsCollection, query.objectType?.identifier == self?.dataTypeIdentifier {
                updateInterfaceWithStatistics(statisticsCollection)
            }
        }
        
        self.healthStore.execute(query)
        self.query = query
    }
    
    
    
    func performQueryMonthly(completion: @escaping () -> Void) {
        let predicate = createThreeMonthPredicate()
        let anchorDate = createAnchorDateToday()
        let dailyInterval = DateComponents(day: 30)
        let statisticsOptions = getStatisticsOptions(for: dataTypeIdentifier)
        
        let query = HKStatisticsCollectionQuery(quantityType: quantityType,
                                                quantitySamplePredicate: predicate,
                                                options: statisticsOptions,
                                                anchorDate: anchorDate,
                                                intervalComponents: dailyInterval)
        
        // The handler block for the HKStatisticsCollection object.
        let updateInterfaceWithStatistics: (HKStatisticsCollection) -> Void = { statisticsCollection in
            var dataValues = [HealthDataTypeValue]()
            
            let now = Date()
            let startDate = getThreeMonthStartDate()
            let endDate = now
            
            statisticsCollection.enumerateStatistics(from: startDate, to: endDate) { [weak self] (statistics, stop) in
                print(statistics.startDate)
                print(statistics.endDate)
                var dataValue = HealthDataTypeValue(startDate: statistics.startDate,
                                                    endDate: statistics.endDate,
                                                    value: 0)
                if let quantity = getStatisticsQuantity(for: statistics, with: statisticsOptions),
                   let identifier = self?.dataTypeIdentifier,
                   let unit = preferredUnit(for: identifier) {
                    dataValue.value = quantity.doubleValue(for: unit)
                    print(dataValue.value)
                }
                
                dataValues.append(dataValue)
                self?.dataValueList[2] = dataValues
            }
            
            completion()
        }
        
        query.initialResultsHandler = { query, statisticsCollection, error in
            if let statisticsCollection = statisticsCollection {
                updateInterfaceWithStatistics(statisticsCollection)
            }
        }
        
        query.statisticsUpdateHandler = { [weak self] query, statistics, statisticsCollection, error in
            // Ensure we only update the interface if the visible data type is updated
            if let statisticsCollection = statisticsCollection, query.objectType?.identifier == self?.dataTypeIdentifier {
                updateInterfaceWithStatistics(statisticsCollection)
            }
        }
        
        self.healthStore.execute(query)
        self.query = query
    }
}

// MARK: - UITableViewDataSource
extension WalkingSpeedTableViewController {
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return dataValueList[section].count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellIdentifier) as? DataTypeTableViewCell else {
            return DataTypeTableViewCell()
        }
        let dataValues = dataValueList[indexPath.section]
        let dataValue = dataValues[indexPath.row]
        
        print("cellForRowAt \(dataValue.value)")
        cell.textLabel?.text = formattedValue(dataValue.value, typeIdentifier: dataTypeIdentifier)
        if indexPath.section == 0 {
            
            cell.detailTextLabel?.text = dateFormatter.string(from: dataValue.startDate)
        } else {
            cell.detailTextLabel?.text = String("\(dateFormatter.string(from: dataValue.startDate)) - \(dateFormatter.string(from: dataValue.endDate))")
        }
        
        return cell
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 3
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        var titleForHeader = "Daily"
        if section == 1 {
            titleForHeader = "Weekly"
        }
        if section == 2 {
            titleForHeader = "Monthly"
        }
        return titleForHeader
    }
}

// MARK: - UITableViewDelegate
extension WalkingSpeedTableViewController {
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}
