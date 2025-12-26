//
//  MainMenuView.swift
//  MetalMan
//
//  Main menu shown on app launch
//

import SwiftUI

struct MainMenuView: View {
    @Binding var gameState: GameState
    @State private var saves: [SaveGameData] = []
    @State private var showLoadMenu = false
    @State private var showDeleteConfirmation = false
    @State private var saveToDelete: SaveGameData?
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.1, green: 0.05, blue: 0.15),
                    Color(red: 0.05, green: 0.1, blue: 0.2),
                    Color.black
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // Decorative elements
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Circle()
                        .fill(Color.purple.opacity(0.1))
                        .frame(width: 400, height: 400)
                        .blur(radius: 100)
                        .offset(x: 150, y: 100)
                }
            }
            .ignoresSafeArea()
            
            if showLoadMenu {
                loadMenuView
            } else {
                mainMenuContent
            }
        }
        .onAppear {
            refreshSaves()
        }
    }
    
    private var mainMenuContent: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Title
            VStack(spacing: 8) {
                Text("METAL MAN")
                    .font(.system(size: 72, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .gray],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .cyan.opacity(0.5), radius: 20)
                
                Text("A Metal RPG Adventure")
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .foregroundColor(.cyan.opacity(0.7))
            }
            
            Spacer()
            
            // Menu buttons
            VStack(spacing: 20) {
                MenuButton(title: "New Game", icon: "play.fill", color: .green) {
                    AudioManager.shared.playTick()
                    gameState = .playing(saveData: nil)
                }
                
                MenuButton(title: "Load Game", icon: "folder.fill", color: .blue, disabled: saves.isEmpty) {
                    AudioManager.shared.playTick()
                    showLoadMenu = true
                }
                
                MenuButton(title: "Quit", icon: "xmark.circle.fill", color: .red) {
                    AudioManager.shared.playTick()
                    NSApplication.shared.terminate(nil)
                }
            }
            .frame(width: 300)
            
            Spacer()
            
            // Version info
            Text("v1.0 • Built with Metal & SwiftUI")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.gray.opacity(0.5))
                .padding(.bottom, 30)
        }
    }
    
    private var loadMenuView: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Button(action: {
                    AudioManager.shared.playTick()
                    showLoadMenu = false
                }) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text("Load Game")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Spacer for centering
                Text("Back")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.clear)
            }
            .padding(.horizontal, 40)
            .padding(.top, 40)
            
            // Save list
            if saves.isEmpty {
                Spacer()
                Text("No saved games found")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.gray)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(saves) { save in
                            SaveSlotView(save: save) {
                                // Load
                                AudioManager.shared.playTick()
                                gameState = .playing(saveData: save)
                            } onDelete: {
                                // Delete
                                saveToDelete = save
                                showDeleteConfirmation = true
                            }
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 20)
                }
            }
        }
        .alert("Delete Save?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let save = saveToDelete {
                    SaveGameManager.shared.deleteSave(id: save.id)
                    refreshSaves()
                }
            }
        } message: {
            if let save = saveToDelete {
                Text("Are you sure you want to delete '\(save.saveName)'? This cannot be undone.")
            }
        }
    }
    
    private func refreshSaves() {
        saves = SaveGameManager.shared.getAllSaves()
    }
}

// MARK: - Menu Button

struct MenuButton: View {
    let title: String
    let icon: String
    let color: Color
    var disabled: Bool = false
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                
                Spacer()
            }
            .foregroundColor(disabled ? .gray : .white)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(disabled ? Color.gray.opacity(0.2) : color.opacity(isHovered ? 0.4 : 0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(disabled ? Color.gray.opacity(0.3) : color.opacity(0.6), lineWidth: 2)
                    )
            )
            .scaleEffect(isHovered && !disabled ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Save Slot View

struct SaveSlotView: View {
    let save: SaveGameData
    let onLoad: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Save info
            VStack(alignment: .leading, spacing: 4) {
                Text(save.saveName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                
                Text(save.formattedTimestamp)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.cyan.opacity(0.8))
                
                Text(save.displaySummary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 12) {
                Button(action: onLoad) {
                    Text("Load")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.green.opacity(0.6))
                        )
                }
                .buttonStyle(.plain)
                
                Button(action: onDelete) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.red)
                        .padding(8)
                        .background(
                            Circle()
                                .fill(Color.red.opacity(0.2))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(isHovered ? 0.1 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Game State

enum GameState: Equatable {
    case mainMenu
    case playing(saveData: SaveGameData?)
    
    static func == (lhs: GameState, rhs: GameState) -> Bool {
        switch (lhs, rhs) {
        case (.mainMenu, .mainMenu):
            return true
        case (.playing(let lhsSave), .playing(let rhsSave)):
            return lhsSave?.id == rhsSave?.id
        default:
            return false
        }
    }
}

#Preview {
    MainMenuView(gameState: .constant(.mainMenu))
}

