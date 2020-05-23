//
//  Components.swift
//  First Attempt
//
//  Created by Daniel Aragon on 5/6/20.
//  Copyright © 2020 Daniel Aragon. All rights reserved.
//

import Foundation
import RealityKit
import Combine
import UIKit

class CreepEntity: Entity, HasModel, HasCollision, HasAnchoring {
    var entitySubs: [Cancellable] = []
    
    required init(color: UIColor) {
        super.init()
        // Shape of this entity for any collisions including gestures
        self.components[CollisionComponent] = CollisionComponent(
            shapes: [.generateBox(size: [1,0.2,1])],
            mode: .trigger,
            filter: .sensor
        )
        
        // Model of this entity, the physical appearance is a 1x0.2x1 cuboid
        
        self.components[ModelComponent] = ModelComponent(
            mesh: .generateBox(size: [1, 0.2, 1]),
            materials: [SimpleMaterial(
                color: color,
                isMetallic: false)
            ]
        )
       
    }
    
    convenience init(color: UIColor, position: SIMD3<Float>) {
        self.init(color: color)
        self.position = position
    }
    
    required convenience init() {
        self.init(color: .orange)
    }
}
