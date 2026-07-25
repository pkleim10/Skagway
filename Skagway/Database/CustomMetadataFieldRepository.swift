import Foundation
import GRDB

/// Per-library custom metadata field definitions (`custom_metadata_field` table).
struct CustomMetadataFieldRepository {
    let dbPool: DatabasePool

    func fetchAll() throws -> [CustomMetadataFieldDefinition] {
        try dbPool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, name, valueType FROM custom_metadata_field
                    ORDER BY sortOrder ASC, name COLLATE NOCASE ASC
                    """
            )
            return rows.compactMap { row in
                let idString: String = row["id"]
                let name: String = row["name"]
                let typeString: String = row["valueType"]
                guard let id = UUID(uuidString: idString),
                      let valueType = CustomMetadataValueType(rawValue: typeString)
                else { return nil }
                return CustomMetadataFieldDefinition(id: id, name: name, valueType: valueType)
            }
        }
    }

    /// Replaces the entire definition list (order = array order).
    func replaceAll(_ fields: [CustomMetadataFieldDefinition]) throws {
        try dbPool.write { db in
            try db.execute(sql: "DELETE FROM custom_metadata_field")
            for (index, field) in fields.enumerated() {
                try db.execute(
                    sql: """
                        INSERT INTO custom_metadata_field (id, name, valueType, sortOrder)
                        VALUES (?, ?, ?, ?)
                        """,
                    arguments: [field.id.uuidString, field.name, field.valueType.rawValue, index]
                )
            }
        }
    }
}
