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
    public typealias Context = DispatchQueue
    public typealias Runtime = AnyCancellable
    
    public static func from(function: () -> Input) -> AnyProducer<Input.Input, Value, Context, Runtime> {
        return function().eraseToAnyProducer()
    }

    public func compose<Output: Producer>(function: (Input) -> Output) -> AnyProducer<Output.Input, Output.Value, Output.Context, Output.Runtime> {
        return function(self).eraseToAnyProducer()
    }

    public func scan<Result>(initial value: Result, reducer: @escaping (Result, Value) -> Result) -> AnyConsumable<Result, Context, Runtime> {
        return self.scan(value, reducer).eraseToAnyPublisher().eraseToAnyConsumable()
    }

    public func consume(by: @escaping (Value) -> Void, on: Context) -> AnyConsumable<Value, Context, Runtime> {
        return self.receive(on: on).handleEvents(receiveOutput: by).eraseToAnyPublisher().eraseToAnyConsumable()
    }

    public func spy(function: @escaping (Value) -> Void) -> AnyProducer<Input, Value, Context, Runtime> {
        return self.handleEvents(receiveOutput: function).eraseToAnyPublisher().eraseToAnyProducer()
    }

    public func engage() -> Runtime {
        return self.subscribe(PassthroughSubject<Value, Failure>())
    }
}
