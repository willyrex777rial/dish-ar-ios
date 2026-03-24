import Foundation
// In a real iOS project you would add the supabase-swift SDK using Swift Package Manager
// https://github.com/supabase/supabase-swift
import Supabase

class SupabaseManager {
    // These keys match the ones provided in the requirements
    private let supabaseUrl = URL(string: "https://cuitufybalbulzzocdvu.supabase.co")!
    private let supabaseKey = "sb_publishable_R80xfd7LVW_ngq0BY4j5-Q_M2is8YIs" // Using publishable key for client
    
    private let client: SupabaseClient
    
    init() {
        self.client = SupabaseClient(supabaseURL: supabaseUrl, supabaseKey: supabaseKey)
    }
    
    func uploadModel(fileUrl: URL, path: String) async throws {
        // Assume file is small enough to upload into memory directly, 
        // otherwise would need to upload via streams or chunks
        let fileData = try Data(contentsOf: fileUrl)
        
        try await client.storage
            .from("models")
            .upload(
                path: path,
                file: fileData,
                options: FileOptions(
                    cacheControl: "3600",
                    contentType: "model/vnd.usdz+zip"
                )
            )
    }
    
    func saveDish(name: String, usdzUrl: String) async throws -> String {
        // Define struct to match table schema
        struct DishInsert: Codable {
            let name: String
            let usdz_url: String
        }
        
        struct DishResponse: Codable {
            let id: String
        }
        
        let dishInsert = DishInsert(name: name, usdz_url: usdzUrl)
        
        // Insert record and request the inserted row back
        let response: [DishResponse] = try await client.database
            .from("dishes")
            .insert(dishInsert)
            .select("id")
            .execute()
            .value
            
        guard let id = response.first?.id else {
            throw NSError(domain: "SupabaseManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse inserted dish ID"])
        }
        
        // Construct the frontend URL that will be encoded into the QR code
        let hostUrl = "https://yourapp.vercel.app"
        return "\(hostUrl)/dish/\(id)"
    }
}
