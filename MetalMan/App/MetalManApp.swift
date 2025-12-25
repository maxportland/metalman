//
//  MetalManApp.swift
//  MetalMan
//
//  Created by Max Davis on 12/23/25.
//

import SwiftUI

@main
struct MetalManApp: App {
    init() {
        // Debug: Print available Font Awesome fonts
        FontAwesomeChecker.printAvailableFonts()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
