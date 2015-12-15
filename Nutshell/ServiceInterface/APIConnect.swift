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

import Foundation
import UIKit
import Alamofire
import SwiftyJSON
import CoreData

/// APIConnector is a singleton object with the main responsibility of communicating to the Tidepool service:
/// - Given a username and password, login.
/// - Can refresh connection.
/// - Fetches Tidepool data.
/// - Provides online/offline statis.
class APIConnector {
    
    static var _connector: APIConnector?
    /// Supports a singleton for the application.
    class func connector() -> APIConnector {
        if _connector == nil {
        _connector = APIConnector()
        }
        return _connector!
    }
    
    // MARK: - Constants
    
    private let kSessionTokenDefaultKey = "SToken"
    private let kCurrentServiceDefaultKey = "SCurrentService"
    private let kSessionIdHeader = "x-tidepool-session-token"

    // Error domain and codes
    private let kNutshellErrorDomain = "NutshellErrorDomain"
    private let kNoSessionTokenErrorCode = -1
    
    // Session token, acquired on login and saved in NSUserDefaults
    // TODO: save in database?
    private var _rememberToken = true
    private var _sessionToken: String?
    var sessionToken: String? {
        set(newToken) {
            if ( newToken != nil  && _rememberToken) {
                NSUserDefaults.standardUserDefaults().setValue(newToken, forKey:kSessionTokenDefaultKey)
            } else {
                NSUserDefaults.standardUserDefaults().removeObjectForKey(kSessionTokenDefaultKey)
            }
            _sessionToken = newToken
        }
        get {
            return _sessionToken
        }
    }
    
    // Dictionary of servers and their base URLs
    let kServers = [
        "Production" :   "https://api.tidepool.org",
        "Staging" :      "https://stg-api.tidepool.org",
        "Development" :  "https://dev-api.tidepool.org",
    ]
    private let kDefaultServerName = "Production"

    private var _currentService: String?
    var currentService: String? {
        set(newService) {
            if newService == nil {
                NSUserDefaults.standardUserDefaults().removeObjectForKey(kCurrentServiceDefaultKey)
                _currentService = nil
            } else {
                if kServers[newService!] != nil {
                    NSUserDefaults.standardUserDefaults().setValue(newService, forKey: kCurrentServiceDefaultKey)
                    _currentService = newService
                }
            }
        }
        get {
            if _currentService == nil {
                if let service = NSUserDefaults.standardUserDefaults().stringForKey(kCurrentServiceDefaultKey) {
                    _currentService = service
                }
            }
            if _currentService == nil || kServers[_currentService!] == nil {
                _currentService = kDefaultServerName
            }
            return _currentService
        }
    }
    
    // Base URL for API calls, set during initialization
    var baseUrl: NSURL?
 
    // Reachability object, valid during lifetime of this APIConnector, and convenience function that uses this
    // Register for ReachabilityChangedNotification to monitor reachability changes             
    var reachability: Reachability?
    func isConnectedToNetwork() -> Bool {
        if let reachability = reachability {
            return reachability.isReachable()
        } else {
            NSLog("Error: reachability object not configured!")
            return true
        }
    }

    func serviceAvailable() -> Bool {
        if !isConnectedToNetwork() || sessionToken == nil {
            return false
        }
        return true
    }

    // MARK: Initialization
    
    /// Creator of APIConnector must call this function after init!
    func configure() -> APIConnector {
        self.baseUrl = NSURL(string: kServers[currentService!]!)!
        NSLog("Using service: \(self.baseUrl)")
        self.sessionToken = NSUserDefaults.standardUserDefaults().stringForKey(kSessionTokenDefaultKey)
        if let reachability = reachability {
            reachability.stopNotifier()
        }
        do {
            let reachability = try Reachability.reachabilityForInternetConnection()
            self.reachability = reachability
        } catch ReachabilityError.FailedToCreateWithAddress(let address) {
            NSLog("Unable to create\nReachability with address:\n\(address)")
        } catch {
                NSLog("Other reachability error!")
        }
        
        do {
           try reachability?.startNotifier()
        } catch {
            NSLog("Error: Unable to start notifier!")
        }
        return self
    }
    
    deinit {
        reachability?.stopNotifier()
    }
    
    func switchToServer(serverName: String) {
        if (currentService != serverName) {
            currentService = serverName
            // refresh connector since there is a new service...
            configure()
            NSLog("Switched to \(serverName) server")
        }
    }
    
    /// Logs in the user and obtains the session token for the session (stored internally)
    func login(username: String, password: String, remember: Bool, completion: (Result<User>) -> (Void)) {
        // Set our endpoint for login
        let endpoint = "auth/login"
        _rememberToken = remember
        
        // Create the authorization string (user:pass base-64 encoded)
        let base64LoginString = NSString(format: "%@:%@", username, password)
            .dataUsingEncoding(NSUTF8StringEncoding)?
            .base64EncodedStringWithOptions(NSDataBase64EncodingOptions(rawValue: 0))
        
        // Set our headers with the login string
        let headers = ["Authorization" : "Basic " + base64LoginString!]
        
        // Send the request and deal with the response as JSON
        UIApplication.sharedApplication().networkActivityIndicatorVisible = true
        sendRequest(Method.POST, endpoint: endpoint, headers:headers).responseJSON { (request, response, result) -> (Void) in
            UIApplication.sharedApplication().networkActivityIndicatorVisible = false
            if ( result.isSuccess ) {
                // Look for the auth token
                self.sessionToken = response!.allHeaderFields[self.kSessionIdHeader] as! String?
                let json = JSON(result.value!)
                
                // Create the User object
                // TODO: Should this call be made in NutshellDataController?
                let moc = NutDataController.controller().mocForCurrentUser()
                if let user = User.fromJSON(json, moc: moc) {
                    NutDataController.controller().loginUser(user)
                    completion(Result.Success(user))
                } else {
                    NutDataController.controller().logoutUser()
                    completion(Result.Failure(nil, NSError(domain: self.kNutshellErrorDomain,
                        code: -1,
                        userInfo: ["description":"Could not create user from JSON", "result":result.value!])))
                }
            } else {
                NutDataController.controller().logoutUser()
                completion(Result.Failure(nil, result.error!))
            }
        }
    }
 
    func fetchProfile(completion: (Result<JSON>) -> (Void)) {
        // Set our endpoint for the user profile
        let endpoint = "metadata/" + NutDataController.controller().currentUserId! + "/profile"
        UIApplication.sharedApplication().networkActivityIndicatorVisible = true
        sendRequest(Method.GET, endpoint: endpoint).responseJSON { (request, response, result) -> Void in
            UIApplication.sharedApplication().networkActivityIndicatorVisible = false
            if ( result.isSuccess ) {
                let json = JSON(result.value!)
                completion(Result.Success(json))
            } else {
                // Failure
                completion(Result.Failure(nil, result.error!))
            }
        }
    }
    
    func logout(completion: () -> (Void)) {
        // Clear our session token and remove entries from the db
        self.sessionToken = nil
        NutDataController.controller().logoutUser()
        completion()
    }
    
    func refreshToken(completion: (succeeded: Bool) -> (Void)) {
        
        let endpoint = "/auth/login"
        
        if self.sessionToken == nil || NutDataController.controller().currentUserId == nil {
            // We don't have a session token to refresh.
            completion(succeeded: false)
            return
        }
        
        // Post the request.
        UIApplication.sharedApplication().networkActivityIndicatorVisible = true
        self.sendRequest(Method.GET, endpoint:endpoint).responseJSON { (request, response, result) -> Void in
            UIApplication.sharedApplication().networkActivityIndicatorVisible = false
            if ( result.isSuccess ) {
                NSLog("Session token updated")
                self.sessionToken = response!.allHeaderFields[self.kSessionIdHeader] as! String?
                completion(succeeded: true)
            } else {
                NSLog("Session token update failed: \(result)")
                if let error = result.error as? NSError {
                    print("NSError: \(error)")
                    // TODO: handle network offline!
                }
                completion(succeeded: false)
            }
        }
    }
    
    /** For now this method returns the result as a JSON object. The result set can be huge, and we want processing to
     *  happen outside of this method until we have something a little less firehose-y.
     */
    func getUserData(completion: (Result<JSON>) -> (Void)) {
        // Set our endpoint for the user data
        let endpoint = "data/" + NutDataController.controller().currentUserId!;
        
        UIApplication.sharedApplication().networkActivityIndicatorVisible = true
        sendRequest(Method.GET, endpoint: endpoint).responseJSON { (request, response, result) -> Void in
            UIApplication.sharedApplication().networkActivityIndicatorVisible = false
            if ( result.isSuccess ) {
                let json = JSON(result.value!)
                completion(Result.Success(json))
            } else {
                // Failure
                completion(Result.Failure(nil, result.error!))
            }
        }
    }
    
    func getReadOnlyUserData(startDate: String, endDate: String,completion: (Result<JSON>) -> (Void)) {
        // Set our endpoint for the user data
        // TODO: centralize define of read-only events!
        let endpoint = "data/" + NutDataController.controller().currentUserId!
        UIApplication.sharedApplication().networkActivityIndicatorVisible = true
        // TODO: Alamofire isn't escaping the periods, but service appears to expect this... right now I have Alamofire modified to do this.
        // TODO: If there is no data returned, I get a failure case with status code 200, and error FAILURE: Error Domain=NSCocoaErrorDomain Code=3840 "Invalid value around character 0." UserInfo={NSDebugDescription=Invalid value around character 0.} ] Maybe an Alamofire issue?
        sendRequest(Method.GET, endpoint: endpoint, parameters: ["type":"smbg,bolus,cbg,wizard,basal", "startDate": startDate, "endDate": endDate]).responseJSON { (request, response, result) -> Void in
            UIApplication.sharedApplication().networkActivityIndicatorVisible = false
            if ( result.isSuccess ) {
                let json = JSON(result.value!)
                completion(Result.Success(json))
            } else {
                // Failure
                // TODO: Note we get here when no data is found as well - status code 200, NSCocoaErrorDomain Code 3840 "The operation couldn't be completed"
                completion(Result.Failure(nil, result.error!))
            }
        }
    }

    func clearSessionToken() -> Void {
        NSUserDefaults.standardUserDefaults().removeObjectForKey(kSessionTokenDefaultKey)
        sessionToken = nil
    }

    // MARK: - Internal methods
    
    /**
     * Sends a request to the specified endpoint
    */
    private func sendRequest(requestType: (Alamofire.Method)? = Method.GET,
        endpoint: (String),
        parameters: [String: AnyObject]? = nil,
        headers: [String: String]? = nil) -> (Request)
    {
        let url = baseUrl!.URLByAppendingPathComponent(endpoint)
        
        // Get our API headers (the session token) and add any headers supplied by the caller
        var apiHeaders = getApiHeaders()
        if ( apiHeaders != nil ) {
            if ( headers != nil ) {
                for(k, v) in headers! {
                    apiHeaders?.updateValue(v, forKey: k)
                }
            }
        } else {
            // We have no headers of our own to use- just use the caller's directly
            apiHeaders = headers
        }
        
        // Fire off the network request
        return Alamofire.request(requestType!, url, headers: apiHeaders, parameters:parameters).validate()
    }
    
    func getApiHeaders() -> [String: String]? {
        if ( sessionToken != nil ) {
            return [kSessionIdHeader : sessionToken!]
        }
        return nil
    }
 }