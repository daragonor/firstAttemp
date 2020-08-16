//
//  Models.swift
//  First Attempt
//
//  Created by Daniel Aragon on 8/16/20.
//  Copyright © 2020 Daniel Aragon. All rights reserved.
//

import Foundation
import ARKit
import RealityKit
import Combine


class TowerBunddle {
    var model: ModelEntity
    var type: TowerType
    var lvl: TowerLevel
    var accesory: Entity
    var enemiesIds: [UInt64]
    var collisionSubs: [Cancellable]
    init(model: ModelEntity, lvl: TowerLevel = .lvl1, type: TowerType, accesory: Entity, collisionSubs: [Cancellable]) {
        self.model = model
        self.type = type
        self.lvl = lvl
        self.type = type
        self.accesory = accesory
        self.enemiesIds = []
        self.collisionSubs = collisionSubs
    }
}
