//
//  DefensorCollectionViewCell.swift
//  First Attempt
//
//  Created by Oscar Jonaiker Rojas Dueñas on 6/1/20.
//  Copyright © 2020 Daniel Aragon. All rights reserved.
//

import Foundation
import UIKit

class Defensor
{
//    var name: String = ""
    var defensorImage: UIImage
    
    init(name: String, defensorImage: UIImage) {
        self.defensorImage = defensorImage
//        self.name = name
    }
    static func getDefensors() -> [Defensor]
    {
        return [
            Defensor(name: "Turret", defensorImage: #imageLiteral(resourceName: "turret")),
            Defensor(name: "Rocket", defensorImage: #imageLiteral(resourceName: "missile-swarm")),
            Defensor(name: "Fighters", defensorImage: #imageLiteral(resourceName: "cryo-chamber")),
        ]
    }
}
class DefensorCollectionViewCell: UICollectionViewCell
{
    @IBOutlet weak var defensorImageView: UIImageView!
//    @IBOutlet weak var defensorTitleLabel: UILabel!

    var defensor: Defensor! {
        didSet{
            self.updateUI()
        }
    }
    func updateUI() {
        if let defensor = defensor {
            defensorImageView.image = defensor.defensorImage
//            defensorTitleLabel.text = defensor.name
            
        } else {
            defensorImageView.image = nil
//            defensorTitleLabel.text = nil
        }
    
        
        defensorImageView.layer.cornerRadius = 30.0
        defensorImageView.layer.masksToBounds = true
    }
}
