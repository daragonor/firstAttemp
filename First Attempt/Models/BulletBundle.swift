//
//  Bullet Bundle.swift
//  First Attempt
//
//  Created by Daniel Aragon Ore on 3/27/21.
//  Copyright © 2021 Daniel Aragon. All rights reserved.
//

import Foundation
import ARKit
import RealityKit
import Combine

class BulletBundle {
    internal init(model: ModelEntity, animation: AnimationPlaybackController, subscription: Cancellable?) {
        self.model = model
        self.animation = animation
        self.subscription = subscription
    }
    
    var model: ModelEntity
    var animation: AnimationPlaybackController
    var subscription: Cancellable?
}
