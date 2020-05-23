//
//  Map.swift
//  First Attempt
//
//  Created by Daniel Aragon on 5/22/20.
//  Copyright © 2020 Daniel Aragon. All rights reserved.
//

import Foundation
import RealityKit


enum MapLegend: CaseIterable {
    case neutral, goal, tower, spawn, creepPath, highCreepPath, zipLineIn, zipLineOut
}
class GameModel: Codable {
    var levels: [LevelModel]
}
class LevelModel: Codable {
    var difficulty: Int
    var maps: [MapModel]
}
class MapModel: Codable {
    var creepPath: [[String]]
    var matrix: [[Int]]
}
