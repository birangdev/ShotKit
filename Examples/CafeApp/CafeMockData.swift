import Foundation

// MARK: - CafeApp example — real mock data
//
// [CafeApp](https://github.com/Arashk-A/CafeApp) ships a fixture
// (`CoffeesMock.json`) that its own `Coffee.mock` decodes for previews and
// tests. The JSON below is copied verbatim from that file, and the types
// mirror its models (`Coffee`, `CoffeeType`, `Size`, `Extra`,
// `Subselection`) with the Realm persistence stripped out, so this example's
// views are populated with the app's real sample data rather than
// hand-invented copy.

struct CoffeeMock: Decodable {
    var types: [CoffeeTypeMock]
    var sizes: [SizeMock]
    var extras: [ExtraMock]

    enum CodingKeys: String, CodingKey {
        case types, sizes, extras
    }
}

struct CoffeeTypeMock: Decodable, Identifiable {
    var id: String
    var name: String

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name
    }
}

struct SizeMock: Decodable, Identifiable {
    var id: String
    var name: String

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name
    }
}

struct ExtraMock: Decodable, Identifiable {
    var id: String
    var name: String
    var subselections: [SubselectionMock]

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, subselections
    }

    /// CafeApp's own `Extra.labelText`: the fixture's extras are a sugar
    /// prompt and a milk prompt, told apart by sniffing the name text.
    var labelText: String {
        name.contains("milk") ? "Milk" : "Sugar"
    }
}

struct SubselectionMock: Decodable, Identifiable {
    var id: String
    var name: String

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name
    }
}

enum CafeMock {
    /// Decoded from CafeApp's `CoffeesMock.json`, first (only) entry.
    static let coffee: CoffeeMock = {
        let data = Data(json.utf8)
        return try! JSONDecoder().decode([CoffeeMock].self, from: data)[0]
    }()

    private static let json = """
    [
     {
      "_id": "60ba1ab72e35f2d9c786c610",
      "types": [
       { "_id": "60ba1a062e35f2d9c786c56d", "name": "Ristretto" },
       { "_id": "60be1db3c45ecee5d77ad890", "name": "Espresso" },
       { "_id": "60be1eabc45ecee5d77ad960", "name": "Cappuccino" }
      ],
      "sizes": [
       { "_id": "60ba18d13ca8c43196b5f606", "name": "Large" },
       { "_id": "60ba3368c45ecee5d77a016b", "name": "Venti" },
       { "_id": "60ba33dbc45ecee5d77a01f8", "name": "Tall" }
      ],
      "extras": [
       {
        "_id": "60ba197c2e35f2d9c786c525",
        "name": "Select the amount of sugar",
        "subselections": [
         { "_id": "60ba194dfdd5e192e14eaa75", "name": "A lot" },
         { "_id": "60ba195407e1dc8a4e33b5e5", "name": "Normal" }
        ]
       },
       {
        "_id": "60ba34a0c45ecee5d77a0263",
        "name": "Select type of milk",
        "subselections": [
         { "_id": "611a1adeff35e4db9df19667", "name": "Soy" },
         { "_id": "60ba348d8c75424ac5ed259e", "name": "Oat" },
         { "_id": "60ba349a869d7a04642b41f4", "name": "Cow" }
        ]
       }
      ]
     }
    ]
    """
}
