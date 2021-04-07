//
//  Collection+Array.swift
//  LibreDirectClient
//
//  Created by Julian Groen on 13/05/2020.
//  Copyright © 2020 Julian Groen. All rights reserved.
//

import Foundation

extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
