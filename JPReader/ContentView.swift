import SwiftUI
import AVFoundation
import G1BLEManager

struct ContentView: View {
    
    @StateObject var bleManager = G1BLEManager()
    
    @State private var renderedImage: UIImage?
    let renderer2 = SubtitleImageRenderer()
    
    @State private var player: AVPlayer?
    @State private var duration: Double = 0
    @State private var currentTime: Double = 0
    @State private var isPlaying = false
    
    @State private var bright: UInt8 = 15
    
    @State private var subtitles: [Subtitle] = []
    @State private var displayedSubtitles: [Subtitle] = Array(repeating: Subtitle(index: 0, start: 0, end: 0, text: ""), count: 5)
    @State private var subtitleCounter: Int = 0
    
    @State private var subtitlesHiragana: [Subtitle] = []
    @State private var displayedHiragana: [Subtitle] = Array(repeating: Subtitle(index: 0, start: 0, end: 0, text: ""), count: 5)
    @State private var counterHiragana: Int = 0

    @State private var subtitlesEigo: [Subtitle] = []
    @State private var displayedEigo: [Subtitle] = Array(repeating: Subtitle(index: 0, start: 0, end: 0, text: ""), count: 5)
    @State private var counterEigo: Int = 0

    @State private var currentIndex = 0
    @State private var renderer: KanjiCSVRenderer? = nil
    
    let audioURL = URL("https://41j.com/jpexperiments/lazyjack/tts.mp3")!
    
    // NEW: background-safe timer
    @State private var bleTimer: DispatchSourceTimer? = nil
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 20) {
                
                VStack(spacing: 10) {
                    if duration > 0 {
                        Slider(value: $currentTime, in: 0...duration, onEditingChanged: { editing in
                            if !editing {
                                seekToTime(currentTime)
                            }
                        })
                    } else {
                        Text("Loading audio...")
                            .foregroundColor(.gray)
                    }
                    
                    Text("\(formatTime(currentTime)) / \(formatTime(duration))").foregroundColor(.white)
                    
                    Button(isPlaying ? "Pause" : "Play") {
                        togglePlayPause()
                    }
                    .padding()
                    .foregroundColor(.white)
                    .background(Color.gray.opacity(0.2))
                    .clipShape(Capsule())
                }
                .padding()
                .onAppear {
                    configureAudioSession()
                    setupPlayer()
                    loadSubtitles()
                    observeAppLifecycle()
                }
                .onDisappear {
                    stopBLETicker()
                }
                
                VStack(spacing: 8) {
                    subtitleRow(displayedSubtitles)
                    subtitleRow(displayedHiragana)
                    subtitleRow(displayedEigo)
                }
                
                HStack(spacing: 20) {
                    VStack {
                        Button("Connect Glasses") {
                            if let (key, pair) = bleManager.discoveredPairs.first(where: { $0.value.left != nil || $0.value.right != nil }) {
                                print("Connecting to \(key)")
                                bleManager.connectPair(pair: pair)
                            } else {
                                print("No G1 glasses discovered yet.")
                            }
                        }
                        Text("Status: \(bleManager.connectionStatus)").foregroundColor(.white)
                    }
                    .onChange(of: bleManager.isFullyReady) { ready in
                        if ready {
                            print("BLE ready, clearing previous state…")
                            bleManager.clear()
                        }
                    }
                    
                    Button("Send BMP") {
                        startBLETicker()
                    }
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    
                    Button("Bright Down") {
                        if(bright > 0) {
                            bright-=1
                        }
                        bleManager.brightness(bright)
                    }
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    
                    Button("Bright Up") {
                        if(bright < 255) {
                            bright+=1
                        }
                        bleManager.brightness(bright)
                    }
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)

                    
                }
            }
        }
    }
    
    @ViewBuilder
    func subtitleRow(_ subs: [Subtitle]) -> some View {
        HStack {
            ForEach(0..<5, id: \.self) { i in
                let sub = subs[i]
                Text(sub.text)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .multilineTextAlignment(.center)
                    .overlay(
                        Rectangle()
                            .frame(height: 2)
                            .foregroundColor(isActive(sub) ? .red : .clear),
                        alignment: .bottom
                    )
            }
        }
        .frame(height: 40)
    }
    
    func loadSubtitles() {
        let base = "https://41j.com/jpexperiments/lazyjack/"
        
        func fetch(_ filename: String, completion: @escaping ([Subtitle]) -> Void) {
            guard let url = URL(string: base + filename) else { return }
            URLSession.shared.dataTask(with: url) { data, _, _ in
                if let data = data, let srtString = String(data: data, encoding: .utf8) {
                    let parsed = parseSRT(srtString)
                    DispatchQueue.main.async {
                        completion(parsed)
                    }
                }
            }.resume()
        }
        
        fetch("tts_fixed_aligned_onlykanji.srt") { subtitles = $0 }
        fetch("tts_fixed_aligned_onlykanji_hira.srt") { subtitlesHiragana = $0 }
        fetch("tts_fixed_aligned_onlykanji_eigo.srt") { subtitlesEigo = $0 }
    }
    
    func updateSubtitle(at time: TimeInterval) {
        guard let currentIndex = subtitles.firstIndex(where: { time >= $0.start && time <= $0.end }) else {
            return
        }
        
        let active = subtitles[currentIndex]
        
        if displayedSubtitles.contains(where: { $0.index == active.index }) {
            return
        }
        
        displayedSubtitles[subtitleCounter % 5] = active
        subtitleCounter += 1
        
        if subtitlesHiragana.indices.contains(currentIndex) {
            let h = subtitlesHiragana[currentIndex]
            displayedHiragana[counterHiragana % 5] = h
            counterHiragana += 1
        }
        
        if subtitlesEigo.indices.contains(currentIndex) {
            let e = subtitlesEigo[currentIndex]
            displayedEigo[counterEigo % 5] = e
            counterEigo += 1
        }
        
        if bleManager.isFullyReady {
            let lines = zip(zip(displayedSubtitles, displayedHiragana), displayedEigo).map {
                "\($0.0.0.text):\($0.0.1.text):\($0.1.text)"
            }
            let result = lines.joined(separator: "\n")
            print("sending: \(result)")
            bleManager.sendText(text: result, counter: 1)
        }
    }
    
    func isActive(_ sub: Subtitle) -> Bool {
        currentTime >= sub.start && currentTime <= sub.end
    }
    
    func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }
    
    func setupPlayer() {
        print("Attempting to load audio from:", audioURL)
        
        player = AVPlayer(url: audioURL)
        
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            currentTime = time.seconds
            if let item = player?.currentItem {
                duration = item.duration.seconds
            }
            updateSubtitle(at: currentTime)
        }
    }
    
    func togglePlayPause() {
        guard let player = player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }
    
    func seekToTime(_ time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime)
    }
    
    func formatTime(_ time: Double) -> String {
        guard time.isFinite else { return "--:--" }
        
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%01d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    
    /// Randomizes the rows of a CSV string.
    /// - Parameters:
    ///   - csvString: The input CSV string.
    ///   - hasHeader: Whether to preserve the first line as a header.
    /// - Returns: A new CSV string with rows shuffled.
    func randomizeCSVRows(_ csvString: String, hasHeader: Bool = true) -> String {
        var rows = csvString.components(separatedBy: .newlines).filter { !$0.isEmpty }
        
        guard !rows.isEmpty else {
            print("CSV appears to be empty.")
            return csvString
        }
        
        if hasHeader {
            let header = rows.first!
            var dataRows = Array(rows.dropFirst())
            dataRows.shuffle()
            return ([header] + dataRows).joined(separator: "\n")
        } else {
            rows.shuffle()
            return rows.joined(separator: "\n")
        }
    }

    
    // MARK: - BLE Background Timer
    
    func startBLETicker() {
        stopBLETicker()
        currentIndex = 0
        
        if renderer == nil {
            guard let url = Bundle.main.url(forResource: "words", withExtension: "csv"),
                  let csvString = try? String(contentsOf: url, encoding: .utf8) else {
                print("Failed to load words.csv")
                return
            }
            let shuffledCSV = randomizeCSVRows(csvString, hasHeader: true)
            renderer = KanjiCSVRenderer(csvString: shuffledCSV)
        }
        
        let queue = DispatchQueue(label: "ble.timer.queue", qos: .background)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 7.0)
        timer.setEventHandler { [weak bleManager, weak renderer] in
            guard let bleManager = bleManager, let renderer = renderer else { return }
            if currentIndex >= renderer.entries.count {
                print("Finished sending all BMPs.")
                stopBLETicker()
                return
            }
            print("Sending BMP \(currentIndex)/\(renderer.entries.count)")
            if let bmpData = renderer.generate1bppBMP(for: currentIndex) {
                bleManager.sendImage(bmpData, to: "Both")
            }
            currentIndex += 1
        }
        bleTimer = timer
        timer.resume()
    }
    
    func stopBLETicker() {
        bleTimer?.cancel()
        bleTimer = nil
    }
    
    // MARK: - App Lifecycle
    
    func observeAppLifecycle() {
        NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            stopBLETicker()
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            print("App entered background, BLE timer should continue.")
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            print("App entered foreground.")
        }
    }
}
