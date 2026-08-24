import Foundation

enum Geometry {
    static func midpoint(_ a: Landmark, _ b: Landmark) -> Landmark {
        Landmark(
            x: (a.x + b.x) / 2,
            y: (a.y + b.y) / 2,
            z: (a.z + b.z) / 2,
            visibility: min(a.visibility, b.visibility),
            presence: min(a.presence, b.presence),
            isPredicted: a.isPredicted || b.isPredicted
        )
    }

    static func distance(_ a: Landmark, _ b: Landmark) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }

    static func angle(_ a: Landmark, _ vertex: Landmark, _ c: Landmark) -> Double {
        let ab = (a.x - vertex.x, a.y - vertex.y)
        let cb = (c.x - vertex.x, c.y - vertex.y)
        let denominator = hypot(ab.0, ab.1) * hypot(cb.0, cb.1)
        guard denominator > 0.000_001 else { return .nan }
        let cosine = max(-1, min(1, (ab.0 * cb.0 + ab.1 * cb.1) / denominator))
        return acos(cosine) * 180 / .pi
    }

    static func trunkAngleFromVertical(hip: Landmark, shoulder: Landmark) -> Double {
        let dx = shoulder.x - hip.x
        let dy = shoulder.y - hip.y
        guard abs(dx) + abs(dy) > 0.000_001 else { return .nan }
        return abs(atan2(dx, dy) * 180 / .pi)
    }
}
