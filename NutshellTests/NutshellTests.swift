/*
* Copyright (c) 2015, Tidepool Project
*
* This program is free software; you can redistribute it and/or modify it under
* the terms of the associated License, which is identical to the BSD 2-Clause
* License as published by the Open Source Initiative at opensource.org.
*
* This program is distributed in the hope that it will be useful, but WITHOUT
* ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
* FOR A PARTICULAR PURPOSE. See the License for more details.
*
* You should have received a copy of the License along with this program; if
* not, you can obtain one from Tidepool Project at tidepool.org.
*/

import XCTest
@testable import Nutshell
import Alamofire
import SwiftyJSON

class NutshellTests: XCTestCase {

    // Initial API connection and note used throughout testing
    var userid: String = ""
    var email: String = "testaccount+duffliteA@tidepool.org"
    var pass: String = "testaccount+duffliteA"
    var server: String = "Production"

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
        // Initialize database by referencing username. This must be done before using the APIConnector!
        let _ = NutDataController.controller().currentUserName
        APIConnector.connector().configure()
        APIConnector.connector().switchToServer(server)
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func login(username: String, password: String, remember: Bool, completion: (Result<User, NSError>) -> (Void)) {
        APIConnector.connector().login(email,
            password: pass) { (result:(Alamofire.Result<User, NSError>)) -> (Void) in
                print("Login result: \(result)")
                completion(result)
        }
    }
    
    func test01LoginOut() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        let expectation = expectationWithDescription("Login successful")
        if email == "test username goes here!" {
            XCTFail("Fatal error: please edit NutshellTests.swift and add a test account!")
        }
        self.login(email, password: pass, remember: false) { (result:(Alamofire.Result<User, NSError>)) -> (Void) in
                print("Login result: \(result)")
                if ( result.isSuccess ) {
                    if let user=result.value {
                        NSLog("login success: \(user)")
                        expectation.fulfill()
                        //appDelegate.setupUIForLoginSuccess()
                    } else {
                        // This should not happen- we should not succeed without a user!
                        XCTFail("Fatal error: No user returned!")
                    }
                } else {
                    var errorCode = ""
                    if let error = result.error {
                        errorCode = String(error.code)
                    }
                    XCTFail("login failed! Error: " + errorCode + result.error.debugDescription)
                }
        }
        // Wait 5.0 seconds until expectation has been fulfilled. If not, fail.
        waitForExpectationsWithTimeout(5.0, handler: nil)

    }

    func test02FetchUserProfile() {
        let expectation = expectationWithDescription("User profile fetch successful")
        
        self.login(email, password: pass, remember: false) { (result:(Alamofire.Result<User, NSError>)) -> (Void) in
            print("Login for profile result: \(result)")

             APIConnector.connector().fetchProfile() { (result:Alamofire.Result<JSON, NSError>) -> (Void) in
                NSLog("Profile fetch result: \(result)")
                if (result.isSuccess) {
                    if let json = result.value {
                        NutDataController.controller().processProfileFetch(json)
                    }
                    expectation.fulfill()
                } else {
                    var errorCode = ""
                    if let error = result.error {
                        errorCode = String(error.code)
                    }
                    XCTFail("profile fetch failed! Error: " + errorCode + result.error.debugDescription)
                }
            }
        }
        
        // Wait 5.0 seconds until expectation has been fulfilled. If not, fail.
        waitForExpectationsWithTimeout(5.0, handler: nil)
    }

    func test03FetchUserData() {
        let expectation = expectationWithDescription("User profile fetch successful")
        
        self.login(email, password: pass, remember: false) { (result:(Alamofire.Result<User, NSError>)) -> (Void) in
            print("Login for fetch user data result: \(result)")
            
            // Look at events in July 2015...
            let startDate = NutUtils.dateFromJSON("2015-07-01T00:00:00.000Z")!
            let endDate = NutUtils.dateFromJSON("2015-07-31T23:59:59.000Z")!
            
            APIConnector.connector().getReadOnlyUserData(startDate, endDate: endDate) { (result:Alamofire.Result<JSON, NSError>) -> (Void) in
                NSLog("FetchUserData result: \(result)")
                if (result.isSuccess) {
                    if let json = result.value {
                        if result.isSuccess {
                            DatabaseUtils.updateEvents(NutDataController.controller().mocForTidepoolEvents()!, eventsJSON: json)
                        } else {
                            NSLog("No user data events!")
                        }
                    }
                    expectation.fulfill()
                } else {
                    var errorCode = ""
                    if let error = result.error {
                        errorCode = String(error.code)
                    }
                    XCTFail("user data fetch failed! Error: " + errorCode + result.error.debugDescription)
                }
            }
        }
        // Wait 5.0 seconds until expectation has been fulfilled. If not, fail.
        waitForExpectationsWithTimeout(5.0, handler: nil)
    }
    
    func test04FetchUserData2() {
        let expectation = expectationWithDescription("User profile fetch successful")
        
        self.login(email, password: pass, remember: false) { (result:(Alamofire.Result<User, NSError>)) -> (Void) in
            print("Login for fetch user data result: \(result)")
            
            // Look at events in July 2015...
            let startDate = NutUtils.dateFromJSON("2015-07-01T00:00:00.000Z")!
            let endDate = NutUtils.dateFromJSON("2015-07-31T23:59:59.000Z")!
            
            APIConnector.connector().getReadOnlyUserData(startDate, endDate: endDate) { (result:Alamofire.Result<JSON, NSError>) -> (Void) in
                NSLog("FetchUserData2 result: \(result)")
                if (result.isSuccess) {
                    if let json = result.value {
                        if result.isSuccess {
                            DatabaseUtils.updateEventsForTimeRange(startDate, endTime: endDate, moc:NutDataController.controller().mocForTidepoolEvents()!, eventsJSON: json)
                        } else {
                            NSLog("No user data events!")
                        }
                    }
                    expectation.fulfill()
                } else {
                    var errorCode = ""
                    if let error = result.error {
                        errorCode = String(error.code)
                    }
                    XCTFail("user data fetch failed! Error: " + errorCode + result.error.debugDescription)
                }
            }
        }
        // Wait 5.0 seconds until expectation has been fulfilled. If not, fail.
        waitForExpectationsWithTimeout(5.0, handler: nil)
    }

    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measureBlock {
            // Put the code you want to measure the time of here.
        }
    }
    
}
