//
//  TealiumModulesManager.swift
//  tealium-swift
//
//  Created by Jason Koo on 10/5/16.
//  Copyright © 2016 tealium. All rights reserved.
//
//  Build 3

import Foundation

/**
    Coordinates optional modules with primary Tealium class.
 */
class TealiumModulesManager : NSObject {
    
    var modules = [TealiumModule]()
    var isEnabled = true
    var modulesRequestingReport = [Weak<TealiumModule>]()
    let timeoutMillisecondIncrement = 250
    var timeoutMillisecondCurrent = 0
    let timeoutMillisecondMax = 2000
    
    func setupModulesFrom(config: TealiumConfig) {
        
        let modulesList = config.getModulesList()
        let newModules = TealiumModules.allModulesFor(modulesList,
                                                      assigningDelegate: self)
        self.modules = newModules.prioritized()
    }
    
    // MARK:
    // MARK: PUBLIC
    func update(config:TealiumConfig){
        
        self.modules.removeAll()
        enable(config: config)
        
    }
    
    
    func enable(config: TealiumConfig) {
        
        self.setupModulesFrom(config: config)
        let request = TealiumEnableRequest(config: config)
        self.modules.first?.handle(request)
        
    }
    
    
    func disable() {
        
        isEnabled = false
        let request = TealiumDisableRequest()
        self.modules.first?.handle(request)
        
    }

    
    func getModule(forName: String) -> TealiumModule? {
        
        return modules.first(where: { type(of:$0).moduleConfig().name == forName})

    }
    
    func modulesNotReady(_ modules: [TealiumModule]) -> [TealiumModule] {
        var result = [TealiumModule]()
        for module in modules {
            if module.isEnabled == false {
                result.append(module)
            }
        }
        return result
    }
    
    func track(_ track: TealiumTrackRequest) {
        
        guard let firstModule = modules.first else {
            track.completion?(false, nil, TealiumModulesManagerError.noModules)
            return
        }
        
        if isEnabled == false {
            track.completion?(false, nil, TealiumModulesManagerError.isDisabled)
            return
        }
        
        let notReady = modulesNotReady(modules)
        
        if notReady.isEmpty == false {
            
            timeoutMillisecondCurrent += timeoutMillisecondIncrement
            if timeoutMillisecondCurrent >= timeoutMillisecondMax {
                print("*** Tealium library failed to enable module(s): \(notReady)")
                return
            }
            let delay = DispatchTime.now() + .milliseconds(timeoutMillisecondCurrent)
            DispatchQueue.global(qos: .background).asyncAfter(deadline: delay, execute: {
                // Put call into end of queue until all modules ready.
                self.track(track)
            })
            return
            
        }
        
        self.timeoutMillisecondCurrent = 0  // reset
        
        firstModule.handle(track)
    }

    // MARK:
    // MARK: INTERNAL
    
    internal func reportToModules(_ modules: [Weak<TealiumModule>],
                                  request: TealiumRequest) {
        
        for moduleRef in modules {
            
            guard let module = moduleRef.value else {
                // Module has been dereferenced
                continue
            }
            
            module.handleReport(request)

        }
        
    }
}

// MARK:
// MARK: TEALIUM MODULE DELEGATE

extension TealiumModulesManager : TealiumModuleDelegate {
    
    func tealiumModuleFinished(module: TealiumModule,
                               process: TealiumRequest) {
        
        guard let nextModule = modules.next(after: module) else {
            
            // If enable call set isEnable
            if let _ = process as? TealiumEnableRequest {
                self.isEnabled = true
            }
            
            // Last module has finished processing
            reportToModules(modulesRequestingReport,
                            request: process)
            
            return
        }
        
        nextModule.handle(process)
    }
    
    func tealiumModuleRequests(module: TealiumModule,
                               process: TealiumRequest) {

        
        // Module wants to be notified when last module has finished processing
        //  any requests.
        if let _ = process as? TealiumReportNotificationsRequest {
            
            let existingRequestModule = modulesRequestingReport.filter{ $0.value == module }
            if existingRequestModule.count == 0 {
                modulesRequestingReport.append(Weak(value:module))
            }
            
            return
        }
        
        // Module wants to notify any listening modules of status.
        if let process = process as? TealiumReportRequest {
            reportToModules(modulesRequestingReport,
                            request: process)
            return
        }
        
        if let track = process as? TealiumTrackRequest {
            self.track(track)
            return
        }
        
        if let enable = process as? TealiumEnableRequest {
            self.enable(config: enable.config)
            return
        }
        
        if let _ = process as? TealiumDisableRequest {
            self.disable()
            return
        }
        
        if isEnabled == false {
            return
        }
        
        // Pass request to other modules - Regular behavior
        modules.first?.handle(process)
    }
    
}

// MARK: 
// MARK: MODULEMANAGER EXTENSIONS
extension Array where Element : TealiumModule {

    /**
     Convenience for sorting Arrays of TealiumModules by priority number: Lower numbers going first.
     */
    func prioritized() -> [TealiumModule] {
        return self.sorted{
            type(of:$0).moduleConfig().priority < type(of:$1).moduleConfig().priority
        }
        
    }
    
    
    /// Get all existing module names, in current order
    ///
    /// - Returns: Array of module names.
    func moduleNames() -> [String] {
        
        return self.map { type(of:$0).moduleConfig().name }
        
    }
    
}

extension Array where Element: Equatable {

    /**
     Convenience for getting the next object in a given array.
     */
    func next(after:Element) -> Element? {
        
        for i in 0..<self.count {
            let object = self[i]
            if object == after {
                
                if i + 1 < self.count {
                    return self[i+1]
                }
            }
        }
        
        return nil
        
    }
    
}
