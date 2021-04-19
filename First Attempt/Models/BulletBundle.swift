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

class BulletBundle: ModelBundle {
    internal init(bundle: ModelBundle, animation: AnimationPlaybackController, subscription: Cancellable?) {
        self.animation = animation
        self.subscription = subscription
        super.init(bundle)
    }
    
    var animation: AnimationPlaybackController
    var subscription: Cancellable?
}
