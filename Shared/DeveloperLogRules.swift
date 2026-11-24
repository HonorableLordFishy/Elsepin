import Foundation

/// Fixed recording windows, not a rolling history. Expired data is removed on
/// the next opportunity to run; iOS cannot run cleanup in a terminated app.
struct DeveloperLogWindow: Codable, Equatable {
    static let duration: TimeInterval = 48 * 60 * 60
    let startedAt: Date
    var endsAt: Date { startedAt.addingTimeInterval(Self.duration) }
    func needsReset(at now: Date) -> Bool { now >= endsAt || now < startedAt }
    func currentBatchStart(at now: Date) -> Date {
        guard now >= startedAt else { return now }
        let batches = floor(now.timeIntervalSince(startedAt) / Self.duration)
        return startedAt.addingTimeInterval(batches * Self.duration)
    }
}

struct DeveloperLogEvent: Codable {
    let time: Date
    let timeMilliseconds: Double
    let uptime: TimeInterval
    let process: String
    let event: String
    let details: [String: String]

    /// Only known high-frequency successes can wait. Unknown events, failures,
    /// user markers, and lifecycle/Stop events always flush immediately.
    var canBatch: Bool {
        switch event {
        case "location_write_requested", "live_activity_update_requested", "live_activity_update_finished": return true
        case "touch_began", "touch_ended", "system_report_part": return true
        case "developer_endpoint_check": return details["reachable"] == "true"
        case "energy_snapshot": return details["reason"] == "interval"
        case "location_write_result": return details["result"] == "accepted"
        default: return false
        }
    }

    init(time: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime,
         process: String, event: String, details: [String: String] = [:]) {
        self.time = time
        self.timeMilliseconds = time.timeIntervalSince1970 * 1000
        self.uptime = uptime
        self.process = process
        self.event = String(event.prefix(100))
        let details = PairingNotificationLog.safeDetails(for: self.event, details: details)
        // Callers supply only app-owned events, never arbitrary request bodies,
        // view text, keyboard input, pairing files, or credential dictionaries.
        self.details = Dictionary(uniqueKeysWithValues: details.keys.sorted().prefix(24).compactMap { key in
            let lower = key.lowercased()
            guard key.count <= 80, !["password", "token", "secret", "pairing", "credential", "authorization", "cookie"].contains(where: lower.contains) else { return nil }
            return (key, String((details[key] ?? "").prefix(1200)))
        })
    }
}

enum PairingNotificationLog {
    private static let identifierBytes = Data(PairingPINNotification.legacyIdentifier.utf8)
    private static let notificationEventBytes = Data("\"notification_".utf8)
    private static let unicodeEscapeBytes = Data("\\u".utf8)

    static func safeDetails(for event: String, details: [String: String]) -> [String: String] {
        guard event.hasPrefix("notification_"), let id = details["id"],
              PairingPINNotification.matches(id) else { return details }
        var metadata = ["id": id]
        if let result = details["result"], ["accepted_by_iOS_not_proof_seen", "failed"].contains(result) {
            metadata["result"] = result
        }
        if let scheduled = details["scheduled"], ["true", "false"].contains(scheduled) {
            metadata["scheduled"] = scheduled
        }
        if let action = details["action"],
           ["com.apple.UNNotificationDefaultActionIdentifier", "com.apple.UNNotificationDismissActionIdentifier"].contains(action) {
            metadata["action"] = action
        }
        return metadata
    }

    static func exportLine(_ line: Data, parsed: [String: Any]? = nil) -> Data? {
        let object: [String: Any]
        if let parsed {
            object = parsed
        } else {
            // The recorder writes ASCII identifiers literally. Also recognize
            // Unicode escapes in JSON notification records before exporting.
            let containsIdentifier = line.range(of: identifierBytes) != nil
            let isEscapedNotification = line.range(of: unicodeEscapeBytes) != nil && line.range(of: notificationEventBytes) != nil
            guard containsIdentifier || isEscapedNotification else { return line }
            guard let decoded = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return nil }
            object = decoded
        }
        guard let event = object["event"] as? String else {
            return line.range(of: identifierBytes) == nil ? line : nil
        }
        guard event.hasPrefix("notification_") else { return line }
        guard let details = object["details"] as? [String: Any], let id = details["id"] as? String else {
            return line.range(of: identifierBytes) == nil ? line : nil
        }
        guard PairingPINNotification.matches(id) else { return line }

        let strings = details.compactMapValues { $0 as? String }
        let metadata = safeDetails(for: event, details: strings)
        guard metadata != strings || details.count != strings.count else { return line }
        var redacted = object
        redacted["details"] = metadata
        return try? JSONSerialization.data(withJSONObject: redacted, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    static func appendExportRecords(_ records: Data, to output: inout Data) {
        guard records.range(of: identifierBytes) != nil || records.range(of: unicodeEscapeBytes) != nil else {
            output.append(records)
            return
        }
        var start = records.startIndex
        while start < records.endIndex {
            let newline = records[start...].firstIndex(of: 0x0A)
            let end = newline ?? records.endIndex
            if let line = exportLine(records[start..<end]) {
                output.append(line)
                if newline != nil { output.append(0x0A) }
            }
            start = newline == nil ? end : records.index(after: end)
        }
    }
}

enum SessionFailureRules {
    /// A failure before issuing a set cannot create a new simulated location.
    /// Earlier accepted/uncertain writes must still be cleared explicitly.
    static func needsClear(previousLocationMayRemain: Bool, failedBeforeWrite: Bool) -> Bool {
        previousLocationMayRemain || !failedBeforeWrite
    }
}
