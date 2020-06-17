//
//  ActionStripCollectionViewCell.swift
//  First Attempt
//
//  Created by Oscar Jonaiker Rojas Dueñas on 6/1/20.
//  Copyright © 2020 Daniel Aragon. All rights reserved.
//

import Foundation
import UIKit

class ActionStripCollectionViewCell: UICollectionViewCell
{
    @IBOutlet weak var iconImageView: UIImageView!

    var iconImage: UIImage! {
        didSet{
            self.updateUI()
        }
    }
    func updateUI() {
        iconImageView.image = iconImage
        iconImageView.layer.cornerRadius = 30.0
        iconImageView.layer.masksToBounds = true
    }
}
