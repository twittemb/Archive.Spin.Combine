//
//  AnyPublisher_SpinTests.swift
//  Spin.CombineTests
//
//  Created by Thibault Wittemberg on 2019-08-17.
//  Copyright © 2019 Thibault Wittemberg. All rights reserved.
//

import Combine
import Spin_Combine
import XCTest

struct Pair<Value: Equatable>: Equatable {
    let left: Value
    let right: Value
}

final class SequencePublisher<Value>: Publisher {
    typealias Output = Value
    typealias Failure = Never
    
    private let sequence: [Value]
    
    init(sequence: [Value]) {
        self.sequence = sequence
    }
    
    func receive<S>(subscriber: S) where S : Subscriber, Failure == S.Failure, Output == S.Input {
        subscriber.receive(subscription: Subscriptions.empty)
        self.sequence.forEach { _ = subscriber.receive($0) }
        subscriber.receive(completion: .finished)
    }
}

final class AnyPublisher_SpinTests: XCTestCase {
    private var cancellables = [AnyCancellable]()
    
    func testToStream_gives_the_original_reactiveStream () {
        // Given: a from closure
        let fromClosure = { return SequencePublisher(sequence: [1]).eraseToAnyPublisher() }
        let fromClosureResult = fromClosure()
        
        // When: retrieving the stream from the closure
        let resultStream = Spin.from(function: fromClosure).toReactiveStream()
        
        // Then: the stream is of the same type than the result of the from closure
        XCTAssertTrue(type(of: resultStream) == type(of: fromClosureResult))
    }
    
    func testMutipleCompose_transforms_a_stream_elements_in_the_correct_type() {
        let expectations = expectation(description: "consume by")
        expectations.expectedFulfillmentCount = 9

        // Given: a composed stream
        // When: executing the loop
        var result = [Int]()
        Spin
            .from { return SequencePublisher(sequence: [1, 2, 3, 4, 5, 6, 7, 8, 9]).eraseToAnyPublisher() }
            .compose { return $0.map { "\($0)" }.eraseToAnyPublisher()}
            .compose { return $0.map { Int($0)! }.eraseToAnyPublisher() }
            .scan(initial: 0) { (previous, current) -> Int in
                expectations.fulfill()
                result.append(current)
                return previous + current
            }
            .spin()
        .disposed(by: &self.cancellables)

        // Then: the output values before the scan are the ones from the final transformation of compose
        waitForExpectations(timeout: 20)
        XCTAssertEqual([1, 2, 3, 4, 5, 6, 7, 8, 9], result)
    }

    func testScan_outputs_the_right_results () {
        // Given: an input stream being a sequence of ints from 1 to 9
        let serialqueue = DispatchQueue(label: "Serial Queue")
        let expectations = expectation(description: "consume by")
        expectations.expectedFulfillmentCount = 9
        let expectedResult = [1, 3, 6, 10, 15, 21, 28, 36, 45]
        var result = [Int]()

        // When: scanning the input by making the sum of all the inputs elements
        Spin.from { return SequencePublisher(sequence: [1, 2, 3, 4, 5, 6, 7, 8, 9]).eraseToAnyPublisher() }
            .scan(initial: 0) { return $0 + $1 }
            .consume(by: { value in
                expectations.fulfill()
                result.append(value)
            }, on: serialqueue)
            .spin()
            .disposed(by: &self.cancellables)

        // Then: the expectation is met with the output being a stream of the successive addition of the input elements
        waitForExpectations(timeout: 2)
        XCTAssertEqual(result, expectedResult)
    }

    func testSpy_spies_the_elements_of_the_stream () {
        // Given: an input stream being a sequence of ints from 1 to 9
        let expectations = expectation(description: "spy")
        expectations.expectedFulfillmentCount = 9
        let expectedResult = [1, 2, 3, 4, 5, 6, 7, 8, 9]
        var result = [Int]()

        // When: spying the elements of the stream
        Spin.from { return SequencePublisher(sequence: [1, 2, 3, 4, 5, 6, 7, 8, 9]).eraseToAnyPublisher() }
            .spy(function: { (value) in
                expectations.fulfill()
                result.append(value)
            })
            .scan(initial: 0) { return $0 + $1 }
            .spin()
            .disposed(by: &self.cancellables)

        // Then: the spied elements are the same as the inputs elements
        waitForExpectations(timeout: 2)
        XCTAssertEqual(result, expectedResult)
    }

    func testMiddlewares_catch_the_elements_of_scan () {
        // Given: an input stream being a sequence of ints from 1 to 9
        let expectations = expectation(description: "middlewares")
        expectations.expectedFulfillmentCount = 27
        let expectedResult = [Pair(left: 0, right: 1),
                              Pair(left: 1, right: 2),
                              Pair(left: 3, right: 3),
                              Pair(left: 6, right: 4),
                              Pair(left: 10, right: 5),
                              Pair(left: 15, right: 6),
                              Pair(left: 21, right: 7),
                              Pair(left: 28, right: 8),
                              Pair(left: 36, right: 9)]
        var result = [Pair<Int>]()

        // When: spying the elements of the stream
        Spin.from { return SequencePublisher(sequence: [1, 2, 3, 4, 5, 6, 7, 8, 9]).eraseToAnyPublisher() }
            .scan(initial: 0, reducer: { $0 + $1 }, middlewares: { (previous, current) in
                expectations.fulfill()
                result.append(Pair(left: previous, right: current))
            }, { (previous, current) in
                expectations.fulfill()
            }, { (previous, current) in
                expectations.fulfill()
            })
            .spin()
            .disposed(by: &self.cancellables)

        // Then: the spied elements are the same as the inputs elements
        waitForExpectations(timeout: 2)
        XCTAssertEqual(result, expectedResult)
    }

    func testSchedulers_execute_layers_on_good_queues () {
        let expectations = expectation(description: "schedulers")
        expectations.expectedFulfillmentCount = 7

        let fromQueue = DispatchQueue(label: "FROM_QUEUE")
        let composeQueue = DispatchQueue(label: "COMPOSE_QUEUE")
        let consumeQueue1 = DispatchQueue(label: "CONSUME_QUEUE_1")
        let consumeQueue2 = DispatchQueue(label: "CONSUME_QUEUE_2")

        // Given: an input stream being a a single element
        // When: executing the different layers off the loop on different Queues
        // Then: the queues are respected
        Spin
            .from { () -> AnyPublisher<Int, Never> in
                expectations.fulfill()
                return SequencePublisher(sequence: [1]).receive(on: fromQueue).eraseToAnyPublisher()
            }
            // switch to FROM_QUEUE after from
            .spy { _ in
                expectations.fulfill()
                XCTAssertEqual(DispatchQueue.currentLabel, "FROM_QUEUE")
            }
            .compose { input -> AnyPublisher<String, Never> in
                expectations.fulfill()
                return input.map { "\($0)" }.receive(on: composeQueue).eraseToAnyPublisher()
            }
            // switch to COMPOSE_QUEUE after compose
            .spy { _ in
                expectations.fulfill()
                XCTAssertEqual(DispatchQueue.currentLabel, "COMPOSE_QUEUE")
            }
            .scan(initial: "") { (previous, current) -> String in
                expectations.fulfill()
                return previous + current
            }
            // switch to CONSUME_QUEUE_1 before consume
            .consume(by: { _ in
                expectations.fulfill()
                XCTAssertEqual(DispatchQueue.currentLabel, "CONSUME_QUEUE_1")
            }, on: consumeQueue1)
            // switch to CONSUME_QUEUE_2 before consume
            .consume(by: { _ in
                expectations.fulfill()
                XCTAssertEqual(DispatchQueue.currentLabel, "CONSUME_QUEUE_2")
            }, on: consumeQueue2)
            .spin()
            .disposed(by: &self.cancellables)

        waitForExpectations(timeout: 2)

    }
}

// workaround found here: https://lists.swift.org/pipermail/swift-users/Week-of-Mon-20160613/002280.html
extension DispatchQueue {
    class var currentLabel: String {
        return String(validatingUTF8: __dispatch_queue_get_label(nil))!
    }
}
