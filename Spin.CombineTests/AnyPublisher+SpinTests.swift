//
//  AnyPublisher_SpinTests.swift
//  Spin.CombineTests
//
//  Created by Thibault Wittemberg on 2019-08-17.
//  Copyright © 2019 Thibault Wittemberg. All rights reserved.
//

import Combine
import Spin
import Spin_Combine
import XCTest

struct MockState: Equatable {
    let value: Int

    static let zero = MockState(value: 0)
}

enum MockAction: Equatable {
    case increment
    case reset
}

class IncrementCommand: Command {
    var operationQueueOfExecutionName: String?
    private let shouldError: Bool

    init(shouldError: Bool = false) {
        self.shouldError = shouldError
    }

    func execute(basedOn state: MockState) -> AnyPublisher<MockAction, TestError> {
        guard !self.shouldError else { return Fail(error: TestError()).eraseToAnyPublisher() }

        self.operationQueueOfExecutionName = DispatchQueue.currentLabel

        if state.value >= 5 {
            return Result<MockAction, TestError>.success(.reset).publisher.eraseToAnyPublisher()
        }

        return Result<MockAction, TestError>.success(.increment).publisher.eraseToAnyPublisher()
    }
}

struct ResetCommand: Command {
    func execute(basedOn state: MockState) -> AnyPublisher<MockAction, TestError> {
        return Result<MockAction, TestError>.success(.reset).publisher.eraseToAnyPublisher()
    }
}

struct TestError: Error {
}

let reducer: (MockState, MockAction) -> MockState = { (state, action) in
    switch action {
    case .increment:
        return MockState(value: state.value + 1)
    case .reset:
        return MockState(value: 0)
    }
}

final class AnyPublisher_SpinTests: XCTestCase {

    private var disposeBag = [AnyCancellable]()

    // MARK: tests Consumable conformance

    func testConsume_receives_all_the_events_from_the_inputStream() {
        // Given: some values to emit as a stream
        let exp = expectation(description: "consume")
        exp.expectedFulfillmentCount = 9

        let expectedValues = [1, 2, 3, 4, 5, 6, 7, 8, 9]
        var consumedValues = [Int]()

        // When: consuming a stream of input values
        expectedValues
            .publisher
            .eraseToAnyPublisher()
            .consume(by: { value in
                consumedValues.append(value)
                exp.fulfill()
            }, on: DispatchQueue.main)
            .spin()
            .disposed(by: &self.disposeBag)

        waitForExpectations(timeout: 2)

        // Then: consumes values are the same os the input values
        XCTAssertEqual(consumedValues, expectedValues)
    }

    func testConsume_switches_to_the_expected_queues () {
        let expectations = expectation(description: "schedulers")
        expectations.expectedFulfillmentCount = 18

        let consumeQueue1 = DispatchQueue(label: "CONSUME_QUEUE_1")
        let consumeQueue2 = DispatchQueue(label: "CONSUME_QUEUE_2")

        // Given: some values to emit as a stream
        // When: consuming these values on different Executers
        // Then: the Executers are respected
        [1, 2, 3, 4, 5, 6, 7, 8, 9]
            .publisher
            .eraseToAnyPublisher()
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
            .disposed(by: &self.disposeBag)

        waitForExpectations(timeout: 2)
    }

    // MARK: tests Producer conformance

    func testToReactiveStream_gives_the_original_inputStream () {

        // Given: a from closure
        let fromClosure = { () -> AnyPublisher<AnyCommand<AnyPublisher<MockAction, TestError>, MockState>, Never> in
            return Just<AnyCommand<AnyPublisher<MockAction, TestError>, MockState>>(ResetCommand().eraseToAnyCommand()).eraseToAnyPublisher()
        }
        let fromClosureResult = fromClosure()

        // When: retrieving the stream from the closure
        let resultStream = Spinner.from(function: fromClosure).toReactiveStream()

        // Then: the stream is of the same type than the result of the from closure
        XCTAssertTrue(type(of: resultStream) == type(of: fromClosureResult))
    }

    //    func testSpy_sees_all_the_events_from_the_inputStream() {
    //
    //        // Given: some commands to emit as a stream
    //        let inputStream = SignalProducer<AnyCommand<SignalProducer<MockAction, TestError>, MockState>, Never>([
    //            IncrementCommand().eraseToAnyCommand(),
    //            ResetCommand().eraseToAnyCommand()
    //            ])
    //
    //        var spiedCommands: [AnyCommand<SignalProducer<MockAction, TestError>, MockState>] = []
    //
    //        // When: spying the stream of commands
    //        _ = Spinner
    //            .from { inputStream }
    //            .spy { spiedCommands.append($0) }
    //            .toReactiveStream()
    //            .wait()
    //
    //        // Then: consumes values are the same os the input values
    //        XCTAssertEqual(spiedCommands.count, 2)
    //        let action1 = try? spiedCommands[0].execute(basedOn: MockState(value: 0)).first()?.get()
    //        let action2 = try? spiedCommands[1].execute(basedOn: MockState(value: 0)).first()?.get()
    //
    //        XCTAssertEqual(action1!, .increment)
    //        XCTAssertEqual(action2!, .reset)
    //    }

    func testFeedback_computes_the_expected_states() {
        let exp = expectation(description: "feedback")
        exp.expectedFulfillmentCount = 7
        var receivedStates = [MockState]()

        // Given: some commands to emit as a stream
        let inputStream = [
            IncrementCommand().eraseToAnyCommand(),
            IncrementCommand().eraseToAnyCommand(),
            IncrementCommand().eraseToAnyCommand(),
            IncrementCommand().eraseToAnyCommand(),
            IncrementCommand().eraseToAnyCommand(),
            IncrementCommand().eraseToAnyCommand()
            ].publisher.eraseToAnyPublisher()

        // When: runing a feedback loop on the stream of commands
        Spinner
            .from { inputStream }
            .feedback(initial: .zero, reducer: reducer)
            .consume(by: { state in
                exp.fulfill()
                receivedStates.append(state)
            }, on: DispatchQueue.main)
            .spin()
            .disposed(by: &self.disposeBag)

        waitForExpectations(timeout: 2)

        // Then: the computed states are good (and relying on the previous state values -> see the implementation of IncrementCommand)
        XCTAssertEqual(receivedStates.map { $0.value }, [0, 1, 2, 3, 4, 5, 0])
    }

    func testLoop_does_not_stop_in_case_of_error_in_a_command() {
        let exp = expectation(description: "feedback")
        exp.expectedFulfillmentCount = 2
        var receivedStates = [MockState]()

        // Given: some commands to emit as a stream
        let inputStream = [
            IncrementCommand(shouldError: true).eraseToAnyCommand(),
            IncrementCommand(shouldError: false).eraseToAnyCommand()
            ].publisher.eraseToAnyPublisher()

        // When: runing a feedback loop on the stream of commands
        Spinner
            .from { inputStream }
            .feedback(initial: .zero, reducer: reducer)
            .consume(by: { state in
                exp.fulfill()
                receivedStates.append(state)
            }, on: DispatchQueue.main)
            .spin()
            .disposed(by: &self.disposeBag)

        waitForExpectations(timeout: 2)

        // Then: the computed states are good (the command that failed did not stop the loop)
        XCTAssertEqual(receivedStates.map { $0.value }, [0, 1])
    }

    func testExecuters_are_correctly_applied () {
        let expectations = expectation(description: "schedulers")
        //        expectations.expectedFulfillmentCount = 6
        expectations.expectedFulfillmentCount = 5

        let fromQueue = DispatchQueue(label: "FROM_QUEUE")
        let consumeQueue1 = DispatchQueue(label: "CONSUME_QUEUE_1")
        let consumeQueue2 = DispatchQueue(label: "CONSUME_QUEUE_2")

        // Given: an input stream being a single Command
        // When: executing the different layers of the loop on different Executers
        // Then: the Executers are respected
        let commandToExecute = IncrementCommand()
        let inputStream = [commandToExecute.eraseToAnyCommand()].publisher.eraseToAnyPublisher()

        Spinner
            .from { () -> AnyPublisher<AnyCommand<AnyPublisher<MockAction, TestError>, MockState>, Never> in
                expectations.fulfill()
                return inputStream.receive(on: fromQueue).eraseToAnyPublisher()
        }
            // switch to FROM_QUEUE after from
            //            .spy(function: { _ in
            //                expectations.fulfill()
            //                XCTAssertEqual(DispatchQueue.currentLabel, "FROM_QUEUE")
            //            })
            .feedback(initial: .zero, reducer: reducer)
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
            .disposed(by: &self.disposeBag)

        waitForExpectations(timeout: 2)

        XCTAssertEqual(commandToExecute.operationQueueOfExecutionName!, "FROM_QUEUE")
    }
}

// workaround found here: https://lists.swift.org/pipermail/swift-users/Week-of-Mon-20160613/002280.html
extension DispatchQueue {
    class var currentLabel: String {
        return String(validatingUTF8: __dispatch_queue_get_label(nil))!
    }
}
