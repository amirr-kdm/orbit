import SwiftUI

// MARK: - Store planets

/// How rare a store planet is (sets its price range and badge colour)
enum Rarity: String, CaseIterable, Identifiable {
    case common, rare, epic, legendary

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .common: Color(hex: "#94A3B8")
        case .rare: Color(hex: "#38BDF8")
        case .epic: Color(hex: "#A855F7")
        case .legendary: Color(hex: "#F59E0B")
        }
    }

    static func of(price: Int) -> Rarity {
        switch price {
        case ..<300: .common
        case ..<550: .rare
        case ..<850: .epic
        default: .legendary
        }
    }
}

/// Spacecraft that orbit a store planet
enum Craft: Hashable {
    case rocket, ufo, station, satellite, shuttle, comet
    /// A belt of tumbling rocks around the planet
    case asteroids
    /// Twinkling stars around the planet
    case stars
    /// An astronaut floating on the orbit
    case astronaut
}

extension PlanetDef {
    var rarity: Rarity { Rarity.of(price: price) }
    var isStoreItem: Bool { price > 0 }
}

extension PlanetCatalog {
    /// Store items whose picture is in this build (personal-only art is missing from release builds)
    static var storeAvailable: [PlanetDef] {
        store.filter { p in p.image.map { PlanetPainter.bundleImage($0) != nil } ?? true }
    }

    /// Level Pass prizes (levels 10, 20 … 60): animated planets you can't buy
    static let rewards: [PlanetDef] = [
        PlanetDef(id: "lv_t1", name: "Penguin Ride", level: 1, blurb: "Level 10 prize: two penguins riding a rocket through pink clouds.",
                  colors: ["#FBCFE8", "#EC4899", "#831843"], accent: "#F9A8D4", glow: true, price: 0, image: "lv_t1"),
        PlanetDef(id: "lv_t2", name: "Penguin Probe", level: 1, blurb: "Level 20 prize: a penguin keeping watch from its satellite.",
                  colors: ["#BAE6FD", "#38BDF8", "#0C4A6E"], accent: "#7DD3FC", glow: true, price: 0, image: "lv_t2"),
        PlanetDef(id: "lv_t3", name: "Shiba Launch", level: 1, blurb: "Level 30 prize: a pixel Shiba blasting off.",
                  colors: ["#FED7AA", "#F97316", "#7C2D12"], accent: "#FDBA74", glow: true, price: 0, image: "lv_t3"),
        PlanetDef(id: "lv_t4", name: "Frog Planet", level: 1, blurb: "Level 40 prize: a very tired frog world with its own ring.",
                  colors: ["#BBF7D0", "#22C55E", "#14532D"], accent: "#86EFAC", glow: true, price: 0, image: "lv_t4"),
        PlanetDef(id: "lv_t5", name: "Happy Earth", level: 1, blurb: "Level 50 prize: a cheerful Earth waving at its moon.",
                  colors: ["#BFDBFE", "#3B82F6", "#14532D"], accent: "#93C5FD", glow: true, price: 0, image: "lv_t5"),
        PlanetDef(id: "lv_t6", name: "Penguin Voyager", level: 1, blurb: "Level 60 prize: the final ride — a penguin rocketing past Mars.",
                  colors: ["#E9D5FF", "#A855F7", "#3B0764"], accent: "#D8B4FE", glow: true, price: 0, image: "lv_t6"),
    ]

    /// Store planets you buy with rockets. Kept apart from the 50 level planets.
    /// Each one is a little world with a story: who lives there and what flies around it.
    static let store: [PlanetDef] = [
        // MARK: Common (100–299)
        PlanetDef(id: "s2_bees", name: "Bee Meadow", level: 1, blurb: "Sunflowers everywhere and bees buzzing between them.",
                  colors: ["#FEF9C3", "#84CC16", "#365314"], pattern: .dots, accent: "#FDE047",
                  price: 110, walkers: ["🐝"], landmarks: ["🌻", "🌻", "🌻"]),
        PlanetDef(id: "s_lemondrop", name: "Citrus Grove", level: 1, blurb: "Lemon trees, a little farmhouse and very sour air.",
                  colors: ["#FEF9C3", "#FACC15", "#A16207"], pattern: .dots, accent: "#FFFBEB",
                  price: 130, walkers: ["🐌"], landmarks: ["🌳", "🏡", "🍋"]),
        PlanetDef(id: "s2_beach", name: "Beach Paradise", level: 1, blurb: "Palm trees, warm sand and crabs on holiday.",
                  colors: ["#A5F3FC", "#06B6D4", "#155E75"], pattern: .waves, accent: "#FDE68A",
                  crafts: [.stars], price: 150, walkers: ["🦀"], landmarks: ["🌴", "⛱️", "🌴"]),
        PlanetDef(id: "s_comet", name: "Comet Tail", level: 1, blurb: "An icy world with a comet that never leaves.",
                  colors: ["#E0F2FE", "#7DD3FC", "#0369A1"], pattern: .craters, accent: "#0C4A6E",
                  crafts: [.comet], price: 160),
        PlanetDef(id: "s2_candy", name: "Candy Land", level: 1, blurb: "Lollipop trees and a gingerbread man out for a walk.",
                  colors: ["#FCE7F3", "#F472B6", "#9D174D"], pattern: .sprinkles, accent: "#FDE047",
                  price: 180, walkers: ["🧁"], landmarks: ["🍭", "🍬", "🍭"]),
        PlanetDef(id: "s_mint", name: "Mint Orbit", level: 1, blurb: "A cool green world watched over by a tiny satellite.",
                  colors: ["#D1FAE5", "#34D399", "#065F46"], pattern: .bands, accent: "#ECFDF5",
                  crafts: [.satellite, .stars], price: 200),
        PlanetDef(id: "s2_farm", name: "Happy Farm", level: 1, blurb: "Cows, a red barn and a tractor working all day.",
                  colors: ["#D9F99D", "#65A30D", "#365314"], pattern: .mountains, accent: "#1A2E05",
                  price: 220, walkers: ["🐄", "🚜"], landmarks: ["🌾", "🏠", "🌾"]),
        PlanetDef(id: "s_launchpad", name: "Launch Pad", level: 1, blurb: "Pixel rockets take off from here every hour.",
                  colors: ["#E2E8F0", "#64748B", "#1E293B"], pattern: .craters, accent: "#CBD5E1",
                  crafts: [.rocket, .stars], price: 240, landmarks: ["🗼", "🏗️"]),
        PlanetDef(id: "s2_penguins", name: "Penguin Pole", level: 1, blurb: "Penguins waddle between igloos and snowy peaks.",
                  colors: ["#F8FAFC", "#BAE6FD", "#0EA5E9"], pattern: .snowflakes, accent: "#FFFFFF",
                  price: 260, walkers: ["🐧", "🐧"], landmarks: ["🏔️", "⛄"]),
        PlanetDef(id: "s2_winter", name: "Winter Village", level: 1, blurb: "Cosy cabins, Christmas trees and a skier racing past.",
                  colors: ["#FFFFFF", "#CBD5E1", "#64748B"], pattern: .snowflakes, accent: "#E0F2FE",
                  crafts: [.stars], price: 290, walkers: ["⛷️"], landmarks: ["🎄", "🏠", "🎄"]),

        // MARK: Rare (300–549)
        PlanetDef(id: "s_sakura", name: "Sakura Garden", level: 1, blurb: "A shrine under cherry blossoms, with a panda keeping watch.",
                  colors: ["#FCE7F3", "#F9A8D4", "#9D174D"], pattern: .waves, accent: "#FFFFFF",
                  price: 310, walkers: ["🐼"], landmarks: ["🌸", "⛩️", "🌸"]),
        PlanetDef(id: "s_moonbase", name: "Moonbase", level: 1, blurb: "Flag planted, rocket parked, astronaut on a walk.",
                  colors: ["#F8FAFC", "#94A3B8", "#334155"], pattern: .craters, accent: "#1E293B",
                  features: [.flag], crafts: [.rocket], price: 330, walkers: ["🧑‍🚀"]),
        PlanetDef(id: "s2_spooky", name: "Pumpkin Hollow", level: 1, blurb: "Jack-o'-lanterns glow while a ghost floats around.",
                  colors: ["#FDBA74", "#EA580C", "#431407"], pattern: .craters, accent: "#1C1917", moons: 1,
                  crafts: [.stars], price: 350, walkers: ["👻"], landmarks: ["🎃", "🏚️", "🎃"]),
        PlanetDef(id: "s_neongrid", name: "Cyber City", level: 1, blurb: "Skyscrapers glow all night and robots run the streets.",
                  colors: ["#818CF8", "#312E81", "#0F0A2E"], pattern: .hexgrid, accent: "#22D3EE", glow: true,
                  crafts: [.satellite], price: 380, walkers: ["🤖"], landmarks: ["🏢", "🏙️", "🏢"]),
        PlanetDef(id: "s2_whale", name: "Whale Ocean", level: 1, blurb: "A blue whale cruises past a sailboat and a lighthouse.",
                  colors: ["#7DD3FC", "#0284C7", "#082F49"], pattern: .waves, accent: "#E0F2FE",
                  price: 400, walkers: ["🐋", "⛵"], landmarks: ["🗼"]),
        PlanetDef(id: "s_station", name: "Station Alpha", level: 1, blurb: "A golden ring and a space station on patrol.",
                  colors: ["#FEF3C7", "#F59E0B", "#78350F"], pattern: .bands, accent: "#FFFBEB",
                  ring: .init(color: "#FDE68A", tilt: -14, width: 0.12), crafts: [.station, .stars], price: 420),
        PlanetDef(id: "s2_desert", name: "Pharaoh's Desert", level: 1, blurb: "Pyramids, cactus and a camel crossing the dunes.",
                  colors: ["#FEF3C7", "#F59E0B", "#92400E"], pattern: .waves, accent: "#FDE68A",
                  crafts: [.comet], price: 440, walkers: ["🐪"], landmarks: ["🌵", "🔺", "🌵"]),
        PlanetDef(id: "s2_jungle", name: "Rainforest", level: 1, blurb: "Monkeys swing and parrots chatter in the canopy.",
                  colors: ["#86EFAC", "#15803D", "#052E16"], pattern: .mountains, accent: "#14532D",
                  price: 460, walkers: ["🐒", "🦜"], landmarks: ["🌳", "🌴", "🌳"]),
        PlanetDef(id: "s_ufo", name: "Close Encounter", level: 1, blurb: "A UFO circles while a little alien explores below.",
                  colors: ["#C7D2FE", "#6366F1", "#1E1B4B"], pattern: .craters, accent: "#312E81",
                  crafts: [.ufo, .stars], price: 490, walkers: ["👽"]),
        PlanetDef(id: "s2_pirates", name: "Pirate Cove", level: 1, blurb: "A pirate ship patrols the island hiding the treasure.",
                  colors: ["#5EEAD4", "#0F766E", "#042F2E"], pattern: .waves, accent: "#FDE68A",
                  price: 520, walkers: ["🏴‍☠️"], landmarks: ["🏝️", "💰"]),

        // MARK: Epic (550–849)
        PlanetDef(id: "s2_mars", name: "Mars Colony", level: 1, blurb: "Domes, a landed rocket and a rover exploring red dust.",
                  colors: ["#FDBA74", "#C2410C", "#431407"], pattern: .craters, accent: "#7C2D12",
                  crafts: [.satellite, .stars], price: 560, walkers: ["🚙"], landmarks: ["🛖", "🚀", "🛖"]),
        PlanetDef(id: "s_crystal", name: "Crystal Fortress", level: 1, blurb: "A diamond citadel under a holy halo.",
                  shape: .diamond, colors: ["#ECFEFF", "#67E8F9", "#155E75"], pattern: .rainbow, accent: "#FFFFFF",
                  features: [.halo], glow: true, crafts: [.stars], price: 580),
        PlanetDef(id: "s2_mine", name: "Asteroid Mine", level: 1, blurb: "Miners dig for gems while rocks tumble overhead.",
                  colors: ["#D6D3D1", "#78716C", "#1C1917"], pattern: .craters, accent: "#FDE047",
                  crafts: [.asteroids, .shuttle], price: 600, walkers: ["👷"], landmarks: ["⛏️", "💎"]),
        PlanetDef(id: "s_solarsail", name: "Solar Sail", level: 1, blurb: "Sun-powered, with a station and a satellite.",
                  colors: ["#FFEDD5", "#FB923C", "#9A3412"], pattern: .waves, accent: "#FEF3C7",
                  crafts: [.station, .satellite, .stars], price: 620),
        PlanetDef(id: "s2_zoo", name: "Space Zoo", level: 1, blurb: "Giraffes and elephants roam the galaxy's biggest zoo.",
                  colors: ["#BBF7D0", "#4ADE80", "#14532D"], pattern: .mountains, accent: "#052E16",
                  crafts: [.rocket], price: 650, walkers: ["🦒", "🐘"], landmarks: ["🌳", "🎪"]),
        PlanetDef(id: "s_rally", name: "Rocket Rally", level: 1, blurb: "Two rockets racing around a double ring.",
                  colors: ["#FECACA", "#EF4444", "#7F1D1D"], pattern: .stripes, accent: "#FEE2E2",
                  ring: .init(color: "#F8FAFC", tilt: 22, width: 0.08, double: true), crafts: [.rocket, .rocket], price: 680),
        PlanetDef(id: "s2_tokyo", name: "Neon Tokyo", level: 1, blurb: "A pagoda, a tower and a bullet train under the stars.",
                  colors: ["#F0ABFC", "#A21CAF", "#2E1065"], pattern: .plain, accent: "#F472B6", glow: true,
                  crafts: [.stars], price: 710, walkers: ["🚄"], landmarks: ["🏯", "🗼", "⛩️"]),
        PlanetDef(id: "s_dragonegg", name: "Dragon Egg", level: 1, blurb: "Warm to the touch. Something is moving inside.",
                  shape: .egg, colors: ["#BBF7D0", "#22C55E", "#14532D"], pattern: .hexgrid, accent: "#052E16",
                  features: [.fireWings], glow: true, price: 740),
        PlanetDef(id: "s2_observatory", name: "Stargazer Peak", level: 1, blurb: "A telescope on the summit, counting every comet.",
                  colors: ["#C4B5FD", "#5B21B6", "#1E1B4B"], pattern: .mountains, accent: "#2E1065",
                  crafts: [.comet, .stars], price: 770, walkers: ["🦉"], landmarks: ["🔭", "🏔️"]),
        PlanetDef(id: "s_mothership", name: "Mothership", level: 1, blurb: "The whole UFO fleet calls this place home.",
                  colors: ["#BEF264", "#4D7C0F", "#1A2E05"], pattern: .spots, accent: "#D9F99D", moons: 1,
                  glow: true, crafts: [.ufo, .ufo, .stars], price: 800, walkers: ["👽"]),
        PlanetDef(id: "s2_kingdom", name: "Dragon Kingdom", level: 1, blurb: "A castle on the hill and a dragon guarding the sky.",
                  colors: ["#A7F3D0", "#059669", "#064E3B"], pattern: .mountains, accent: "#022C22",
                  crafts: [.stars], price: 830, walkers: ["🐉", "🐎"], landmarks: ["🏰"]),

        // MARK: Legendary (850–1000)
        PlanetDef(id: "s_blackhole", name: "Event Horizon", level: 1, blurb: "Light bends around it. So does time.",
                  colors: ["#475569", "#0F172A", "#000000"], pattern: .swirl, accent: "#F472B6",
                  ring: .init(color: "#FB923C", tilt: -10, width: 0.22, double: true), glow: true,
                  crafts: [.comet, .asteroids], price: 860),
        PlanetDef(id: "s2_robots", name: "Robot Factory", level: 1, blurb: "Robots build more robots, day and night.",
                  colors: ["#E2E8F0", "#64748B", "#0F172A"], pattern: .checker, accent: "#38BDF8",
                  crafts: [.satellite, .station], price: 880, walkers: ["🤖", "🦾"], landmarks: ["🏭", "🏭"]),
        PlanetDef(id: "s_captain", name: "Captain Whiskers", level: 1, blurb: "The coolest cat in the fleet flies his own rocket.",
                  colors: ["#FDE68A", "#F59E0B", "#92400E"], pattern: .stripes, accent: "#78350F",
                  features: [.catEars, .sunglasses, .whiskers], crafts: [.rocket, .stars], price: 900),
        PlanetDef(id: "s2_jurassic", name: "Jurassic World", level: 1, blurb: "Dinosaurs roam the jungle while meteors streak past.",
                  colors: ["#A3E635", "#3F6212", "#1A2E05"], pattern: .mountains, accent: "#14532D",
                  crafts: [.asteroids, .comet], price: 920, walkers: ["🦕", "🦖"], landmarks: ["🌴", "🌋", "🌴"]),
        PlanetDef(id: "s_odyssey", name: "Starship Odyssey", level: 1, blurb: "A shuttle, a rocket and a station on one long voyage.",
                  colors: ["#DBEAFE", "#3B82F6", "#1E3A8A"], pattern: .clouds, accent: "#E0F2FE",
                  ring: .init(color: "#93C5FD", tilt: 18, width: 0.1), moons: 1, glow: true,
                  crafts: [.shuttle, .rocket, .station], price: 950),
        PlanetDef(id: "s_royal", name: "Royal Nebula", level: 1, blurb: "A crowned world wrapped in violet starlight.",
                  colors: ["#F5D0FE", "#A855F7", "#3B0764"], pattern: .waves, accent: "#FDE047",
                  ring: .init(color: "#E9D5FF", tilt: -24, width: 0.14), moons: 2, features: [.crown], glow: true,
                  crafts: [.satellite, .stars], price: 970),
        PlanetDef(id: "s3_meteor", name: "Meteor Strike", level: 1, blurb: "A blazing pixel meteor on a collision course.",
                  colors: ["#FDE047", "#F97316", "#7C2D12"], accent: "#FB923C", glow: true, price: 720, image: "meteor"),
        PlanetDef(id: "s3_satellite", name: "Deep Space Probe", level: 1, blurb: "An old pixel probe still sending postcards home.",
                  colors: ["#99F6E4", "#14B8A6", "#134E4A"], accent: "#5EEAD4", glow: true, price: 540, image: "satellite"),
        PlanetDef(id: "s3_impact", name: "Comet Impact", level: 1, blurb: "The moment a comet meets a blue world.",
                  colors: ["#FDE68A", "#F59E0B", "#1E3A8A"], accent: "#FCD34D", glow: true, price: 960, image: "gaia"),
        PlanetDef(id: "s_aliens", name: "Alien Visitors", level: 1, blurb: "Two little green friends dropped by in their pixel saucer.",
                  colors: ["#BEF264", "#4ADE80", "#14532D"], accent: "#86EFAC", glow: true, price: 990, image: "ufo"),
        PlanetDef(id: "s5_frost", name: "Frost Shard", level: 1, blurb: "A jagged crystal of ice spinning in the cold.",
                  colors: ["#BAE6FD", "#38BDF8", "#0C4A6E"], accent: "#BAE6FD", glow: true, price: 850, image: "s5_frost"),
        PlanetDef(id: "s5_coral", name: "Coral Bloom", level: 1, blurb: "Soft pink coral with pebbles drifting around it.",
                  colors: ["#FBCFE8", "#EC4899", "#831843"], accent: "#FBCFE8", glow: true, price: 870, image: "s5_coral"),
        PlanetDef(id: "s5_geode", name: "Emerald Geode", level: 1, blurb: "A green world cracked open to glowing gems.",
                  colors: ["#A7F3D0", "#10B981", "#064E3B"], accent: "#A7F3D0", glow: true, price: 890, image: "s5_geode"),
        PlanetDef(id: "s5_maze", name: "Ringed Maze", level: 1, blurb: "A swirling maze world inside a golden ring.",
                  colors: ["#FECDD3", "#F43F5E", "#4C0519"], accent: "#FECDD3", glow: true, price: 910, image: "s5_maze"),
        PlanetDef(id: "s5_cloud", name: "Cloud Garden", level: 1, blurb: "Green lands wrapped in fluffy clouds.",
                  colors: ["#BBF7D0", "#22C55E", "#14532D"], accent: "#BBF7D0", glow: true, price: 880, image: "s5_cloud"),
        PlanetDef(id: "s5_river", name: "River Mars", level: 1, blurb: "A rusty red world with one long blue river.",
                  colors: ["#FED7AA", "#F97316", "#7C2D12"], accent: "#FED7AA", glow: true, price: 900, image: "s5_river"),
        PlanetDef(id: "s5_vortex", name: "Golden Vortex", level: 1, blurb: "A whirl of gold around a dark heart.",
                  colors: ["#FEF08A", "#EAB308", "#422006"], accent: "#FEF08A", glow: true, price: 950, image: "s5_vortex"),
        PlanetDef(id: "s5_crater", name: "Crater Blue", level: 1, blurb: "A quiet blue moon covered in craters.",
                  colors: ["#BFDBFE", "#3B82F6", "#1E3A8A"], accent: "#BFDBFE", glow: true, price: 860, image: "s5_crater"),
        PlanetDef(id: "s5_circuit", name: "Circuit Core", level: 1, blurb: "Golden plates over a glowing teal core.",
                  colors: ["#FDE68A", "#14B8A6", "#134E4A"], accent: "#FDE68A", glow: true, price: 980, image: "s5_circuit"),
        PlanetDef(id: "s5_mushroom", name: "Mushroom Orbit", level: 1, blurb: "Purple mushrooms on a ringed little world.",
                  colors: ["#E9D5FF", "#A855F7", "#3B0764"], accent: "#E9D5FF", glow: true, price: 920, image: "s5_mushroom"),
        PlanetDef(id: "s5_hills", name: "Green Hills", level: 1, blurb: "Rolling hills, trees and a tiny pond.",
                  colors: ["#BBF7D0", "#4ADE80", "#14532D"], accent: "#BBF7D0", glow: true, price: 860, image: "s5_hills"),
        PlanetDef(id: "s5_glacier", name: "Glacier Keep", level: 1, blurb: "An icy keep with frozen waterfalls.",
                  colors: ["#E0F2FE", "#7DD3FC", "#075985"], accent: "#E0F2FE", glow: true, price: 900, image: "s5_glacier"),
        PlanetDef(id: "s5_blossom", name: "Blossom Swirl", level: 1, blurb: "A pink swirl full of flowers.",
                  colors: ["#FBCFE8", "#F472B6", "#831843"], accent: "#FBCFE8", glow: true, price: 870, image: "s5_blossom"),
        PlanetDef(id: "s5_cocoa", name: "Cocoa Swirl", level: 1, blurb: "A chocolate-brown world with a golden swirl.",
                  colors: ["#FDE68A", "#B45309", "#451A03"], accent: "#FDE68A", glow: true, price: 880, image: "s5_cocoa"),
        PlanetDef(id: "s5_candy", name: "Candy Castle", level: 1, blurb: "Caramel towers dripping with frosting.",
                  colors: ["#FED7AA", "#FB923C", "#7C2D12"], accent: "#FED7AA", glow: true, price: 940, image: "s5_candy"),
        PlanetDef(id: "s5_blocks", name: "Block World", level: 1, blurb: "A cube of grass, stone and waterfalls.",
                  colors: ["#D9F99D", "#84CC16", "#365314"], accent: "#D9F99D", glow: true, price: 960, image: "s5_blocks"),
        PlanetDef(id: "s5_lemon", name: "Lemon Reef", level: 1, blurb: "A sunny yellow reef with blue sprouts.",
                  colors: ["#FEF08A", "#FACC15", "#713F12"], accent: "#FEF08A", glow: true, price: 890, image: "s5_lemon"),
        PlanetDef(id: "s5_cotton", name: "Cotton Isle", level: 1, blurb: "A floating isle under pink cotton trees.",
                  colors: ["#FBCFE8", "#2DD4BF", "#134E4A"], accent: "#FBCFE8", glow: true, price: 910, image: "s5_cotton"),
        PlanetDef(id: "s5_slime", name: "Slime World", level: 1, blurb: "A bubbly green world with curious eyes.",
                  colors: ["#BBF7D0", "#34D399", "#065F46"], accent: "#BBF7D0", glow: true, price: 930, image: "s5_slime"),
        PlanetDef(id: "s5_burger", name: "Burger Ring", level: 1, blurb: "A tasty burger with a purple ring.",
                  colors: ["#FDE68A", "#F59E0B", "#78350F"], accent: "#FDE68A", glow: true, price: 850, image: "s5_burger"),
        PlanetDef(id: "s5_hotdog", name: "Hot Dog Orbit", level: 1, blurb: "A hot dog circled by a mustard ring.",
                  colors: ["#FDE68A", "#EF4444", "#7F1D1D"], accent: "#FDE68A", glow: true, price: 860, image: "s5_hotdog"),
        PlanetDef(id: "s5_donut", name: "Donut Planet", level: 1, blurb: "A pink-frosted donut with sprinkles.",
                  colors: ["#FBCFE8", "#EC4899", "#9D174D"], accent: "#FBCFE8", glow: true, price: 880, image: "s5_donut"),
        PlanetDef(id: "s5_taco", name: "Taco Moon", level: 1, blurb: "A crunchy taco with spicy rings.",
                  colors: ["#FDE68A", "#F97316", "#7C2D12"], accent: "#FDE68A", glow: true, price: 870, image: "s5_taco"),
        PlanetDef(id: "s5_sushi", name: "Sushi Saturn", level: 1, blurb: "A salmon roll with its own ring.",
                  colors: ["#FED7AA", "#F97316", "#1F2937"], accent: "#FED7AA", glow: true, price: 900, image: "s5_sushi"),
        PlanetDef(id: "s5_icecream", name: "Ice Cream Comet", level: 1, blurb: "Swirled ice cream racing through space.",
                  colors: ["#E9D5FF", "#C084FC", "#581C87"], accent: "#E9D5FF", glow: true, price: 920, image: "s5_icecream"),
        PlanetDef(id: "s5_burgersaturn", name: "Burger Saturn", level: 1, blurb: "The legendary burger with sparkling rings.",
                  colors: ["#FDE68A", "#A78BFA", "#4C1D95"], accent: "#FDE68A", glow: true, price: 1000, image: "s5_burgersaturn"),
        PlanetDef(id: "s5_duck", name: "Duck Island", level: 1, blurb: "A sea world with a rubber duck and a tiny island.",
                  colors: ["#BAE6FD", "#38BDF8", "#0C4A6E"], accent: "#FDE047", glow: true, price: 890, image: "s5_duck"),
        PlanetDef(id: "s4_spacecat", name: "Cosmo Cat", level: 1, blurb: "A Siamese astronaut floating calmly between the stars.",
                  colors: ["#BAE6FD", "#38BDF8", "#0C4A6E"], accent: "#7DD3FC", glow: true, price: 1000, image: "s4_spacecat"),
        PlanetDef(id: "s4_ufocat", name: "Kitty Cruiser", level: 1, blurb: "A cat at the controls of its own saucer. It moves!",
                  colors: ["#E9D5FF", "#A855F7", "#3B0764"], accent: "#D8B4FE", glow: true, price: 1000, image: "s4_ufocat"),
        PlanetDef(id: "s4_claudecoder", name: "Claude at Work", level: 1, blurb: "Busy typing code somewhere out in space.",
                  colors: ["#FED7AA", "#F97316", "#7C2D12"], accent: "#FDBA74", glow: true, price: 1000, image: "s4_claudecoder"),
        PlanetDef(id: "s4_claudechute", name: "Claude Drop", level: 1, blurb: "Parachuting in to help with your homework.",
                  colors: ["#FED7AA", "#F97316", "#1E3A8A"], accent: "#93C5FD", glow: true, price: 1000, image: "s4_claudechute"),
        PlanetDef(id: "s2_hub", name: "Galactic Hub", level: 1, blurb: "The busiest port in space: ships come and go all day.",
                  colors: ["#E0E7FF", "#6366F1", "#1E1B4B"], pattern: .bands, accent: "#C7D2FE",
                  ring: .init(color: "#A5B4FC", tilt: 14, width: 0.1, double: true), glow: true,
                  crafts: [.station, .ufo, .rocket, .shuttle, .asteroids, .stars], price: 1000, walkers: ["🧑‍🚀"]),
        PlanetDef(id: "s_infinity", name: "Infinity Core", level: 1, blurb: "Every colour, every orbit — the rarest world of all.",
                  shape: .burst, colors: ["#FEF9C3", "#F472B6", "#4C1D95"], pattern: .rainbow, accent: "#FFFFFF",
                  ring: .init(color: "#FDE68A", tilt: 12, width: 0.12, double: true), moons: 3,
                  features: [.halo], glow: true, crafts: [.comet, .shuttle, .stars], price: 1000),
    ]
}

// MARK: - Spacecraft drawing

extension PlanetPainter {
    /// Craft fly on an orbit around the planet; `phase` (0…1) moves them
    static func drawCrafts(_ all: [Craft], ctx: inout GraphicsContext, c: CGPoint, r: CGFloat, phase: Double) {
        if all.contains(.stars) { twinkles(&ctx, c: c, r: r, phase: phase) }
        if all.contains(.asteroids) { asteroidBelt(&ctx, c: c, r: r, phase: phase) }
        let crafts = all.filter { $0 != .stars && $0 != .asteroids }
        for (i, craft) in crafts.enumerated() {
            let a = (Double(i) / Double(max(1, crafts.count)) + phase * (craft == .comet ? 0.6 : 1)) * .pi * 2 + 2.2
            let orbitX = r * (craft == .comet ? 1.55 : 1.42), orbitY = r * 0.62
            let p = CGPoint(x: c.x + cos(a) * orbitX, y: c.y + sin(a) * orbitY - r * 0.1)
            // Direction of travel along the ellipse
            let heading = atan2(cos(a) * orbitY, -sin(a) * orbitX)
            var g = ctx
            g.translateBy(x: p.x, y: p.y)
            g.rotate(by: .radians(craft == .ufo || craft == .station || craft == .satellite ? 0 : heading))
            let u = r * (craft == .comet ? 0.26 : 0.33)
            switch craft {
            case .rocket: rocket(&g, u)
            case .ufo: ufo(&g, u)
            case .station: station(&g, u, spin: phase)
            case .satellite: satellite(&g, u * 0.85)
            case .shuttle: shuttle(&g, u)
            case .comet: comet(&g, u)
            case .astronaut:
                g.rotate(by: .radians(-heading + sin(phase * .pi * 4) * 0.4))
                g.draw(Text("🧑‍🚀").font(.system(size: u * 2)), at: .zero)
            case .asteroids, .stars: break
            }
        }
    }

    /// A ring of tumbling rocks
    private static func asteroidBelt(_ ctx: inout GraphicsContext, c: CGPoint, r: CGFloat, phase: Double) {
        var rng = SeededRandom(seed: "belt")
        for k in 0..<14 {
            let a = (Double(k) / 14 + phase * 0.35) * .pi * 2 + rng.next() * 0.3
            let rx = r * (1.5 + rng.next() * 0.18), ry = r * (0.5 + rng.next() * 0.1)
            let p = CGPoint(x: c.x + cos(a) * rx, y: c.y + sin(a) * ry)
            let s = r * (0.06 + rng.next() * 0.07)
            var rock = Path()
            let spin = phase * .pi * 4 + Double(k)
            for v in 0..<6 {
                let va = Double(v) / 6 * .pi * 2 + spin
                let vr = s * (0.75 + rng.next() * 0.45)
                let q = CGPoint(x: p.x + cos(va) * vr, y: p.y + sin(va) * vr)
                if v == 0 { rock.move(to: q) } else { rock.addLine(to: q) }
            }
            rock.closeSubpath()
            ctx.fill(rock, with: .linearGradient(Gradient(colors: [Color(hex: "#D6D3D1"), Color(hex: "#57534E")]),
                                                 startPoint: CGPoint(x: p.x - s, y: p.y - s), endPoint: CGPoint(x: p.x + s, y: p.y + s)))
        }
    }

    /// Four-point stars that twinkle around the planet
    private static func twinkles(_ ctx: inout GraphicsContext, c: CGPoint, r: CGFloat, phase: Double) {
        var rng = SeededRandom(seed: "stars")
        for k in 0..<7 {
            let a = rng.next() * .pi * 2, d = r * (1.35 + rng.next() * 0.35)
            let p = CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d * 0.85)
            let tw = 0.5 + 0.5 * sin(phase * .pi * 6 + Double(k) * 1.7)
            let s = r * (0.05 + 0.07 * tw)
            var star = Path()
            star.move(to: CGPoint(x: p.x, y: p.y - s * 2))
            star.addQuadCurve(to: CGPoint(x: p.x + s * 2, y: p.y), control: p)
            star.addQuadCurve(to: CGPoint(x: p.x, y: p.y + s * 2), control: p)
            star.addQuadCurve(to: CGPoint(x: p.x - s * 2, y: p.y), control: p)
            star.addQuadCurve(to: CGPoint(x: p.x, y: p.y - s * 2), control: p)
            ctx.fill(star, with: .color(Color(hex: "#FEF9C3").opacity(0.55 + 0.45 * tw)))
        }
    }

    /// Landmarks stand on the upper rim; walkers stroll back and forth across the top
    static func drawSurface(_ p: PlanetDef, ctx: inout GraphicsContext, c: CGPoint, r: CGFloat, phase: Double) {
        let size = r * 0.6
        func standing(_ emoji: String, angle: Double, scale: CGFloat = 1, flip: Bool = false, lift: CGFloat = 0) {
            var g = ctx
            let edge = r + size * scale * 0.38 + lift
            g.translateBy(x: c.x + cos(angle) * edge, y: c.y + sin(angle) * edge)
            g.rotate(by: .radians(angle + .pi / 2))
            if flip { g.scaleBy(x: -1, y: 1) }
            g.draw(Text(emoji).font(.system(size: size * scale)), at: .zero)
        }
        let n = p.landmarks.count
        for (i, e) in p.landmarks.enumerated() {
            // Spread over the top of the planet, away from the walkers' path in the middle
            let t = n == 1 ? 0.5 : Double(i) / Double(n - 1)
            standing(e, angle: -.pi / 2 + (t - 0.5) * 2.1, scale: 1.05)
        }
        for (i, e) in p.walkers.enumerated() {
            let offset = Double(i) * 2.1
            let wave = sin(phase * .pi * 2 + offset)
            let angle = -.pi / 2 + wave * 0.75
            // Face the way it's walking, with a little step bounce
            let goingRight = cos(phase * .pi * 2 + offset) > 0
            let bounce = abs(sin(phase * .pi * 24 + offset)) * size * 0.08
            standing(e, angle: angle, scale: 0.85, flip: goingRight, lift: bounce)
        }
    }

    /// White body, red fins, blue window and a flame (like the rocket currency icon)
    private static func rocket(_ g: inout GraphicsContext, _ u: CGFloat) {
        var flame = Path()
        flame.move(to: CGPoint(x: -u * 1.0, y: -u * 0.28))
        flame.addQuadCurve(to: CGPoint(x: -u * 1.0, y: u * 0.28), control: CGPoint(x: -u * 2.1, y: 0))
        g.fill(flame, with: .linearGradient(Gradient(colors: [Color(hex: "#FDE047"), Color(hex: "#22D3EE"), Color(hex: "#2563EB").opacity(0)]),
                                            startPoint: CGPoint(x: -u, y: 0), endPoint: CGPoint(x: -u * 2.1, y: 0)))
        var fins = Path()
        fins.move(to: CGPoint(x: -u * 0.5, y: -u * 0.3)); fins.addLine(to: CGPoint(x: -u * 1.05, y: -u * 0.75)); fins.addLine(to: CGPoint(x: -u * 0.95, y: -u * 0.2))
        fins.move(to: CGPoint(x: -u * 0.5, y: u * 0.3)); fins.addLine(to: CGPoint(x: -u * 1.05, y: u * 0.75)); fins.addLine(to: CGPoint(x: -u * 0.95, y: u * 0.2))
        g.fill(fins, with: .color(Color(hex: "#F05252")))
        var body = Path()
        body.move(to: CGPoint(x: u * 1.1, y: 0))
        body.addQuadCurve(to: CGPoint(x: -u, y: -u * 0.36), control: CGPoint(x: u * 0.5, y: -u * 0.55))
        body.addLine(to: CGPoint(x: -u, y: u * 0.36))
        body.addQuadCurve(to: CGPoint(x: u * 1.1, y: 0), control: CGPoint(x: u * 0.5, y: u * 0.55))
        g.fill(body, with: .linearGradient(Gradient(colors: [Color(hex: "#F8FAFC"), Color(hex: "#CBD5E1")]),
                                           startPoint: CGPoint(x: 0, y: -u * 0.4), endPoint: CGPoint(x: 0, y: u * 0.4)))
        var nose = Path()
        nose.move(to: CGPoint(x: u * 1.1, y: 0))
        nose.addQuadCurve(to: CGPoint(x: u * 0.55, y: -u * 0.33), control: CGPoint(x: u * 0.9, y: -u * 0.25))
        nose.addLine(to: CGPoint(x: u * 0.55, y: u * 0.33))
        nose.addQuadCurve(to: CGPoint(x: u * 1.1, y: 0), control: CGPoint(x: u * 0.9, y: u * 0.25))
        g.fill(nose, with: .color(Color(hex: "#F05252")))
        let w = CGRect(x: u * 0.05, y: -u * 0.17, width: u * 0.34, height: u * 0.34)
        g.fill(Path(ellipseIn: w.insetBy(dx: -u * 0.05, dy: -u * 0.05)), with: .color(Color(hex: "#475569")))
        g.fill(Path(ellipseIn: w), with: .linearGradient(Gradient(colors: [Color(hex: "#7DD3FC"), Color(hex: "#0284C7")]),
                                                        startPoint: CGPoint(x: w.minX, y: w.minY), endPoint: CGPoint(x: w.maxX, y: w.maxY)))
    }

    /// Flying saucer with a glass dome and two little green aliens
    private static func ufo(_ g: inout GraphicsContext, _ u: CGFloat) {
        g.fill(Path(ellipseIn: CGRect(x: -u * 0.55, y: u * 0.15, width: u * 1.1, height: u * 1.1)),
               with: .linearGradient(Gradient(colors: [Color(hex: "#BEF264").opacity(0.45), .clear]),
                                     startPoint: CGPoint(x: 0, y: u * 0.2), endPoint: CGPoint(x: 0, y: u * 1.3)))
        let dome = CGRect(x: -u * 0.6, y: -u * 0.75, width: u * 1.2, height: u * 1.0)
        g.fill(Path(ellipseIn: dome), with: .color(Color(hex: "#1E293B").opacity(0.9)))
        for dx in [-0.25, 0.25] {
            let head = CGRect(x: u * (dx - 0.13), y: -u * 0.55, width: u * 0.26, height: u * 0.3)
            g.fill(Path(ellipseIn: head), with: .color(Color(hex: "#4ADE80")))
            g.fill(Path(ellipseIn: CGRect(x: head.minX + u * 0.04, y: head.minY + u * 0.1, width: u * 0.07, height: u * 0.08)), with: .color(.black))
            g.fill(Path(ellipseIn: CGRect(x: head.maxX - u * 0.11, y: head.minY + u * 0.1, width: u * 0.07, height: u * 0.08)), with: .color(.black))
        }
        g.stroke(Path(ellipseIn: dome), with: .color(.white.opacity(0.35)), lineWidth: max(0.6, u * 0.05))
        g.fill(Path(ellipseIn: CGRect(x: -u * 1.15, y: -u * 0.28, width: u * 2.3, height: u * 0.55)),
               with: .linearGradient(Gradient(colors: [Color(hex: "#E5E7EB"), Color(hex: "#9CA3AF")]),
                                     startPoint: CGPoint(x: 0, y: -u * 0.3), endPoint: CGPoint(x: 0, y: u * 0.3)))
        g.fill(Path(ellipseIn: CGRect(x: -u * 0.75, y: u * 0.05, width: u * 1.5, height: u * 0.35)), with: .color(Color(hex: "#A78BFA")))
        for k in -2...2 {
            g.fill(Path(ellipseIn: CGRect(x: CGFloat(k) * u * 0.28 - u * 0.05, y: u * 0.17, width: u * 0.1, height: u * 0.1)),
                   with: .color(Color(hex: "#FBCFE8")))
        }
    }

    /// A small station: hub, ring and two solar panels
    private static func station(_ g: inout GraphicsContext, _ u: CGFloat, spin: Double) {
        g.rotate(by: .radians(spin * .pi * 2 * 0.5))
        for side in [-1.0, 1.0] {
            let panel = CGRect(x: side < 0 ? -u * 1.35 : u * 0.45, y: -u * 0.28, width: u * 0.9, height: u * 0.56)
            g.fill(Path(panel), with: .linearGradient(Gradient(colors: [Color(hex: "#60A5FA"), Color(hex: "#1D4ED8")]),
                                                      startPoint: CGPoint(x: panel.minX, y: panel.minY), endPoint: CGPoint(x: panel.maxX, y: panel.maxY)))
            g.stroke(Path(panel), with: .color(.white.opacity(0.5)), lineWidth: max(0.5, u * 0.04))
        }
        g.fill(Path(CGRect(x: -u * 0.5, y: -u * 0.05, width: u, height: u * 0.1)), with: .color(Color(hex: "#CBD5E1")))
        g.stroke(Path(ellipseIn: CGRect(x: -u * 0.45, y: -u * 0.45, width: u * 0.9, height: u * 0.9)),
                 with: .color(Color(hex: "#E2E8F0")), lineWidth: max(0.8, u * 0.12))
        g.fill(Path(ellipseIn: CGRect(x: -u * 0.22, y: -u * 0.22, width: u * 0.44, height: u * 0.44)), with: .color(Color(hex: "#F8FAFC")))
        g.fill(Path(ellipseIn: CGRect(x: -u * 0.08, y: -u * 0.08, width: u * 0.16, height: u * 0.16)), with: .color(Color(hex: "#F43F5E")))
    }

    private static func satellite(_ g: inout GraphicsContext, _ u: CGFloat) {
        g.rotate(by: .degrees(-25))
        for side in [-1.0, 1.0] {
            let panel = CGRect(x: side < 0 ? -u * 1.2 : u * 0.4, y: -u * 0.22, width: u * 0.8, height: u * 0.44)
            g.fill(Path(panel), with: .color(Color(hex: "#3B82F6")))
        }
        g.fill(Path(roundedRect: CGRect(x: -u * 0.35, y: -u * 0.3, width: u * 0.7, height: u * 0.6), cornerRadius: u * 0.1),
               with: .color(Color(hex: "#FBBF24")))
        var dish = Path()
        dish.addArc(center: CGPoint(x: 0, y: -u * 0.55), radius: u * 0.3, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
        g.stroke(dish, with: .color(Color(hex: "#E5E7EB")), lineWidth: max(0.8, u * 0.1))
    }

    private static func shuttle(_ g: inout GraphicsContext, _ u: CGFloat) {
        var wing = Path()
        wing.move(to: CGPoint(x: u * 0.2, y: 0)); wing.addLine(to: CGPoint(x: -u * 0.8, y: -u * 0.8))
        wing.addLine(to: CGPoint(x: -u * 0.9, y: u * 0.8)); wing.closeSubpath()
        g.fill(wing, with: .color(Color(hex: "#CBD5E1")))
        g.fill(Path(roundedRect: CGRect(x: -u * 1.0, y: -u * 0.24, width: u * 2.0, height: u * 0.48), cornerRadius: u * 0.24),
               with: .linearGradient(Gradient(colors: [Color.white, Color(hex: "#E2E8F0")]),
                                     startPoint: CGPoint(x: 0, y: -u * 0.25), endPoint: CGPoint(x: 0, y: u * 0.25)))
        g.fill(Path(roundedRect: CGRect(x: u * 0.55, y: -u * 0.24, width: u * 0.45, height: u * 0.48), cornerRadius: u * 0.24),
               with: .color(Color(hex: "#1F2937")))
        g.fill(Path(ellipseIn: CGRect(x: -u * 1.35, y: -u * 0.15, width: u * 0.4, height: u * 0.3)), with: .color(Color(hex: "#FB923C")))
    }

    private static func comet(_ g: inout GraphicsContext, _ u: CGFloat) {
        var tail = Path()
        tail.move(to: CGPoint(x: 0, y: -u * 0.35))
        tail.addQuadCurve(to: CGPoint(x: -u * 3.2, y: 0), control: CGPoint(x: -u * 1.4, y: -u * 0.4))
        tail.addQuadCurve(to: CGPoint(x: 0, y: u * 0.35), control: CGPoint(x: -u * 1.4, y: u * 0.4))
        g.fill(tail, with: .linearGradient(Gradient(colors: [Color(hex: "#A5F3FC").opacity(0.85), Color(hex: "#A5F3FC").opacity(0)]),
                                           startPoint: .zero, endPoint: CGPoint(x: -u * 3.2, y: 0)))
        g.fill(Path(ellipseIn: CGRect(x: -u * 0.6, y: -u * 0.6, width: u * 1.2, height: u * 1.2)),
               with: .radialGradient(Gradient(colors: [Color.white.opacity(0.9), Color(hex: "#67E8F9").opacity(0)]),
                                     center: .zero, startRadius: 0, endRadius: u * 0.6))
        g.fill(Path(ellipseIn: CGRect(x: -u * 0.26, y: -u * 0.26, width: u * 0.52, height: u * 0.52)), with: .color(.white))
    }
}

// MARK: - Picture planets

extension PlanetPainter {
    private static var imageCache: [String: NSImage] = [:]

    static func bundleImage(_ name: String) -> NSImage? {
        if let img = imageCache[name] { return img }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"), let img = NSImage(contentsOf: url) else {
            return frames(name).first   // animated pictures are stored as name_0.png, name_1.png, …
        }
        imageCache[name] = img
        return img
    }

    private static var frameCache: [String: [NSImage]] = [:]

    /// Frames of an animated picture (from a GIF), or [] for a still one
    static func frames(_ name: String) -> [NSImage] {
        if let f = frameCache[name] { return f }
        var out: [NSImage] = []
        while let url = Bundle.main.url(forResource: "\(name)_\(out.count)", withExtension: "png"), let img = NSImage(contentsOf: url) { out.append(img) }
        frameCache[name] = out
        return out
    }

    /// A picture item (like the pixel UFO): glow, a soft shadow and a gentle bob
    static func drawPicture(_ img: NSImage, p: PlanetDef, ctx: inout GraphicsContext, c: CGPoint, r: CGFloat, phase: Double) {
        let accent = Color(hex: p.accent)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 1.6, y: c.y - r * 1.6, width: r * 3.2, height: r * 3.2)),
                 with: .radialGradient(Gradient(colors: [accent.opacity(0.45), accent.opacity(0)]),
                                       center: c, startRadius: r * 0.3, endRadius: r * 1.6))
        let bob = sin(phase * .pi * 2) * r * 0.08
        // Round "portal" pictures (Level Pass planets) are already planet-shaped
        let side = r * ((p.image ?? "").hasPrefix("lv_") ? 3.5 : 3.3)
        let rect = CGRect(x: c.x - side / 2, y: c.y - side / 2 + bob, width: side, height: side)
        let frames = p.image.map(Self.frames) ?? []
        // Animated pictures play at about 8 frames a second
        let img = frames.isEmpty ? img : frames[Int(Date().timeIntervalSinceReferenceDate * 8) % frames.count]
        guard p.image == "ufo" else {
            ctx.draw(Image(nsImage: img).interpolation(.none), in: rect)
            return
        }
        // Tractor beam (UFO only)
        var beam = Path()
        beam.move(to: CGPoint(x: c.x - r * 0.35, y: c.y + r * 0.25 + bob))
        beam.addLine(to: CGPoint(x: c.x + r * 0.35, y: c.y + r * 0.25 + bob))
        beam.addLine(to: CGPoint(x: c.x + r * 0.7, y: c.y + r * 1.3))
        beam.addLine(to: CGPoint(x: c.x - r * 0.7, y: c.y + r * 1.3))
        beam.closeSubpath()
        ctx.fill(beam, with: .linearGradient(Gradient(colors: [accent.opacity(0.5), accent.opacity(0)]),
                                             startPoint: CGPoint(x: c.x, y: c.y + r * 0.25), endPoint: CGPoint(x: c.x, y: c.y + r * 1.3)))
        ctx.draw(Image(nsImage: img).interpolation(.none), in: rect)
    }
}

// MARK: - Rocket currency icon

/// The rocket currency icon (from Resources/rocket.png in the app bundle)
struct RocketIcon: View {
    var size: CGFloat = 18

    static let image: NSImage? = Bundle.main.url(forResource: "rocket", withExtension: "png").flatMap(NSImage.init(contentsOf:))

    var body: some View {
        Group {
            if let img = Self.image {
                Image(nsImage: img).resizable().interpolation(.none).aspectRatio(contentMode: .fill)
            } else {
                Text("🚀").font(.system(size: size * 0.8))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}
