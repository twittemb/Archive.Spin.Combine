//
//  Publisher+withLatestFrom.swift
//  Spin.CombineTests
//
//  Created by Thibault Wittemberg on 2019-09-16.
//  Copyright © 2019 Thibault Wittemberg. All rights reserved.
//

import Combine
@testable import Spin_Combine
import XCTest

final class Publisher_withLatestFrom: XCTestCase {

    private var cancellables = [AnyCancellable]()
    
    func testExample() {
        
        let expectations = expectation(description: "with latest from")
        expectations.expectedFulfillmentCount = 5
        let expected = ["James - 1701", "Spock - 1701", "Leonard - 1702", "Icaru - 1703", "Pavel - 1703"]
        var received = [String]()
        
        let mainSubject = PassthroughSubject<String, Never>()
        let latestSubject = CurrentValueSubject<Int, Never>(1701)
        
        mainSubject.withLatest(from: latestSubject).sink { (values) in
            let mainValue = values.0
            let latestValue = values.1
            
            received.append("\(mainValue) - \(latestValue)")
            expectations.fulfill()
            
        }.disposed(by: &self.cancellables)
        
        mainSubject.send("James")
        mainSubject.send("Spock")
        latestSubject.send(1702)
        mainSubject.send("Leonard")
        latestSubject.send(1703)
        mainSubject.send("Icaru")
        mainSubject.send("Pavel")
        
        XCTAssertEqual(received, expected)

        waitForExpectations(timeout: 5)
        
    }
}
