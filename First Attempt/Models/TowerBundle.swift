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


class TowerBundle: ModelBundle {
    internal init(bundle: ModelBundle, type: TowerType, lvl: TowerLevel = .lvl1, accessory: Entity, collisionSubs: [Cancellable]) {
        self.type = type
        self.lvl = lvl
        self.accessory = accessory
        self.enemiesIds = []
        self.collisionSubs = collisionSubs
        super.init(bundle)
    }
    var type: TowerType
    var lvl: TowerLevel
    var accessory: Entity
    var enemiesIds: [UInt64]
    var collisionSubs: [Cancellable]
}
