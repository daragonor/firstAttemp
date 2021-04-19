//
//  Bundle.swift
//  First Attempt
//
//  Created by Daniel Aragon Ore on 4/18/21.
//  Copyright © 2021 Daniel Aragon. All rights reserved.
//

import Foundation
import ARKit
import RealityKit


class ModelBundle {
    internal init(_ bundle: ModelBundle) {
        self.model = bundle.model
        self.entity = bundle.entity
    }
    internal init(model: ModelEntity, entity: Entity) {
        self.model = model
        self.entity = entity
    }
    var entity: Entity
    var model: ModelEntity
    
    func rotate(to target: ModelBundle) {
        let ca = target.model.position.x - model.position.x
        let co = target.model.position.z - model.position.z
        print ("ca:\(ca), co:\(co)")
        var angle = atan(ca/co)
        if target.model.position.z < model.position.z {
            angle = angle + .pi
        }
        entity.transform.rotation = simd_quatf(angle: angle, axis: Axis.y.matrix)
    }
    
}
