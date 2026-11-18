import Foundation

/// USB Wacom tablets that speak the Graphire protocol (Linux types GRAPHIRE and WACOM_G4).
/// Sizes, pressure range and resolution come from the Linux kernel's `wacom_wac.c` feature table.
struct TabletModel {
    let productID: Int
    let name: String
    let maxX: Double
    let maxY: Double
    let maxPressure: Double
    /// Tablet counts per millimetre.
    let resolution: Double
    /// Graphire4: has two pad buttons and a scroll wheel on the tablet.
    let hasPad: Bool
    /// Verified on real hardware.
    let tested: Bool

    static let vendorID = 0x056A

    static let all: [TabletModel] = [
        .init(productID: 0x10, name: "Graphire",            maxX: 10206, maxY: 7422,  maxPressure: 511,  resolution: 80,  hasPad: false, tested: true),
        .init(productID: 0x11, name: "Graphire2 4x5",       maxX: 10206, maxY: 7422,  maxPressure: 511,  resolution: 80,  hasPad: false, tested: false),
        .init(productID: 0x12, name: "Graphire2 5x7",       maxX: 13918, maxY: 10206, maxPressure: 511,  resolution: 80,  hasPad: false, tested: false),
        .init(productID: 0x13, name: "Graphire3 4x5",       maxX: 10208, maxY: 7424,  maxPressure: 511,  resolution: 80,  hasPad: false, tested: false),
        .init(productID: 0x14, name: "Graphire3 6x8",       maxX: 16704, maxY: 12064, maxPressure: 511,  resolution: 80,  hasPad: false, tested: false),
        .init(productID: 0x15, name: "Graphire4 4x5",       maxX: 10208, maxY: 7424,  maxPressure: 511,  resolution: 80,  hasPad: true,  tested: false),
        .init(productID: 0x16, name: "Graphire4 6x8",       maxX: 16704, maxY: 12064, maxPressure: 511,  resolution: 80,  hasPad: true,  tested: false),
        .init(productID: 0x19, name: "Bamboo1 Medium",      maxX: 16704, maxY: 12064, maxPressure: 511,  resolution: 80,  hasPad: false, tested: false),
        .init(productID: 0x60, name: "Volito",              maxX: 5104,  maxY: 3712,  maxPressure: 511,  resolution: 50,  hasPad: false, tested: false),
        .init(productID: 0x61, name: "PenStation2",         maxX: 3250,  maxY: 2320,  maxPressure: 255,  resolution: 50,  hasPad: false, tested: false),
        .init(productID: 0x62, name: "Volito2 4x5",         maxX: 5104,  maxY: 3712,  maxPressure: 511,  resolution: 50,  hasPad: false, tested: false),
        .init(productID: 0x63, name: "Volito2 2x3",         maxX: 3248,  maxY: 2320,  maxPressure: 511,  resolution: 50,  hasPad: false, tested: false),
        .init(productID: 0x64, name: "PenPartner2",         maxX: 3250,  maxY: 2320,  maxPressure: 511,  resolution: 50,  hasPad: false, tested: false),
        .init(productID: 0x69, name: "Bamboo1",             maxX: 5104,  maxY: 3712,  maxPressure: 511,  resolution: 40,  hasPad: false, tested: false),
        .init(productID: 0x6A, name: "Bamboo1 4x6",         maxX: 14760, maxY: 9225,  maxPressure: 1023, resolution: 100, hasPad: false, tested: false),
        .init(productID: 0x6B, name: "Bamboo1 5x8",         maxX: 21648, maxY: 13530, maxPressure: 1023, resolution: 100, hasPad: false, tested: false),
    ]

    static func find(productID: Int) -> TabletModel? { all.first { $0.productID == productID } }
}
