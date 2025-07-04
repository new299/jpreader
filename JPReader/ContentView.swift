import SwiftUI
import AVFoundation



struct ContentView: View {
    
    @StateObject var bleManager = G1BLEManager()
    
    @State private var renderedImage: UIImage?
    let renderer = SubtitleImageRenderer()
    
    @State private var player: AVPlayer?
    @State private var duration: Double = 0
    @State private var currentTime: Double = 0
    @State private var isPlaying = false
    
    // Subtitle related
    @State private var subtitles: [Subtitle] = []
    @State private var displayedSubtitles: [Subtitle] = Array(repeating: Subtitle(index: 0, start: 0, end: 0, text: ""), count: 5)
    @State private var subtitleCounter: Int = 0
    
    @State private var subtitlesHiragana: [Subtitle] = []
    @State private var displayedHiragana: [Subtitle] = Array(repeating: Subtitle(index: 0, start: 0, end: 0, text: ""), count: 5)
    @State private var counterHiragana: Int = 0

    @State private var subtitlesEigo: [Subtitle] = []
    @State private var displayedEigo: [Subtitle] = Array(repeating: Subtitle(index: 0, start: 0, end: 0, text: ""), count: 5)
    @State private var counterEigo: Int = 0

    

    // Use local or remote MP3 URL
    let audioURL = URL(string: "https://41j.com/anathemhtml/static/Anathem_jp_2.mp3")!

    var body: some View {
        
        ZStack {
            Color.black.ignoresSafeArea() // <- sets entire view background

            VStack(spacing: 20) {
                // All your content

        
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

        }
        VStack(spacing: 8) {
            subtitleRow(displayedSubtitles)
            subtitleRow(displayedHiragana)
            subtitleRow(displayedEigo)
        }
            }
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
                Text("Status: \(bleManager.connectionStatus)")
                
               
            }
            .onChange(of: bleManager.isFullyReady) { ready in
                print("ready so trying to out now ok....")
                if ready {
                    print("ble ready..........")
                    bleManager.clear()
                }
            }

            Button("Send BMP") {
 
                
                if let bmpData = renderer.renderBMP(fixed: displayedSubtitles,
                                                    hiragana: displayedHiragana,
                                                    eigo: displayedEigo) {
                    bleManager.sendImage(bmpData, to: "Both")
                    
                } else {
                    print("⚠️ No BMP data to send")
                }
            }
            .padding()
            .background(Color.green)
            .foregroundColor(.white)
            .cornerRadius(10)
        }



    }
    
    @ViewBuilder
    func subtitleRow(_ subs: [Subtitle]) -> some View {
        HStack {
            ForEach(0..<5, id: \.self) { i in
                let sub = subs[i]
                Text(sub.text)
                    .foregroundColor(.white)           // white text
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
        let base = "https://41j.com/anathemhtml/static/"
        
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

        // Avoid re-adding the same subtitle
        if displayedSubtitles.contains(where: { $0.index == active.index }) {
            return
        }

        // Main track (always update)
        displayedSubtitles[subtitleCounter % 5] = active
        subtitleCounter += 1

        // Hiragana: always add, even if blank
        if subtitlesHiragana.indices.contains(currentIndex) {
            let h = subtitlesHiragana[currentIndex]
            displayedHiragana[counterHiragana % 5] = h
            counterHiragana += 1
        }

        // Eigo: same
        if subtitlesEigo.indices.contains(currentIndex) {
            let e = subtitlesEigo[currentIndex]
            displayedEigo[counterEigo % 5] = e
            counterEigo += 1
        }
        
            
            if (bleManager.isFullyReady) {
                
                
                let lines = zip(zip(displayedSubtitles, displayedHiragana), displayedEigo).map {
                    let subtitle = $0.0.0.text
                    let hiragana = $0.0.1.text
                    let eigo     = $0.1.text
                    return "\(subtitle):\(hiragana):\(eigo)"
                }

                let result = lines.joined(separator: "\n")

                print("sending: \(result)")
                bleManager.sendText(
                    text: result,
                    counter: 1
                )
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
        guard time.isFinite else {
            return "--:--"
        }

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


}
