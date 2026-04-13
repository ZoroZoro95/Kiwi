//
//  SymbolClassifier.swift
//  TrackpadCanvas
//
//  Created by Siddharth Lalwani on 20/03/26.
//

import Foundation
import CoreGraphics

enum SymbolType {
    case nonGroupable
    case groupable
    case bigOperator
}

struct SymbolClassifier {
    
    static func classify(_ strokes: [[NSPoint]]) -> SymbolType {
        guard !strokes.isEmpty else { return .groupable }
        
        let allPoints = strokes.flatMap { $0 }
        guard allPoints.count > 3 else { return .groupable }
        
        let minX = allPoints.map { $0.x }.min()!
        let maxX = allPoints.map { $0.x }.max()!
        let minY = allPoints.map { $0.y }.min()!
        let maxY = allPoints.map { $0.y }.max()!
        
        let width = maxX - minX
        let height = maxY - minY
        let aspectRatio = width / max(height, 1)
        
        // horizontal line only — must be very flat and wide
        if height < 8 && width > 30 && aspectRatio > 4.0 {
            return .nonGroupable
        }
        
        // big operator: tall single stroke (∫)
        if strokes.count == 1 && height > 100 && aspectRatio < 0.5 {
            return .bigOperator
        }
        
        return .groupable
    }
}
