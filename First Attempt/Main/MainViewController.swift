//
//  MainViewController.swift
//  First Attempt
//
//  Created by Daniel Aragon on 7/5/20.
//  Copyright © 2020 Daniel Aragon. All rights reserved.
//

import UIKit
import RealityKit
class Models {
    static let shared = Models()
//    let pathTemplate = try! Entity.load(named: "path")
//    let pathDownwardsTemplate = try! Entity.load(named: "path_downwards")
//    let pathUpwardsTemplate = try! Entity.load(named: "path_upwards")
//    let turretLvl1Template = try! Entity.load(named: "turret_lvl1")
//    let turretLvl2Template = try! Entity.load(named: "turret_lvl2")
//    let turretLvl3Template = try! Entity.load(named: "turret_lvl3")
//    let rocketLvl1Template = try! Entity.load(named: "rocket_lvl1")
//    let rocketLvl2Template = try! Entity.load(named: "rocket_lvl2")
//    let rocketLvl3Template = try! Entity.load(named: "rocket_lvl3")
//    let barracksLvl1Template = try! Entity.load(named: "barracks_lvl1")
//    let barracksLvl2Template = try! Entity.load(named: "barracks_lvl2")
//    let barracksLvl3Template = try! Entity.load(named: "barracks_lvl3")
//    let placingTemplate = try! Entity.load(named: "tower_place")
//    let flyingCreep = try! Entity.load(named: "flying_creep")
//    let heavyCreep = try! Entity.load(named: "heavy_creep")
//    let regularCreep = try! Entity.load(named: "regular_creep")
//    let smallCreep = try! Entity.load(named: "small_creep")
//    let runeTemplate = try! Entity.load(named: "here")
//    let portalTemplate = try! Entity.load(named: "gate")
//    let spawnTemplate = try! Entity.load(named: "spawn_port")
//    let bulletTemplate = try! Entity.load(named: "bullet")
    let fullHPBarTemplate = ModelEntity(mesh: .generateBox(size: SIMD3(x: 0.003, y: 0.0005, z: 0.0005), cornerRadius: 0.0002), materials: [SimpleMaterial(color: .green, isMetallic: false)])
    let halfHPBarTemplate = ModelEntity(mesh: .generateBox(size: SIMD3(x: 0.003, y: 0.0005, z: 0.0005), cornerRadius: 0.0002), materials: [SimpleMaterial(color: .yellow, isMetallic: false)])
    let lowHPBarTemplate = ModelEntity(mesh: .generateBox(size: SIMD3(x: 0.003, y: 0.0005, z: 0.0005), cornerRadius: 0.0002), materials: [SimpleMaterial(color: .red, isMetallic: false)])
    private init() {
        ///Map
//        let pathScale: Float = 0.000125
//        placingTemplate.setScale(SIMD3(repeating: pathScale), relativeTo: nil)
//        pathTemplate.setScale(SIMD3(repeating: pathScale), relativeTo: nil)
//        let rampScale: Float = 0.0125
//        pathDownwardsTemplate.setScale(SIMD3(repeating: rampScale), relativeTo: nil)
//        pathUpwardsTemplate.setScale(SIMD3(repeating: rampScale), relativeTo: nil)
//        spawnTemplate.setScale(SIMD3(repeating: 0.0002), relativeTo: nil)
//        portalTemplate.setScale(SIMD3(repeating: 0.0001), relativeTo: nil)
//        ///Runes
//        runeTemplate.setScale(SIMD3(repeating: 0.0003), relativeTo: nil)
//        ///Towers
//        let towerScale: Float = 0.00047
//        turretLvl1Template.setScale(SIMD3(repeating: towerScale), relativeTo: nil)
//        turretLvl2Template.setScale(SIMD3(repeating: towerScale), relativeTo: nil)
//        turretLvl3Template.setScale(SIMD3(repeating: towerScale), relativeTo: nil)
//        rocketLvl1Template.setScale(SIMD3(repeating: towerScale), relativeTo: nil)
//        rocketLvl2Template.setScale(SIMD3(repeating: towerScale), relativeTo: nil)
//        rocketLvl3Template.setScale(SIMD3(repeating: towerScale), relativeTo: nil)
//        barracksLvl1Template.setScale(SIMD3(repeating: towerScale), relativeTo: nil)
//        barracksLvl2Template.setScale(SIMD3(repeating: towerScale), relativeTo: nil)
//        barracksLvl3Template.setScale(SIMD3(repeating: towerScale), relativeTo: nil)
//
//        ///Creep
//        heavyCreep.setScale(SIMD3(repeating: 0.00002), relativeTo: nil)
//        regularCreep.setScale(SIMD3(repeating: 0.00001), relativeTo: nil)
//        smallCreep.setScale(SIMD3(repeating: 0.00001), relativeTo: nil)
//        flyingCreep.setScale(SIMD3(repeating: 0.000007), relativeTo: nil)
//        ///Bullet
//        bulletTemplate.setScale(SIMD3(repeating: 0.002), relativeTo: nil)
    }
}

class MainViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
         _ = Models.shared
        // Do any additional setup after loading the view.
    }
   

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
