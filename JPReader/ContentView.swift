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
    
    @State var ans = false
    
    @State private var baseURLString: String = "https://41j.com/jpexperiments/lazyjack/"
    
    @State private var bleTimer: DispatchSourceTimer? = nil
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 20) {
                
                HStack {
                    Button("Lazy Jack") {
                        baseURLString = "https://41j.com/jpexperiments/lazyjack/"
                        setupPlayer()
                        loadSubtitles()
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    
                    Button("Anathem") {
                        baseURLString = "https://41j.com/jpexperiments/anathem1/"
                        setupPlayer()
                        loadSubtitles()
                    }
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                
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
                                bleManager.connectPair(pair: pair)
                            } else {
                                print("No G1 glasses discovered yet.")
                            }
                        }
                        Text("Status: \(bleManager.connectionStatus)").foregroundColor(.white)
                    }
                    .onChange(of: bleManager.isFullyReady) { ready in
                        if ready {
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
                        if bright > 0 { bright -= 1 }
                        bleManager.brightness(bright)
                    }
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    
                    Button("Bright Up") {
                        if bright < 255 { bright += 1 }
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
        func fetch(_ filename: String, completion: @escaping ([Subtitle]) -> Void) {
            guard let url = URL(string: baseURLString + filename) else { return }
            URLSession.shared.dataTask(with: url) { data, _, _ in
                if let data = data, let srtString = String(data: data, encoding: .utf8) {
                    let parsed = parseSRT(srtString)
                    DispatchQueue.main.async {
                        completion(parsed)
                    }
                }
            }.resume()
        }
        
        fetch("tts_final_kanjionly.srt") { subtitles = $0 }
        fetch("tts_final_kanjionly_hira.srt") { subtitlesHiragana = $0 }
        fetch("tts_final_kanjionly_eigo.srt") { subtitlesEigo = $0 }
    }
    
    func setupPlayer() {
        guard let url = URL(string: baseURLString + "tts.mp3") else { return }
        
        player = AVPlayer(url: url)
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            currentTime = time.seconds
            if let item = player?.currentItem {
                duration = item.duration.seconds
            }
            updateSubtitle(at: currentTime)
        }
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
    
    func togglePlayPause() {
        guard let player = player else { return }
        isPlaying ? player.pause() : player.play()
        isPlaying.toggle()
    }
    
    func seekToTime(_ time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime)
    }
    
    func formatTime(_ time: Double) -> String {
        guard time.isFinite else { return "--:--" }
        let totalSeconds = Int(time)
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    func startBLETicker() {
        stopBLETicker()
        currentIndex = 0
        
        fetchCSV(from: baseURLString + "subtitles_unique.csv") { csvString in
            print("Fetching CSV",baseURLString + "subtitles_unqiue.csv")
            let shuffledCSV = randomizeCSVRows(csvString, hasHeader: true)
            renderer = KanjiCSVRenderer(csvString: shuffledCSV)
            startBLETimer()
        }
    }
    
    func fetchCSV(from urlString: String, completion: @escaping (String) -> Void) {
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data, let csvString = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                completion(csvString)
            }
        }.resume()
    }

    
    func startBLETimer() {
        guard let renderer = renderer else { return }
        let queue = DispatchQueue(label: "ble.timer.queue", qos: .background)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 10)
        timer.setEventHandler { [weak bleManager, weak renderer] in
            guard let bleManager = bleManager, let renderer = renderer else { return }
            if currentIndex >= renderer.entries.count {
                stopBLETicker()
                return
            }
            if ans { ans = false } else { ans = true }
            if let bmpData = renderer.generate1bppBMP(for: currentIndex, printanswer: ans) {
                bleManager.sendImage(bmpData, to: "Both")
            }
            if ans { currentIndex += 1 }
        }
        bleTimer = timer
        timer.resume()
    }
    
    func stopBLETicker() {
        bleTimer?.cancel()
        bleTimer = nil
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
    
    func randomizeCSVRows(_ csvString: String, hasHeader: Bool = true) -> String {
        var rows = csvString.components(separatedBy: .newlines).filter { !$0.isEmpty }
        
        guard !rows.isEmpty else { return csvString }
        
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
    
    func observeAppLifecycle() {
        NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { _ in stopBLETicker() }
    }
}
