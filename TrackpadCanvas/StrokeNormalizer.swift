//
//  StrokeNormalizer.swift
//  TrackpadCanvas
//
//  Created by Siddharth Lalwani on 20/03/26.
//

import Foundation
import CoreGraphics

struct StrokeNormalizer {
    
    // MARK: - Main Entry Point
    static func normalize(_ strokes: [[NSPoint]]) -> [[NSPoint]] {
        guard !strokes.isEmpty else { return strokes }
        let smoothed = smoothStrokes(strokes)
        let baseline = detectBaseline(smoothed)
        let driftCorrected = correctVerticalDrift(smoothed, baseline: baseline)
        let tiltCorrected = correctTilt(driftCorrected)
        return tiltCorrected
    }
    
    // MARK: - Baseline Detection
    static func detectBaseline(_ strokes: [[NSPoint]]) -> CGFloat {
        let midpoints = strokes.compactMap { stroke -> CGFloat? in
            guard !stroke.isEmpty else { return nil }
            let minY = stroke.map { $0.y }.min()!
            let maxY = stroke.map { $0.y }.max()!
            return (minY + maxY) / 2
        }
        guard !midpoints.isEmpty else { return 0 }
        let sorted = midpoints.sorted()
        return sorted[sorted.count / 2]  // median
    }
    
    // MARK: - Vertical Drift Correction
    static func correctVerticalDrift(_ strokes: [[NSPoint]], baseline: CGFloat) -> [[NSPoint]] {
        return strokes.map { stroke in
            guard !stroke.isEmpty else { return stroke }
            let minY = stroke.map { $0.y }.min()!
            let maxY = stroke.map { $0.y }.max()!
            let strokeHeight = maxY - minY
            let strokeMidY = (minY + maxY) / 2
            let drift = strokeMidY - baseline
            
            // only correct if drift is significant but stroke size is normal
            if abs(drift) > 15 && strokeHeight < 80 {
                return stroke.map { NSPoint(x: $0.x, y: $0.y - drift) }
            }
            return stroke
        }
    }
    
    // MARK: - Tilt Correction
    static func correctTilt(_ strokes: [[NSPoint]]) -> [[NSPoint]] {
        guard strokes.count >= 2 else { return strokes }
        
        // get midpoint y of first and last stroke
        let firstStroke = strokes.first!
        let lastStroke = strokes.last!
        
        let firstMidY = (firstStroke.map { $0.y }.min()! + firstStroke.map { $0.y }.max()!) / 2
        let lastMidY = (lastStroke.map { $0.y }.min()! + lastStroke.map { $0.y }.max()!) / 2
        
        let firstMidX = (firstStroke.map { $0.x }.min()! + firstStroke.map { $0.x }.max()!) / 2
        let lastMidX = (lastStroke.map { $0.x }.min()! + lastStroke.map { $0.x }.max()!) / 2
        
        let deltaX = lastMidX - firstMidX
        let deltaY = lastMidY - firstMidY
        
        guard abs(deltaX) > 1 else { return strokes }
        
        let angle = atan2(deltaY, deltaX) * 180 / .pi
        
        // only correct if tilt > 5 degrees
        guard abs(angle) > 5 else { return strokes }
        
        let tiltPerUnit = deltaY / max(deltaX, 1)
        
        return strokes.map { stroke in
            stroke.map { p in
                let correction = (p.x - firstMidX) * tiltPerUnit
                return NSPoint(x: p.x, y: p.y - correction)
            }
        }
    }
    
    // MARK: - Stroke Smoothing
    static func smoothStrokes(_ strokes: [[NSPoint]]) -> [[NSPoint]] {
        return strokes.map { smoothSingleStroke($0) }
    }
    
    private static func smoothSingleStroke(_ stroke: [NSPoint]) -> [NSPoint] {
        guard stroke.count > 3 else { return stroke }
        
        var smoothed: [NSPoint] = []
        // moving average window of 3
        for i in 0..<stroke.count {
            let prev = stroke[max(0, i - 1)]
            let curr = stroke[i]
            let next = stroke[min(stroke.count - 1, i + 1)]
            smoothed.append(NSPoint(
                x: (prev.x + curr.x + next.x) / 3,
                y: (prev.y + curr.y + next.y) / 3
            ))
        }
        
        // reduce point density — keep 1 point per 4px
        var reduced: [NSPoint] = []
        var lastKept = smoothed[0]
        reduced.append(lastKept)
        
        for point in smoothed.dropFirst() {
            let dx = point.x - lastKept.x
            let dy = point.y - lastKept.y
            let dist = sqrt(dx*dx + dy*dy)
            if dist >= 4 {
                reduced.append(point)
                lastKept = point
            }
        }
        
        return reduced
    }
}
