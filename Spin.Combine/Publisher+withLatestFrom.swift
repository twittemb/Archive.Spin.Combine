//
//  Publisher+withLatestFrom.swift
//  Spin.Combine
//
//  Created by Thibault Wittemberg on 2019-09-16.
//  Copyright © 2019 Thibault Wittemberg. All rights reserved.
//

import Combine

class CompositionSubscripttion: Subscription {
    
    let cancellables: [AnyCancellable]
    
    init(cancellables: [AnyCancellable]) {
        self.cancellables = cancellables
    }
    
    func request(_ demand: Subscribers.Demand) {
        
    }
    
    func cancel() {
        self.cancellables.forEach { $0.cancel() }
    }
}

extension Publisher {
    func withLatest<LatestPublisher: Publisher>(from latestPublisher: LatestPublisher) -> Publishers.WithLatestFrom<Self, LatestPublisher> where LatestPublisher.Failure == Never {
        return Publishers.WithLatestFrom<Self, LatestPublisher>(mainPublisher: self, latestPublisher: latestPublisher)
    }
}

extension Publishers {
    class WithLatestFrom<MainPublisher: Publisher, LatestPublisher: Publisher>: Publisher where LatestPublisher.Failure == Never {
        
        typealias Output = (MainPublisher.Output, LatestPublisher.Output)
        typealias Failure = MainPublisher.Failure
        
        private let mainPublisher: MainPublisher
        private let latestPublisher: LatestPublisher
        
        private var cancellables = [AnyCancellable]()
        
        init(mainPublisher: MainPublisher, latestPublisher: LatestPublisher) {
            self.mainPublisher = mainPublisher
            self.latestPublisher = latestPublisher
        }
        
        func receive<S>(subscriber: S) where S : Subscriber, Failure == S.Failure, Output == S.Input {
            
            var latestValue: LatestPublisher.Output?
            
            self.latestPublisher.sink { (value) in
                latestValue = value
            }.disposed(by: &self.cancellables)
            
            self.mainPublisher.sink(receiveCompletion: { (completion) in
                subscriber.receive(completion: completion)
            }) { (value) in
                if let latestValue = latestValue {
                    _ = subscriber.receive((value, latestValue))
                }
            }.disposed(by: &self.cancellables)
            
            subscriber.receive(subscription: CompositionSubscripttion(cancellables: self.cancellables))
            
        }
    }
}
