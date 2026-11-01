import Foundation

extension RouterAPI {
    // MARK: Reboot / LEDs

    public func reboot() async throws {
        _ = try await request(.POST, "/cgi-bin/Reboot", query: [:], body: nil)
    }

    public func ledsOn() async throws -> Bool {
        try await get("/cgi-bin/LEDStatus")["isactive"].bool
    }

    public func setLEDs(_ on: Bool) async throws {
        _ = try await request(.PUT, "/cgi-bin/LEDStatus", query: [:], body: ["status": .bool(on)])
    }

    // MARK: Backup / restore / firmware

    /// The router's config file, as opaque bytes.
    public func backupConfig() async throws -> Data {
        try await download("/cgi-bin/Backup_Restore?action=Backup")
    }

    /// Max accepted size for "firmware" or "config" uploads.
    public func maxUploadSize(_ kind: String) async throws -> Int {
        let j = try await get("/cgi-bin/GetMTDSize?from=\(kind)")
        return (j.array.first ?? j)["CompareSize"].int ?? 0
    }

    /// Uploads a config file. The router applies it and reboots.
    public func restoreConfig(_ data: Data, fileName: String) async throws {
        do {
            _ = try await upload("/cgi-bin/Backup_Restore?action=Restore", field: "mtenRestoreCfg", fileName: fileName, data: data)
        } catch RouterError.http(400, _) {
            throw RouterError.badResponse("The router rejected this file as a configuration backup.")
        }
    }

    /// Uploads a firmware image. On success the router flashes it and reboots.
    public func upgradeFirmware(_ data: Data, fileName: String) async throws {
        do {
            _ = try await upload("/cgi-bin/Firmware_Upgrade", field: "filename", fileName: fileName, data: data)
        } catch RouterError.http(let code, let body) {
            let reason: String
            if body.contains("ZCFG_INVALID_IMAGE") { reason = "Not a valid firmware image for this router." }
            else if body.contains("ZCFG_INVALID_PARAM_VALUE") { reason = "Downgrades are blocked by this firmware." }
            else if body.contains("ZCFG_REQUEST_POSTPONED") { reason = "This image needs a factory reset to install; use the stock web UI for that." }
            else if body.contains("ZCFG_INVALID_FORMAT") { reason = "Invalid image format. The router may need a reboot." }
            else { reason = "Upload failed (HTTP \(code))." }
            throw RouterError.badResponse(reason)
        }
    }

    /// Polls until the router's web server answers again after a reboot (or `timeout`).
    public func waitUntilBack(timeout: Duration = .seconds(600), progress: (@Sendable (Duration) -> Void)? = nil) async -> Bool {
        let start = ContinuousClock.now
        try? await Task.sleep(for: .seconds(15))
        while ContinuousClock.now - start < timeout {
            progress?(ContinuousClock.now - start)
            if await isReachable() { return true }
            try? await Task.sleep(for: .seconds(5))
        }
        return false
    }

    // MARK: Account

    /// Changes the logged-in account's password. The router ends the session afterwards.
    public func changePassword(account: String, old: String, new: String) async throws {
        guard let me = try await dal("user_account").first(where: { $0["Username"].str == account }) else {
            throw RouterError.badResponse("Account \(account) not found")
        }
        let idx = me["Index"].str
        var o = try await dal("user_account", query: ["DalGetOneObject": "y", "Index": idx]).first ?? me
        o["Index"] = .string(idx)
        o["oldPw"] = .string(old)
        o["Password"] = .string(new)
        o["verifyNewpassword"] = .string(new)
        try await dalWrite(.PUT, oid: "user_account", o, query: ["timedelay": "1"])
    }

    public static func passwordProblems(_ pw: String) -> [String] {
        var p: [String] = []
        if !(6...64).contains(pw.count) { p.append("6–64 characters") }
        if pw.rangeOfCharacter(from: .letters) == nil { p.append("at least one letter") }
        if pw.rangeOfCharacter(from: .decimalDigits) == nil { p.append("at least one digit") }
        return p
    }
}
