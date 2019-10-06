//
//  AnyPublisher+Spin.swift
//  Spin.Combine
//
//  Created by Thibault Wittemberg on 2019-08-17.
//  Copyright © 2019 Thibault Wittemberg. All rights reserved.
//

import Combine
import Spin

extension AnyPublisher: Consumable {
    public typealias Value = Output
    public typealias Executer = DispatchQueue
    public typealias Lifecycle = AnyCancellable

    public func consume(by: @escaping (Value) -> Void, on: Executer) -> AnyConsumable<Value, Executer, Lifecycle> {
        return self
            .receive(on: on)
            .handleEvents(receiveOutput: by)
            .eraseToAnyPublisher()
            .eraseToAnyConsumable()
    }

    public func spin() -> Lifecycle {
        return self.sink(receiveCompletion: { _ in }, receiveValue: { _ in })
    }
}

extension AnyPublisher: Producer where Value: Command, Value.Stream: Publisher, Value.Stream.Output == Value.Stream.Value, Failure == Never {
    public typealias Input = AnyPublisher

    public func feedback(initial value: Value.State, reducer: @escaping (Value.State, Value.Stream.Value) -> Value.State) -> AnyConsumable<Value.State, Executer, Lifecycle> {
        let currentState = CurrentValueSubject<Value.State, Never>(value)

        return self
            .withLatest(from: currentState.eraseToAnyPublisher())
            .flatMap { args -> AnyPublisher<Value.Stream.Value, Never> in
                let (command, state) = args
                return command.execute(basedOn: state).catch { _ in return Empty() }.eraseToAnyPublisher()
            }
        .scan(value, reducer)
        .prepend(value)
        .handleEvents(receiveOutput: { currentState.send($0) })
        .eraseToAnyPublisher()
        .eraseToAnyConsumable()
    }

//    public func spy(function: @escaping (Value) -> Void) -> AnyProducer<Input, Value, Executer, Lifecycle> {
//        return self
//            .handleEvents(receiveOutput: function)
//            .eraseToAnyPublisher()
//            .eraseToAnyProducer()
//    }

    public func toReactiveStream() -> Input {
        return self
    }
}

public extension AnyCancellable {
    func disposed(by disposables: inout [AnyCancellable]) {
        self.store(in: &disposables)
    }
}
