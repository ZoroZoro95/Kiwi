//
//  Symbol.swift
//  TrackpadCanvas
//
//  Created by Siddharth Lalwani on 15/02/26.
//

import Foundation
import CoreGraphics

struct Symbol {
    let id : UUID
    var strokes : [[NSPoint]]
    var dots : [NSPoint]
    var boundingBox : NSRect
    var timestamp : Date
    
    init(strokes: [[NSPoint]], dots: [NSPoint] = []) {
        self.id = UUID()
        self.strokes = strokes
        self.dots = dots
        self.timestamp = Date()
        self.boundingBox = Symbol.computeBoundingBox(strokes: strokes, dots: dots)
    }
    
    static func computeBoundingBox(strokes:[[NSPoint]], dots:[NSPoint]) -> NSRect{
        let allPoints = strokes.flatMap { $0 } + dots
        guard !allPoints.isEmpty else { return.zero }
        
        let minX = allPoints.map { $0.x }.min()!
        let maxX = allPoints.map { $0.x }.max()!
        let minY = allPoints.map { $0.y }.min()!
        let maxY = allPoints.map { $0.y }.max()!
        
        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    
}

