//
//  Map.swift
//  First Attempt
//
//  Created by Daniel Aragon on 5/22/20.
//  Copyright © 2020 Daniel Aragon. All rights reserved.
//

import Foundation
import RealityKit
import GameplayKit

enum MapLegend: CaseIterable {
    case neutral, goal, lowerTower, higherTower, spawn, lowerPath, higherPath, zipLineIn, zipLineOut
}

enum Direction: CaseIterable {
    case up, down, left, right
    var offset: Position {
        switch self {
        case .up: return (0, 1)
        case .down: return (0, -1)
        case .left: return (-1, 0)
        case .right: return (1, 0)
        }
    }
    var rotation: simd_quatf {
        var angle: Float {
            switch self {
            case .up: return 0
            case .down: return .pi
            case .left: return -.pi/2
            case .right: return .pi/2
            }
        }
        return simd_quatf(angle: angle, axis: [0, 1, 0])
    }
}

enum TowerAssets: CaseIterable {
    case type1
}

enum CreepAssets: CaseIterable {
    case type1
}

enum PathAssets: CaseIterable {
    case type1
}

struct GameModel: Codable {
    var assets: AssetsModel
    var levels: [LevelModel]
}

struct AssetsModel: Codable {
    var creeps: [GroundUnitModel]
    var towers: [TowerModel]
    var paths: [BasicModel]
    var goal: BasicModel
    var spawn: BasicModel
}

struct BasicModel: Codable {
    var fileName: String
    var scalingFactor: Float
}

struct GroundUnitModel: Codable {
    var fileName: String
    var scalingFactor: Float
    var lifePoints: Int
}

class TowerModel: Codable {
    var fileName: String
    var scalingFactor: Float
    var attackValue: Float
    var range: Float
}

struct LevelModel: Codable {
    var difficulty: Int
    var maps: [MapModel]
}

typealias Position = (row: Int, column: Int)
typealias OrientedPosition = (position: Position, rotation: Direction)
typealias OrientedCoordinate = (traslation: SIMD3<Float>, direction: Direction)

struct MapModel: Codable {
    var matrix: [[Int]]
    var rows: Int
    var columns: Int
    var allPaths = [[OrientedPosition]]()
    var spawns = [Position]()
    var goals = [Position]()

    enum CodingKeys: String, CodingKey {
        case matrix
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        matrix = try values.decode([[Int]].self, forKey: .matrix)
        (rows, columns) = (self.matrix.count, self.matrix.first!.count)
        for (rowIndex, row) in matrix.enumerated() {
            for (columnIndex, column) in row.enumerated() {
                switch MapLegend.allCases[column] {
                case .goal: goals.append((rowIndex, columnIndex))
                case .spawn, .zipLineIn: spawns.append((rowIndex, columnIndex))
                default: break
                }
            }
        }
        for spawn in spawns {
            moveTo((spawn, .down), path: [])
        }
    }
    mutating func moveTo(_ orientedPosition: OrientedPosition, path: [OrientedPosition]) {
        let current = orientedPosition.position
        var path = path
        path.append(orientedPosition)
        let mapType = MapLegend.allCases[matrix[current.row][current.column]]
        if [MapLegend.goal, .zipLineOut].contains(mapType) {
            allPaths.append(path)
            return
        } else {
            for direction in Direction.allCases {
                let position = Position(current.row + direction.offset.row, current.column + direction.offset.column)
                if position.row >= 0 && position.row < rows &&
                    position.column >= 0 && position.column < columns &&
                    !path.contains(where: { previous, _ in return (previous.row == position.row && previous.column == position.column) }) &&
                    [MapLegend.lowerPath, .higherPath, .goal, .zipLineOut].contains(MapLegend.allCases[matrix[position.row][position.column]]) {
                    moveTo((position, .right), path: path)
                } 
            }
        }
    }
    
    func creepPathsCoordinates(at position: Position, diameter: Float) -> [OrientedCoordinate] {
        let (rowDistance, columnDistance) = (Float(rows / 2) - diameter, Float(columns / 2) - diameter)
        let paths = allPaths.filter { path in
            return position == path.first!.position
        }
        return paths[Int.random(in: 0..<paths.count)].map { (position, direction) in
            let (row, column) = position
            let x = (Float(row) - rowDistance ) * 0.1
            var y: Float {
                switch MapLegend.allCases[self.matrix[row][column]] {
                case .higherPath, .higherTower: return 0.1
                default: return 0.0
                }
            }
            let z = (Float(column) - columnDistance) * 0.1
            return ([x, y, z], direction)
        }
    }
}
