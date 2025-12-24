//
//  ContentView.swift
//  MetalMan
//
//  Created by Max Davis on 12/23/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            MetalGameContainer()
        }
        .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}

