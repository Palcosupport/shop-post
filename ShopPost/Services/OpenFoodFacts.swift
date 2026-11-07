import Foundation

/// Información nutricional de Open Food Facts (base de datos abierta, por código de barras).
struct FoodFacts: Decodable, Sendable {
    let productName: String?
    let brands: String?
    let imageURL: String?
    let nutriscore: String?
    let novaGroup: Int?
    let ingredients: String?
    let allergens: String?
    let quantity: String?
    let nutriments: [String: Double]

    enum CodingKeys: String, CodingKey {
        case productName = "product_name", brands, imageURL = "image_front_url", nutriscore = "nutriscore_grade",
             novaGroup = "nova_group", ingredients = "ingredients_text_es", allergens = "allergens_from_ingredients",
             quantity, nutriments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        productName = try? c.decode(String.self, forKey: .productName)
        brands = try? c.decode(String.self, forKey: .brands)
        imageURL = try? c.decode(String.self, forKey: .imageURL)
        nutriscore = (try? c.decode(String.self, forKey: .nutriscore)).flatMap { ["a", "b", "c", "d", "e"].contains($0) ? $0 : nil }
        novaGroup = try? c.decode(Int.self, forKey: .novaGroup)
        ingredients = try? c.decode(String.self, forKey: .ingredients)
        allergens = try? c.decode(String.self, forKey: .allergens)
        quantity = try? c.decode(String.self, forKey: .quantity)
        var n: [String: Double] = [:]
        if let raw = try? c.decode([String: FlexibleNumber].self, forKey: .nutriments) {
            for (k, v) in raw { if let d = v.value { n[k] = d } }
        }
        nutriments = n
    }

    struct FlexibleNumber: Decodable {
        let value: Double?
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let d = try? c.decode(Double.self) { value = d } else if let s = try? c.decode(String.self) { value = Double(s) } else { value = nil }
        }
    }

    var displayNutrients: [(String, String)] {
        let rows: [(String, String, String)] = [
            ("Energía", "energy-kcal_100g", "kcal"), ("Grasas", "fat_100g", "g"), ("Saturadas", "saturated-fat_100g", "g"),
            ("Hidratos", "carbohydrates_100g", "g"), ("Azúcares", "sugars_100g", "g"), ("Proteínas", "proteins_100g", "g"),
            ("Sal", "salt_100g", "g"),
        ]
        return rows.compactMap { label, key, unit in
            nutriments[key].map { (label, String(format: $0 >= 10 ? "%.0f %@" : "%.1f %@", $0, unit)) }
        }
    }
}

enum OpenFoodFacts {
    static func lookup(ean: String) async -> FoodFacts? {
        let code = ean.filter(\.isNumber)
        guard !code.isEmpty,
              let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=product_name,brands,image_front_url,nutriscore_grade,nova_group,ingredients_text_es,allergens_from_ingredients,quantity,nutriments&lc=es")
        else { return nil }
        var req = URLRequest(url: url)
        req.setValue("ShopPost/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        struct Response: Decodable { let status: Int?; let product: FoodFacts? }
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let r = try? JSONDecoder().decode(Response.self, from: data), r.status == 1 else { return nil }
        return r.product
    }
}
