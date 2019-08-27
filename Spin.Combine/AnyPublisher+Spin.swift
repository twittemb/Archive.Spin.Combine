//
//  AnyPublisher+Spin.swift
//  Spin.Combine
//
//  Created by Thibault Wittemberg on 2019-08-17.
//  Copyright © 2019 Thibault Wittemberg. All rights reserved.
//

import Combine
import Spin

extension AnyPublisher: Producer & Consumable {
    public typealias Input = AnyPublisher
    public typealias Value = Output
    public typealias Executer = DispatchQueue
    public typealias Lifecycle = AnyCancellable
    
    public static func from(function: () -> Input) -> AnyProducer<Input.Input, Value, Executer, Lifecycle> {
        return function().eraseToAnyProducer()
    }

    public func compose<Output: Producer>(function: (Input) -> Output) -> AnyProducer<Output.Input, Output.Value, Output.Executer, Output.Lifecycle> {
        return function(self).eraseToAnyProducer()
    }

    public func scan<Result>(initial value: Result, reducer: @escaping (Result, Value) -> Result) -> AnyConsumable<Result, Executer, Lifecycle> {
        return self.scan(value, reducer).eraseToAnyPublisher().eraseToAnyConsumable()
    }
        
    public func consume(by: @escaping (Value) -> Void, on: Executer) -> AnyConsumable<Value, Executer, Lifecycle> {
        return self.receive(on: on).handleEvents(receiveOutput: by).eraseToAnyPublisher().eraseToAnyConsumable()
    }

    public func spy(function: @escaping (Value) -> Void) -> AnyProducer<Input, Value, Executer, Lifecycle> {
        return self.handleEvents(receiveOutput: function).eraseToAnyPublisher().eraseToAnyProducer()
    }

    public func spin() -> Lifecycle {
        return self.subscribe(PassthroughSubject<Value, Failure>())
    }
    
    public func toReactiveStream() -> Input {
        return self
    }
}

public extension AnyCancellable {
    func disposed(by disposables: inout [AnyCancellable]) {
        self.store(in: &disposables)
    }
}
