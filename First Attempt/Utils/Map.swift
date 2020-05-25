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
    //hightowerplacing
    case neutral, goal, towerPlacing, spawn, lowCreepPath, highCreepPath, zipLineIn, zipLineOut
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
//    func creepPathsPositions() -> [[Position]] {
//        return allPaths.map { path in
//            return path.map { stringPosition in
//                let position = stringPosition.split(separator: ",")
//                return Position(Int(String(position[0]))!, Int(String(position[1]))!)
//            }
//        }
//    }
    func creepPathsCoordinates(diameter: Float) -> [[SIMD3<Float>]] {
        return allPaths.map { path in
            return path.map { stringPosition in
                let positionStrings = stringPosition.split(separator: ",").map { String($0) }
                let (row, column) = (Int(positionStrings.first!)!, Int(positionStrings.last!)!)
                let (rows, columns) = (self.matrix.count, self.matrix.first!.count)
                let (rowDistance, columnDistance) = (Float(rows / 2) - diameter, Float(columns / 2) - diameter)
                let mapCode = self.matrix[row][column]
                let x = (Float(row) - rowDistance ) * 0.1
                let y: Float = mapCode == 5 ? 0.1 : 0.0
                let z = (Float(column) - columnDistance) * 0.1
                return [x, y, z]
            }
        }
    }
}
