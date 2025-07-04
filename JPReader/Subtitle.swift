//
//  Subtitle.swift
//  JPReader
//
//  Created by new on 2025/06/29.
//


import Foundation

struct Subtitle: Identifiable, Equatable {
    var id: Int { index }
    let index: Int
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}

func parseSRT(_ srt: String) -> [Subtitle] {
    let blocks = srt.components(separatedBy: "\n\n")
    var subtitles: [Subtitle] = []

    for (i, block) in blocks.enumerated() {
        let lines = block.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count >= 2 else { continue }

        let timeParts = lines[1].components(separatedBy: " --> ")
        guard timeParts.count == 2 else { continue }

        func timeStringToSeconds(_ str: String) -> TimeInterval {
            let parts = str.replacingOccurrences(of: ",", with: ".").components(separatedBy: ":")
            guard parts.count == 3 else { return 0 }
            return (Double(parts[0]) ?? 0) * 3600 + (Double(parts[1]) ?? 0) * 60 + (Double(parts[2]) ?? 0)
        }

        let start = timeStringToSeconds(timeParts[0])
        let end = timeStringToSeconds(timeParts[1])
        let text: String
        if lines.count >= 3 {
            text = lines[2...].joined(separator: " ")
        } else if lines.count == 2 {
            text = ""
        } else {
            continue
        }

        subtitles.append(Subtitle(index: i, start: start, end: end, text: text))
    }

    return subtitles
}

