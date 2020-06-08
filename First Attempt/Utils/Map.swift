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
    var baseRotation: Float {
        switch self {
        case .up: return 0
        case .right: return .pi/2
        case .down: return .pi
        case .left: return 3*(.pi)/2
        }
    }
    func rotation(previous: Direction) -> Float {
        switch (self, previous) {
        case (.up, .right), (.right, .up): return .pi/4
        case (.right, .down), (.down, .right): return 3*(.pi)/4
        case (.down, .left), (.left, .down): return 5*(.pi)/4
        case (.left, .up), (.up, .left): return 7*(.pi)/4
        default: return 0.0
        }
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
typealias OrientedPosition = (position: Position, direction: Direction)
typealias OrientedCoordinate = (coordinate: SIMD3<Float>, rotation: simd_quatf)

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
            moveTo((spawn, Direction.down), path: [])
        }
    }
    mutating func moveTo(_ orientedPosition: OrientedPosition, path: [OrientedPosition]) {
        var path = path
        let current = orientedPosition.position
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
                    moveTo((position, direction), path: path)
                } 
            }
        }
    }
    
    func creepPathsCoordinates(at position: Position, diameter: Float, aditionalRotationOffset: Float = 0) -> [[OrientedCoordinate]] {
        let (rowDistance, columnDistance) = (Float(rows / 2) - diameter, Float(columns / 2) - diameter)
        let pathsPerSpawn = allPaths.filter { path in
            return position == path.first!.position
        }
        return pathsPerSpawn.map { path in
            return path.enumerated().map { (index, move) in
                let (row, column) = move.position
                let x = (Float(row) - rowDistance ) * 0.1
                var y: Float {
                    switch MapLegend.allCases[self.matrix[row][column]] {
                    case .higherPath, .higherTower: return 0.1
                    default: return 0.0
                    }
                }
                let z = (Float(column) - columnDistance) * 0.1

                var rotation: Float {
                    guard index + 1 < path.count, path[index + 1].direction != move.direction else { return move.direction.baseRotation}
                    return path[index + 1].direction.rotation(previous: move.direction)
                }
                return ([x, y, z], simd_quatf(angle: rotation + aditionalRotationOffset, axis: [0, 1, 0]))
            }
        }
    }
}
