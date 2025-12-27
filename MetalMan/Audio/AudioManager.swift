import AVFoundation

// Disable verbose logging for audio
private let audioDebugLogging = false
private func debugLog(_ message: @autoclosure () -> String) {
    if audioDebugLogging {
        print(message())
    }
}

/// Manages audio playback for the game
final class AudioManager {
    static let shared = AudioManager()
    
    private var footstepsPlayer: AVAudioPlayer?
    private var isFootstepsPlaying = false
    
    private var swordSwingPlayer: AVAudioPlayer?
    private var metalHitPlayer: AVAudioPlayer?
    private var treasureChestOpenPlayer: AVAudioPlayer?
    private var levelUpPlayer: AVAudioPlayer?
    private var hurtPlayers: [AVAudioPlayer] = []
    private var diePlayer: AVAudioPlayer?
    private var tickPlayer: AVAudioPlayer?
    private var spottedPlayer: AVAudioPlayer?
    private var spottedStopTimer: Timer?
    private var playerDiePlayer: AVAudioPlayer?
    private var deathLaughPlayer: AVAudioPlayer?
    private var lootMenuPlayer: AVAudioPlayer?
    private var backgroundMusicPlayer: AVAudioPlayer?
    private var drinkPotionPlayer: AVAudioPlayer?
    
    private init() {
        setupFootsteps()
        setupSwordSwing()
        setupMetalHit()
        setupTreasureChestOpen()
        setupLevelUp()
        setupHurtSounds()
        setupDie()
        setupTick()
        setupSpotted()
        setupPlayerDeath()
        setupLootMenu()
        setupBackgroundMusic()
        setupDrinkPotion()
    }
    
    private func setupFootsteps() {
        if let url = Bundle.main.url(forResource: "footsteps", withExtension: "wav", subdirectory: "Sounds") {
            setupFootstepsPlayer(with: url)
        } else if let url = Bundle.main.url(forResource: "footsteps", withExtension: "wav") {
            setupFootstepsPlayer(with: url)
        } else {
            debugLog("[Audio] Could not find footsteps.wav in bundle")
        }
    }
    
    private func setupFootstepsPlayer(with url: URL) {
        do {
            footstepsPlayer = try AVAudioPlayer(contentsOf: url)
            footstepsPlayer?.numberOfLoops = -1  // Loop indefinitely
            footstepsPlayer?.volume = 0.4  // Not too loud
            footstepsPlayer?.prepareToPlay()
            debugLog("[Audio] Footsteps audio loaded successfully")
        } catch {
            debugLog("[Audio] Failed to load footsteps audio: \(error)")
        }
    }
    
    private func setupSwordSwing() {
        if let url = Bundle.main.url(forResource: "sword-swing", withExtension: "wav", subdirectory: "Sounds") {
            setupSwordSwingPlayer(with: url)
        } else if let url = Bundle.main.url(forResource: "sword-swing", withExtension: "wav") {
            setupSwordSwingPlayer(with: url)
        } else {
            debugLog("[Audio] Could not find sword-swing.wav in bundle")
        }
    }
    
    private func setupSwordSwingPlayer(with url: URL) {
        do {
            swordSwingPlayer = try AVAudioPlayer(contentsOf: url)
            swordSwingPlayer?.numberOfLoops = 0  // Play once
            swordSwingPlayer?.volume = 0.6
            swordSwingPlayer?.prepareToPlay()
            debugLog("[Audio] Sword swing audio loaded successfully")
        } catch {
            debugLog("[Audio] Failed to load sword swing audio: \(error)")
        }
    }
    
    private func setupMetalHit() {
        if let url = Bundle.main.url(forResource: "metal-hit", withExtension: "wav", subdirectory: "Sounds") {
            setupMetalHitPlayer(with: url)
        } else if let url = Bundle.main.url(forResource: "metal-hit", withExtension: "wav") {
            setupMetalHitPlayer(with: url)
        } else {
            debugLog("[Audio] Could not find metal-hit.wav in bundle")
        }
    }
    
    private func setupMetalHitPlayer(with url: URL) {
        do {
            metalHitPlayer = try AVAudioPlayer(contentsOf: url)
            metalHitPlayer?.numberOfLoops = 0  // Play once
            metalHitPlayer?.volume = 0.7
            metalHitPlayer?.prepareToPlay()
            debugLog("[Audio] Metal hit audio loaded successfully")
        } catch {
            debugLog("[Audio] Failed to load metal hit audio: \(error)")
        }
    }
    
    private func setupTreasureChestOpen() {
        if let url = Bundle.main.url(forResource: "treasure-chest-open", withExtension: "wav", subdirectory: "Sounds") {
            setupTreasureChestOpenPlayer(with: url)
        } else if let url = Bundle.main.url(forResource: "treasure-chest-open", withExtension: "wav") {
            setupTreasureChestOpenPlayer(with: url)
        } else {
            debugLog("[Audio] Could not find treasure-chest-open.wav in bundle")
        }
    }
    
    private func setupTreasureChestOpenPlayer(with url: URL) {
        do {
            treasureChestOpenPlayer = try AVAudioPlayer(contentsOf: url)
            treasureChestOpenPlayer?.numberOfLoops = 0
            treasureChestOpenPlayer?.volume = 0.6
            treasureChestOpenPlayer?.prepareToPlay()
            debugLog("[Audio] Treasure chest open audio loaded successfully")
        } catch {
            debugLog("[Audio] Failed to load treasure chest open audio: \(error)")
        }
    }
    
    private func setupLevelUp() {
        if let url = Bundle.main.url(forResource: "level-up", withExtension: "wav", subdirectory: "Sounds") {
            setupLevelUpPlayer(with: url)
        } else if let url = Bundle.main.url(forResource: "level-up", withExtension: "wav") {
            setupLevelUpPlayer(with: url)
        } else {
            debugLog("[Audio] Could not find level-up.wav in bundle")
        }
    }
    
    private func setupLevelUpPlayer(with url: URL) {
        do {
            levelUpPlayer = try AVAudioPlayer(contentsOf: url)
            levelUpPlayer?.numberOfLoops = 0
            levelUpPlayer?.volume = 0.8
            levelUpPlayer?.prepareToPlay()
            debugLog("[Audio] Level up audio loaded successfully")
        } catch {
            debugLog("[Audio] Failed to load level up audio: \(error)")
        }
    }
    
    private func setupHurtSounds() {
        for i in 1...3 {
            let fileName = "hurt\(i)"
            if let url = Bundle.main.url(forResource: fileName, withExtension: "wav", subdirectory: "Sounds") {
                setupHurtPlayer(with: url)
            } else if let url = Bundle.main.url(forResource: fileName, withExtension: "wav") {
                setupHurtPlayer(with: url)
            } else {
                debugLog("[Audio] Could not find \(fileName).wav in bundle")
            }
        }
        debugLog("[Audio] Loaded \(hurtPlayers.count) hurt sounds")
    }
    
    private func setupHurtPlayer(with url: URL) {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = 0
            player.volume = 0.7
            player.prepareToPlay()
            hurtPlayers.append(player)
        } catch {
            debugLog("[Audio] Failed to load hurt audio: \(error)")
        }
    }
    
    private func setupDie() {
        if let url = Bundle.main.url(forResource: "die", withExtension: "wav", subdirectory: "Sounds") {
            setupDiePlayer(with: url)
        } else if let url = Bundle.main.url(forResource: "die", withExtension: "wav") {
            setupDiePlayer(with: url)
        } else {
            debugLog("[Audio] Could not find die.wav in bundle")
        }
    }
    
    private func setupDiePlayer(with url: URL) {
        do {
            diePlayer = try AVAudioPlayer(contentsOf: url)
            diePlayer?.numberOfLoops = 0
            diePlayer?.volume = 0.7
            diePlayer?.prepareToPlay()
            debugLog("[Audio] Die audio loaded successfully")
        } catch {
            debugLog("[Audio] Failed to load die audio: \(error)")
        }
    }
    
    /// Start playing footsteps sound (if not already playing)
    func startFootsteps() {
        guard !isFootstepsPlaying else { return }
        footstepsPlayer?.play()
        isFootstepsPlaying = true
    }
    
    /// Stop playing footsteps sound
    func stopFootsteps() {
        guard isFootstepsPlaying else { return }
        footstepsPlayer?.pause()
        isFootstepsPlaying = false
    }
    
    /// Update footsteps based on movement state
    func updateFootsteps(isWalking: Bool) {
        if isWalking {
            startFootsteps()
        } else {
            stopFootsteps()
        }
    }
    
    /// Play sword swing sound effect
    func playSwordSwing() {
        swordSwingPlayer?.currentTime = 0  // Reset to start
        swordSwingPlayer?.play()
    }
    
    /// Play metal hit sound effect (when attack connects)
    func playMetalHit() {
        metalHitPlayer?.currentTime = 0  // Reset to start
        metalHitPlayer?.play()
    }
    
    func playTreasureChestOpen() {
        treasureChestOpenPlayer?.currentTime = 0
        treasureChestOpenPlayer?.play()
    }
    
    func playLevelUp() {
        levelUpPlayer?.currentTime = 0
        levelUpPlayer?.play()
    }
    
    /// Play a random hurt sound effect
    func playHurt() {
        guard !hurtPlayers.isEmpty else { return }
        let randomIndex = Int.random(in: 0..<hurtPlayers.count)
        let player = hurtPlayers[randomIndex]
        player.currentTime = 0
        player.play()
    }
    
    /// Play enemy death sound effect
    func playDie() {
        diePlayer?.currentTime = 0
        diePlayer?.play()
    }
    
    private func setupTick() {
        if let url = Bundle.main.url(forResource: "tick", withExtension: "wav", subdirectory: "Sounds") {
            setupTickPlayer(with: url)
        } else if let url = Bundle.main.url(forResource: "tick", withExtension: "wav") {
            setupTickPlayer(with: url)
        } else {
            debugLog("[Audio] Could not find tick.wav in bundle")
        }
    }
    
    private func setupTickPlayer(with url: URL) {
        do {
            tickPlayer = try AVAudioPlayer(contentsOf: url)
            tickPlayer?.numberOfLoops = 0
            tickPlayer?.volume = 0.5
            tickPlayer?.prepareToPlay()
            debugLog("[Audio] Tick audio loaded successfully")
        } catch {
            debugLog("[Audio] Failed to load tick audio: \(error)")
        }
    }
    
    /// Play UI tick/click sound effect
    func playTick() {
        tickPlayer?.currentTime = 0
        tickPlayer?.play()
    }
    
    private func setupSpotted() {
        if let url = Bundle.main.url(forResource: "spotted", withExtension: "wav", subdirectory: "Sounds") {
            setupSpottedPlayer(with: url)
        } else if let url = Bundle.main.url(forResource: "spotted", withExtension: "wav") {
            setupSpottedPlayer(with: url)
        } else {
            debugLog("[Audio] Could not find spotted.wav in bundle")
        }
    }
    
    private func setupSpottedPlayer(with url: URL) {
        do {
            spottedPlayer = try AVAudioPlayer(contentsOf: url)
            spottedPlayer?.numberOfLoops = 0
            spottedPlayer?.volume = 0.6
            spottedPlayer?.prepareToPlay()
            debugLog("[Audio] Spotted audio loaded successfully")
        } catch {
            debugLog("[Audio] Failed to load spotted audio: \(error)")
        }
    }
    
    /// Play spotted sound effect (first 500ms only)
    func playSpotted() {
        // Cancel any existing timer
        spottedStopTimer?.invalidate()
        
        spottedPlayer?.currentTime = 0
        spottedPlayer?.play()
        
        // Stop after 500ms
        spottedStopTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.spottedPlayer?.stop()
        }
    }
    
    private func setupPlayerDeath() {
        // Setup player-die.wav
        if let url = Bundle.main.url(forResource: "player-die", withExtension: "wav", subdirectory: "Sounds") {
            setupPlayerDiePlayer(with: url)
        } else if let url = Bundle.main.url(forResource: "player-die", withExtension: "wav") {
            setupPlayerDiePlayer(with: url)
        } else {
            debugLog("[Audio] Could not find player-die.wav in bundle")
        }
        
        // Setup death-laugh.wav
        if let url = Bundle.main.url(forResource: "death-laugh", withExtension: "wav", subdirectory: "Sounds") {
            setupDeathLaughPlayer(with: url)
        } else if let url = Bundle.main.url(forResource: "death-laugh", withExtension: "wav") {
            setupDeathLaughPlayer(with: url)
        } else {
            debugLog("[Audio] Could not find death-laugh.wav in bundle")
        }
    }
    
    private func setupPlayerDiePlayer(with url: URL) {
        do {
            playerDiePlayer = try AVAudioPlayer(contentsOf: url)
            playerDiePlayer?.numberOfLoops = 0
            playerDiePlayer?.volume = 0.8
            playerDiePlayer?.prepareToPlay()
            debugLog("[Audio] Player die audio loaded successfully")
        } catch {
            debugLog("[Audio] Failed to load player die audio: \(error)")
        }
    }
    
    private func setupDeathLaughPlayer(with url: URL) {
        do {
            deathLaughPlayer = try AVAudioPlayer(contentsOf: url)
            deathLaughPlayer?.numberOfLoops = 0
            deathLaughPlayer?.volume = 0.7
            deathLaughPlayer?.prepareToPlay()
            debugLog("[Audio] Death laugh audio loaded successfully")
        } catch {
            debugLog("[Audio] Failed to load death laugh audio: \(error)")
        }
    }
    
    /// Play player death sounds (player-die.wav followed by death-laugh.wav)
    func playPlayerDeath() {
        // Stop footsteps if playing
        stopFootsteps()
        
        playerDiePlayer?.currentTime = 0
        playerDiePlayer?.play()
        
        // Get duration of player-die sound and schedule death-laugh after it
        let delay = playerDiePlayer?.duration ?? 1.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.deathLaughPlayer?.currentTime = 0
            self?.deathLaughPlayer?.play()
        }
    }
    
    private func setupLootMenu() {
        if let url = Bundle.main.url(forResource: "loot-menu", withExtension: "wav", subdirectory: "Sounds") {
            setupLootMenuPlayer(with: url)
        } else if let url = Bundle.main.url(forResource: "loot-menu", withExtension: "wav") {
            setupLootMenuPlayer(with: url)
        } else {
            debugLog("[Audio] Could not find loot-menu.wav in bundle")
        }
    }
    
    private func setupLootMenuPlayer(with url: URL) {
        do {
            lootMenuPlayer = try AVAudioPlayer(contentsOf: url)
            lootMenuPlayer?.numberOfLoops = 0
            lootMenuPlayer?.volume = 0.5
            lootMenuPlayer?.prepareToPlay()
            debugLog("[Audio] Loot menu audio loaded successfully")
        } catch {
            debugLog("[Audio] Failed to load loot menu audio: \(error)")
        }
    }
    
    /// Play loot menu sound effect
    func playLootMenu() {
        lootMenuPlayer?.currentTime = 0
        lootMenuPlayer?.play()
    }
    
    private func setupBackgroundMusic() {
        if let url = Bundle.main.url(forResource: "game-music1", withExtension: "mp3", subdirectory: "Sounds") {
            setupBackgroundMusicPlayer(with: url)
        } else if let url = Bundle.main.url(forResource: "game-music1", withExtension: "mp3") {
            setupBackgroundMusicPlayer(with: url)
        } else {
            debugLog("[Audio] Could not find game-music1.mp3 in bundle")
        }
    }
    
    private func setupBackgroundMusicPlayer(with url: URL) {
        do {
            backgroundMusicPlayer = try AVAudioPlayer(contentsOf: url)
            backgroundMusicPlayer?.numberOfLoops = -1  // Loop indefinitely
            backgroundMusicPlayer?.volume = 0.15  // Low volume
            backgroundMusicPlayer?.prepareToPlay()
            backgroundMusicPlayer?.play()  // Start playing immediately
            debugLog("[Audio] Background music loaded and started")
        } catch {
            debugLog("[Audio] Failed to load background music: \(error)")
        }
    }
    
    /// Start background music
    func startBackgroundMusic() {
        if !(backgroundMusicPlayer?.isPlaying ?? false) {
            backgroundMusicPlayer?.play()
        }
    }
    
    /// Stop background music
    func stopBackgroundMusic() {
        backgroundMusicPlayer?.stop()
    }
    
    /// Set background music volume (0.0 to 1.0)
    func setBackgroundMusicVolume(_ volume: Float) {
        backgroundMusicPlayer?.volume = volume
    }
    
    private func setupDrinkPotion() {
        if let url = Bundle.main.url(forResource: "drink-potion", withExtension: "wav", subdirectory: "Sounds") {
            setupDrinkPotionPlayer(with: url)
        } else if let url = Bundle.main.url(forResource: "drink-potion", withExtension: "wav") {
            setupDrinkPotionPlayer(with: url)
        } else {
            debugLog("[Audio] Could not find drink-potion.wav in bundle")
        }
    }
    
    private func setupDrinkPotionPlayer(with url: URL) {
        do {
            drinkPotionPlayer = try AVAudioPlayer(contentsOf: url)
            drinkPotionPlayer?.numberOfLoops = 0
            drinkPotionPlayer?.volume = 0.6
            drinkPotionPlayer?.prepareToPlay()
            debugLog("[Audio] Drink potion audio loaded successfully")
        } catch {
            debugLog("[Audio] Failed to load drink potion audio: \(error)")
        }
    }
    
    /// Play drink potion sound effect
    func playDrinkPotion() {
        drinkPotionPlayer?.currentTime = 0
        drinkPotionPlayer?.play()
    }
}

