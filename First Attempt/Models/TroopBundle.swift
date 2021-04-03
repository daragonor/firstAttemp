//
//  TroopBundle.swift
//  First Attempt
//
//  Created by Daniel Aragon Ore on 3/27/21.
//  Copyright © 2021 Daniel Aragon. All rights reserved.
//

import Foundation
import ARKit
import RealityKit
import Combine

class TroopBundle: UnitBundle {
    internal init(hpBarId: UInt64, maxHP: Float, towerId: UInt64, enemiesIds: [UInt64] = []) {
        self.towerId = towerId
        self.enemiesIds = enemiesIds
        super.init(hpBarId: hpBarId, hp: maxHP, maxHP: maxHP)
    }
    
    var towerId: UInt64
    var enemiesIds: [UInt64]
}
