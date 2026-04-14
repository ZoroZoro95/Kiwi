//
//  GroupingDetector.swift
//  TrackpadCanvas
//
//  Created by Siddharth Lalwani on 14/04/26.
//

import Foundation
import CoreGraphics

struct GroupingDetector {
    
    // MARK: - Main Entry Point
    static func detect(current: Symbol, previous: Symbol?) -> GroupingResult {
        guard let prev = previous else { return .newSymbol }
        
        let currentBox = current.boundingBox
        let prevBox = prev.boundingBox
        
        // dot above detection (for i, j)
        if current.strokes.isEmpty && !current.dots.isEmpty {
            if isDotAbove(dot: current.dots[0], symbol: prev) {
                return .mergeAsDot
            }
        }
        
        // exponent detection
        if isExponent(current: currentBox, previous: prevBox) {
            return .mergeAsExponent
        }
        
        // subscript detection
        if isSubscript(current: currentBox, previous: prevBox) {
            return .mergeAsSubscript
        }
        
        // coefficient detection (digit then letter, same baseline)
        if isCoefficient(current: currentBox, previous: prevBox) {
            return .mergeAsCoefficient
        }
        
        return .newSymbol
    }
    
    // MARK: - Detection Rules
    private static func isDotAbove(dot: NSPoint, symbol: Symbol) -> Bool {
        let box = symbol.boundingBox
        let horizontallyAligned = abs(dot.x - box.midX) < 15
        let aboveSymbol = dot.y > box.maxY + 10 && dot.y < box.maxY + 80
        return horizontallyAligned && aboveSymbol
    }
    
    private static func isExponent(current: NSRect, previous: NSRect) -> Bool {
        let isSmall = current.height < previous.height * 0.6
        let isAboveMidpoint = current.midY > previous.midY
        let isToTheRight = current.minX > previous.maxX - 15 && current.minX < previous.maxX + 30
        return isSmall && isAboveMidpoint && isToTheRight
    }
    
    private static func isSubscript(current: NSRect, previous: NSRect) -> Bool {
        let isSmall = current.height < previous.height * 0.6
        let isBelowMidpoint = current.midY < previous.midY
        let isToTheRight = current.minX > previous.maxX - 15 && current.minX < previous.maxX + 30
        return isSmall && isBelowMidpoint && isToTheRight
    }
    
    private static func isCoefficient(current: NSRect, previous: NSRect) -> Bool {
        let sameBaseline = abs(current.minY - previous.minY) < 10
        let similarHeight = abs(current.height - previous.height) < 20
        let noGap = current.minX < previous.maxX + 10
        return sameBaseline && similarHeight && noGap
    }
}

enum GroupingResult {
    case newSymbol
    case mergeAsDot
    case mergeAsExponent
    case mergeAsSubscript
    case mergeAsCoefficient
}
