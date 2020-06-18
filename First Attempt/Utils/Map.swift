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

enum TowerType: CaseIterable {
    case turret, rocketLauncher, barracks
    var cost: Int {
        switch self {
        case .turret: return 150
        case .rocketLauncher: return 200
        case .barracks: return 300
        }
    }
    var range: Float {
        switch self {
        case .turret: return 3.0
        case .rocketLauncher: return 6.0
        case .barracks: return 1.0
        }
    }
    var capacity: Int {
        switch self {
        case .turret: return 1
        case .rocketLauncher: return 2
        case .barracks: return 1
        }
    }
    
}
enum TowerStates: CaseIterable {
    case empty, phase1, phase2
}

enum MapLegend: CaseIterable {
    case neutral, goal, lowerPlacing, higherPlacing, spawn, lowerPath, higherPath, zipLineIn, zipLineOut
}

enum Direction: CaseIterable {
    case up, down, left, right
    case upright, downright, downleft, upleft
    static var baseMoves: [Direction] {
        return [.up, .down, .left, .right]
    }
    
    var offset: Position {
        switch self {
        case .up: return (0, 1)
        case .down: return (0, -1)
        case .left: return (-1, 0)
        case .right: return (1, 0)
        case .upright: return (1, 1)
        case .downright: return (1, -1)
        case .downleft: return (-1, -1)
        case .upleft : return (-1, 1)
        }
    }
    var angle: Float {
        switch self {
        case .up: return 0
        case .right: return .pi/2
        case .down: return .pi
        case .left: return 3*(.pi)/2
        case .upright: return .pi/4
        case .downright: return 3*(.pi)/4
        case .downleft: return 5*(.pi)/4
        case .upleft : return 7*(.pi)/4
        }
    }
    func rotation(offset: Float = 0) -> simd_quatf {
        return simd_quatf(angle: self.angle + offset, axis: [0, 1, 0])
    }
    func blendDirection(previous: Direction) -> Direction {
        switch (self, previous) {
        case (.up, .right), (.right, .up): return .upright
        case (.right, .down), (.down, .right): return .downright
        case (.down, .left), (.left, .down): return .downleft
        case (.left, .up), (.up, .left): return .upleft
        default: return .down
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
typealias OrientedCoordinate = (coordinate: SIMD3<Float>, rotation: simd_quatf, position: Position)

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
            for direction in Direction.baseMoves {
                let position = Position(current.row + direction.offset.row, current.column + direction.offset.column)
                if position.row >= 0 && position.row < rows &&
                    position.column >= 0 && position.column < columns &&
                    !path.contains(where: { previous, _ in return (previous.row == position.row && previous.column == position.column) }) &&
                    [MapLegend.lowerPath, .higherPath, .goal, .zipLineOut].contains(MapLegend.allCases[matrix[position.row][position.column]]) {
                    if let lastMove = path.last, lastMove.direction != direction {
                        path[path.count - 1].direction = direction.blendDirection(previous: lastMove.direction)
                    }
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
                    case .higherPath, .higherPlacing: return 0.1
                    default: return 0.0
                    }
                }
                let z = (Float(column) - columnDistance) * 0.1
                let rotation = move.direction.rotation(offset: aditionalRotationOffset)
                return ([x, y, z], rotation, move.position)
            }
        }
    }
}
