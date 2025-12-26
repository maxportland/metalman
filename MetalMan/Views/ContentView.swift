//
//  ContentView.swift
//  MetalMan
//
//  Created by Max Davis on 12/23/25.
//

import SwiftUI

struct ContentView: View {
    @State private var gameState: GameState = .mainMenu
    
    var body: some View {
        ZStack {
            switch gameState {
            case .mainMenu:
                MainMenuView(gameState: $gameState)
                    .transition(.opacity)
                
            case .playing(let saveData):
                MetalGameContainer(
                    initialSaveData: saveData,
                    onReturnToMainMenu: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            gameState = .mainMenu
                        }
                    }
                )
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.3), value: gameState)
    }
}

#Preview {
    ContentView()
}
