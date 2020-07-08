//
//  MissionsViewController.swift
//  First Attempt
//
//  Created by Daniel Aragon on 7/5/20.
//  Copyright © 2020 Daniel Aragon. All rights reserved.
//

import UIKit

class MissionsViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        let destination = segue.destination as? GameViewController

        if segue.identifier == "0" {
            destination?.mission = 0
        } else {
            destination?.mission = 1
        }
    }
}
