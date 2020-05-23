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
    case neutral, goal, tower, spawn, lowCreepPath, highCreepPath, zipLineIn, zipLineOut
}
struct GameModel: Codable {
    var levels: [LevelModel]
}
struct LevelModel: Codable {
    var difficulty: Int
    var maps: [MapModel]
}
typealias Position = (x: Int, z: Int)
struct MapModel: Codable {
    var allPaths: [[String]]
    var matrix: [[Int]] = []
    func creepPaths() -> [[Position]] {
        return allPaths.map { path in
            return path.map { stringPosition in
                let position = stringPosition.split(separator: ",")
                return Position(Int(String(position[0]))!, Int(String(position[1]))!)
            }
        }
    }
}
