import Foundation

struct WalletSkinService: Sendable {
    private let zip = ZipArchive()

    func listDevices() async throws -> [DeviceInfo] {
        let helper = try NativeTools.helperURL(named: "device_helper")
        let result = try await ProcessRunner.run(executable: helper, arguments: ["list"], timeout: .seconds(30))
        guard let rows = try NativeTools.jsonObject(from: result.stdoutString) as? [[String: Any]] else {
            throw AirCardError.invalidHelperOutput(result.stdoutString)
        }
        return rows.compactMap { row in
            guard let udid = row["udid"] as? String, !udid.isEmpty else { return nil }
            let product = row["product"] as? String ?? ""
            guard product.hasPrefix("iPhone") else { return nil }
            return DeviceInfo(
                id: udid,
                name: row["name"] as? String ?? "iPhone",
                product: product,
                version: row["version"] as? String ?? "",
                build: row["buildVersion"] as? String ?? ""
            )
        }
    }

    func validateCardHash(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "'\".,"))
        guard trimmed.count == 27 || trimmed.count == 28 || trimmed.count == 43 || trimmed.count == 44 else {
            return nil
        }
        guard trimmed.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+/_-=\"".contains($0)) }) else {
            return nil
        }
        var normalized = trimmed.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while normalized.count % 4 != 0 { normalized.append("=") }
        guard let data = Data(base64Encoded: normalized), data.count == 20 || data.count == 32 else {
            return nil
        }
        return trimmed.count == 27 || trimmed.count == 43 ? "\(trimmed)=" : trimmed
    }

    func extractCardHash(from line: String) -> String? {
        CardHashDetector.detect(in: line)?.hash
    }

    func readCardPass(
        device: DeviceInfo,
        cardHash rawHash: String,
        progress: @escaping @Sendable (String) async -> Void
    ) async throws -> CardPassMetadata {
        let (pass, _) = try await readCardPassPayload(
            device: device,
            cardHash: rawHash,
            progress: progress
        )
        return CardPassMetadata(
            foregroundColor: pass["foregroundColor"] as? String,
            labelColor: pass["labelColor"] as? String
        )
    }

    func writeCardTextColor(
        device: DeviceInfo,
        cardHash rawHash: String,
        color: CardTextColor,
        progress: @escaping @Sendable (String) async -> Void
    ) async throws {
        var (pass, _) = try await readCardPassPayload(
            device: device,
            cardHash: rawHash,
            progress: progress
        )
        pass["foregroundColor"] = color.passValue
        let data = try JSONSerialization.data(
            withJSONObject: pass,
            options: [.prettyPrinted, .sortedKeys]
        )
        let cardHash = try validatedCardHash(rawHash)
        let target = "/var/mobile/Library/Passes/Cards/\(cardHash).pkpass"
        await progress(AirCardL10n.text("Writing only foregroundColor in pass.json…"))
        guard try await writeFiles(
            device: device,
            target: target,
            files: [("pass.json", data)],
            progress: progress
        ) else {
            throw AirCardError.processFailed(AirCardL10n.text("Could not write card pass.json."))
        }
        await progress(AirCardL10n.text("Color sent. Close and reopen Wallet to check numbers."))
    }

    func invalidateCardCache(
        device: DeviceInfo,
        cardHash rawHash: String,
        progress: @escaping @Sendable (String) async -> Void
    ) async throws -> Int {
        let cardHash = try validatedCardHash(rawHash)
        let leaves = ["FrontFace", "PlaceHolder", "Preview"]
        var removedCount = 0

        for suffix in [".cache", ".pkcache"] {
            try Task.checkCancellation()
            let target = "/var/mobile/Library/Passes/Cards/\(cardHash)\(suffix)"
            await progress(AirCardL10n.format("Rebuilding Wallet cache: %@…", suffix))
            removedCount += try await removeCachedFiles(
                device: device,
                target: target,
                leaves: leaves,
                progress: progress
            )
        }
        return removedCount
    }

    func flash(
        device: DeviceInfo,
        cardHash rawHash: String,
        artwork: PreparedArtwork,
        progress: @escaping @Sendable (String) async -> Void
    ) async throws -> FlashResult {
        guard let cardHash = validateCardHash(rawHash) else {
            throw AirCardError.invalidCardHash
        }
        try Task.checkCancellation()

        let assets = Self.artworkFiles(artwork)
        let cardTarget = "/var/mobile/Library/Passes/Cards/\(cardHash).pkpass"
        await progress(AirCardL10n.text("Writing canonical Wallet assets (cardBackgroundCombined, diffuse, background, and strip)…"))

        await progress(AirCardL10n.text("Unlock iPhone and open Apple Books once before continuing…"))
        await progress(AirCardL10n.text("Preparing atomic card write…"))
        var artworkWritten = false
        do {
            artworkWritten = try await writeBatch(
                device: device,
                target: cardTarget,
                files: assets,
                progress: progress
            )
        } catch AirCardError.airTrafficUnavailable {
            throw AirCardError.airTrafficUnavailable
        } catch {
            await progress(AirCardL10n.text("Artwork batch failed; trying individual writes…"))
        }
        if !artworkWritten {
            var individualWritesSucceeded = true
            for asset in assets {
                try Task.checkCancellation()
                let wrote = try await writeBatch(
                    device: device,
                    target: cardTarget,
                    files: [asset],
                    progress: progress
                )
                if !wrote {
                    individualWritesSucceeded = false
                    break
                }
            }
            artworkWritten = individualWritesSucceeded
        }
        guard artworkWritten else {
            throw AirCardError.processFailed(AirCardL10n.text("Could not write card artwork."))
        }

        var cacheFilesRemoved = 0
        do {
            cacheFilesRemoved = try await invalidateCardCache(
                device: device,
                cardHash: cardHash,
                progress: progress
            )
            await progress(AirCardL10n.format("Wallet cache removed: %d files moved for regeneration.", cacheFilesRemoved))
        } catch {
            // Like the reference client, cache invalidation is best-effort;
            // the artwork write remains the success criterion.
            await progress(AirCardL10n.format("Could not complete full cache cleanup; artwork was written. %@", error.localizedDescription))
        }

        await progress(AirCardL10n.text("Skin written. Close and reopen Wallet on iPhone."))
        return FlashResult(cardHash: cardHash, artworkFiles: assets.count, cacheFiles: cacheFilesRemoved)
    }

    private func readCardPassPayload(
        device: DeviceInfo,
        cardHash rawHash: String,
        progress: @escaping @Sendable (String) async -> Void
    ) async throws -> ([String: Any], Data) {
        let cardHash = try validatedCardHash(rawHash)
        let path = "/var/mobile/Library/Passes/Cards/\(cardHash).pkpass/pass.json"
        await progress(AirCardL10n.text("Reading card pass.json…"))
        let result = try await native(device: device, arguments: ["read-file", path])
        guard result["ok"] as? Bool == true,
              let encoded = result["dataBase64"] as? String,
              let data = Data(base64Encoded: encoded) else {
            let message = result["error"] as? String ?? AirCardL10n.text("pass.json is not available through AFC.")
            throw AirCardError.processFailed(message)
        }
        guard var pass = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AirCardError.processFailed(AirCardL10n.text("Card pass.json does not contain a valid JSON object."))
        }
        // Force a mutable copy before callers update foregroundColor.
        pass = Dictionary(uniqueKeysWithValues: pass.map { ($0.key, $0.value) })
        return (pass, data)
    }

    private func validatedCardHash(_ rawHash: String) throws -> String {
        guard let cardHash = validateCardHash(rawHash) else {
            throw AirCardError.invalidCardHash
        }
        return cardHash
    }

    static func artworkFiles(_ artwork: PreparedArtwork) -> [(String, Data)] {
        [
            ("cardBackgroundCombined@3x.png", artwork.png),
            ("diffuse@3x.png", artwork.png),
            ("background@3x.png", artwork.png),
            ("strip@3x.png", artwork.png),
            ("cardBackgroundCombined@2x.png", artwork.png2x),
            ("diffuse@2x.png", artwork.png2x),
            ("background@2x.png", artwork.png2x),
            ("strip@2x.png", artwork.png2x),
            ("cardBackgroundCombined.pdf", artwork.pdf),
            ("background.pdf", artwork.pdf),
            ("strip.pdf", artwork.pdf)
        ]
    }

    func writeFiles(
        device: DeviceInfo,
        target: String,
        files: [(String, Data)],
        progress: @escaping @Sendable (String) async -> Void
    ) async throws -> Bool {
        guard !files.isEmpty else { return true }
        if try await writeBatch(device: device, target: target, files: files, progress: progress) {
            return true
        }

        await progress(AirCardL10n.text("Batch failed; writing keys individually…"))
        for file in files {
            try Task.checkCancellation()
            guard try await writeBatch(
                device: device,
                target: target,
                files: [file],
                progress: progress
            ) else { return false }
        }
        return true
    }

    private func writeBatch(
        device: DeviceInfo,
        target: String,
        files: [(String, Data)],
        progress: @escaping @Sendable (String) async -> Void
    ) async throws -> Bool {
        var lastError: Error?
        for attempt in 1...3 {
            do {
                let succeeded = try await writeBatchAttempt(
                    device: device,
                    target: target,
                    files: files,
                    progress: progress
                )
                if succeeded { return true }
            } catch is CancellationError {
                throw CancellationError()
            } catch AirCardError.airTrafficUnavailable {
                throw AirCardError.airTrafficUnavailable
            } catch {
                lastError = error
            }

            if attempt < 3 {
                await progress(AirCardL10n.format("Retrying write %d/3…", attempt + 1))
                try await Task.sleep(for: .milliseconds(400 * attempt))
            }
        }
        if let lastError { throw lastError }
        return false
    }

    private func writeBatchAttempt(
        device: DeviceInfo,
        target: String,
        files: [(String, Data)],
        progress: @escaping @Sendable (String) async -> Void
    ) async throws -> Bool {
        let token = randomToken()
        let source = "airlift-src-\(token)"
        let link = "airlift-link-\(token)"
        let recovered = "airlift-recovered-\(token)"

        let work = try NativeTools.temporaryDirectory(prefix: "aircard-write")
        defer { try? FileManager.default.removeItem(at: work) }
        let archiveURL = work.appendingPathComponent("payload.zip")
        let booksURL = work.appendingPathComponent("Books.plist")
        let snapshotURL = work.appendingPathComponent("books-snapshot", isDirectory: true)
        try FileManager.default.createDirectory(at: snapshotURL, withIntermediateDirectories: true)

        let archive = try zip.build(target: target, files: files)
        try archive.write(to: archiveURL, options: .atomic)

        let identifiers = ["../../\(source)/p0/p1/p2/link"]
            + files.indices.map { "../../\(source)/payload_\($0)" }
        let books = try PropertyListSerialization.data(
            fromPropertyList: [
                "Books": identifiers.enumerated().map { index, identifier in
                    ["Persistent ID": identifier, "Item ID": "\(index + 1)", "DSID": "1"]
                }
            ],
            format: .binary,
            options: 0
        )
        try books.write(to: booksURL, options: .atomic)

        await progress(AirCardL10n.text("Preserving Books state…"))
        let snapshot = try await native(device: device, arguments: ["snapshot-books", snapshotURL.path])
        await progress(AirCardL10n.format("Books snapshot: %@", diagnostic(snapshot)))
        guard operationOK(snapshot) else { return false }
        let stage = try await native(
            device: device,
            arguments: ["stage", source, link, recovered, archiveURL.path, booksURL.path, snapshotURL.path]
        )
        await progress(AirCardL10n.format("Stage: %@", diagnostic(stage)))
        guard operationOK(stage) else { return false }

        await progress(AirCardL10n.text("Sending assets to iPhone…"))
        var atcArguments = [device.id]
        let destinations = [link] + files.map { "\(link)/\($0.0)" }
        for (identifier, destination) in Swift.zip(identifiers, destinations) {
            atcArguments.append(contentsOf: [identifier, destination])
        }
        let atc = try await nativeAirTraffic(arguments: atcArguments)
        await progress(AirCardL10n.format("AirTraffic: %@", diagnostic(atc)))

        await progress(AirCardL10n.text("Cleaning temporary area and restoring Books…"))
        let finish = try await native(
            device: device,
            arguments: ["finish-write", source, link, recovered, snapshotURL.path]
        )
        await progress(AirCardL10n.format("Cleanup: %@", diagnostic(finish)))
        if Self.isHandshakeFailure(atc) {
            throw AirCardError.airTrafficUnavailable
        }
        return atc["ok"] as? Bool == true && operationOK(finish)
    }

    private func removeCachedFiles(
        device: DeviceInfo,
        target: String,
        leaves: [String],
        progress: @escaping @Sendable (String) async -> Void
    ) async throws -> Int {
        guard !leaves.isEmpty,
              leaves.allSatisfy({ !$0.isEmpty && !$0.contains("/") && $0 != "." && $0 != ".." }) else {
            throw AirCardError.processFailed(AirCardL10n.text("Unsafe cache names."))
        }

        var lastFailure: Error?
        for attempt in 1...3 {
            try Task.checkCancellation()
            let token = randomToken()
            let source = "airlift-src-\(token)"
            let link = "airlift-link-\(token)"
            let recovered = "airlift-recovered-\(token)"
            let linkIdentifier = "../../\(source)/p0/p1/p2/link"
            let protectedIdentifiers = leaves.map { "../../\(link)/\($0)" }
            let removedDestinations = leaves.indices.map { "\(source)/removed-\($0)" }

            let work = try NativeTools.temporaryDirectory(prefix: "aircard-cache")
            defer { try? FileManager.default.removeItem(at: work) }
            let archiveURL = work.appendingPathComponent("payload.zip")
            let booksURL = work.appendingPathComponent("Books.plist")
            let snapshotURL = work.appendingPathComponent("books-snapshot", isDirectory: true)
            try FileManager.default.createDirectory(at: snapshotURL, withIntermediateDirectories: true)

            let archive = try zip.build(target: target, files: [("payload", Data("aircard-v2".utf8))])
            try archive.write(to: archiveURL, options: .atomic)
            let identifiers = [linkIdentifier] + protectedIdentifiers
            let books = try PropertyListSerialization.data(
                fromPropertyList: [
                    "Books": identifiers.enumerated().map { index, identifier in
                        ["Persistent ID": identifier, "Item ID": "\(index + 1)", "DSID": "1"]
                    }
                ],
                format: .binary,
                options: 0
            )
            try books.write(to: booksURL, options: .atomic)

            let snapshot = try await native(device: device, arguments: ["snapshot-books", snapshotURL.path])
            guard operationOK(snapshot) else {
                lastFailure = AirCardError.processFailed(AirCardL10n.text("Could not preserve Books before cleaning cache."))
                if attempt < 3 { try await Task.sleep(for: .milliseconds(400 * attempt)) }
                continue
            }
            let stage = try await native(
                device: device,
                arguments: ["stage", source, link, recovered, archiveURL.path, booksURL.path, snapshotURL.path]
            )
            guard operationOK(stage) else {
                lastFailure = AirCardError.processFailed(AirCardL10n.format("The helper could not prepare cleanup for %@.", URL(fileURLWithPath: target).pathExtension))
                if attempt < 3 { try await Task.sleep(for: .milliseconds(400 * attempt)) }
                continue
            }

            var atcArguments = [device.id, linkIdentifier, link]
            for (identifier, destination) in Swift.zip(protectedIdentifiers, removedDestinations) {
                atcArguments.append(contentsOf: [identifier, destination])
            }

            do {
                let atc = try await nativeAirTraffic(arguments: atcArguments)
                guard atc["ok"] as? Bool == true, atc["processExitCode"] as? Int == 0 else {
                    _ = try? await native(
                        device: device,
                        arguments: ["finish-write", source, link, recovered, snapshotURL.path]
                    )
                    lastFailure = AirCardError.processFailed(AirCardL10n.text("AirTraffic could not move cache files."))
                    if attempt < 3 { try await Task.sleep(for: .milliseconds(400 * attempt)) }
                    continue
                }

                let finish = try await native(
                    device: device,
                    arguments: ["finish-moved-removal", source, link, recovered, snapshotURL.path, "\(leaves.count)"]
                )
                guard operationOK(finish) else {
                    lastFailure = AirCardError.processFailed(AirCardL10n.text("Cache deletion or Books restoration was not completed."))
                    if attempt < 3 { try await Task.sleep(for: .milliseconds(400 * attempt)) }
                    continue
                }
                let operation = finish["operation"] as? [String: Any]
                return operation?["movedCount"] as? Int ?? leaves.count
            } catch {
                _ = try? await native(
                    device: device,
                    arguments: ["finish-write", source, link, recovered, snapshotURL.path]
                )
                lastFailure = error
                if attempt < 3 { try await Task.sleep(for: .milliseconds(400 * attempt)) }
            }
        }
        throw lastFailure ?? AirCardError.processFailed(AirCardL10n.text("Could not delete Wallet cache."))
    }

    private func native(device: DeviceInfo, arguments: [String]) async throws -> [String: Any] {
        let helper = try NativeTools.helperURL(named: "device_helper")
        guard let command = arguments.first else {
            throw AirCardError.invalidHelperOutput("empty native command")
        }
        let helperArguments = [command, device.id] + Array(arguments.dropFirst())
        let result = try await ProcessRunner.run(
            executable: helper,
            arguments: helperArguments,
            timeout: .seconds(90)
        )
        guard let object = try? NativeTools.jsonObject(from: result.stdoutString) as? [String: Any] else {
            let stdout = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
            let stderr = result.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AirCardError.invalidHelperOutput(
                "status=\(result.status), stdout=\(stdout.isEmpty ? "<empty>" : stdout), stderr=\(stderr.isEmpty ? "<empty>" : stderr)"
            )
        }
        return object
    }

    private func nativeAirTraffic(arguments: [String]) async throws -> [String: Any] {
        let helper = try NativeTools.helperURL(named: "airtraffic_host")
        let assetCount = (arguments.count - 1) / 2
        let result = try await ProcessRunner.run(
            executable: helper,
            arguments: arguments,
            timeout: .seconds(max(60, assetCount * 2) + 15)
        )
        guard var object = try? NativeTools.jsonObject(from: result.stdoutString) as? [String: Any] else {
            let stdout = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
            let stderr = result.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AirCardError.invalidHelperOutput(
                "status=\(result.status), stdout=\(stdout.isEmpty ? "<empty>" : stdout), stderr=\(stderr.isEmpty ? "<empty>" : stderr)"
            )
        }
        object["processExitCode"] = Int(result.status)
        return object
    }

    private static func isHandshakeFailure(_ result: [String: Any]) -> Bool {
        guard result["ok"] as? Bool != true, let error = result["error"] as? String else { return false }
        return ["timeout", "SyncAllowed not observed", "ReadyForSync not observed"].contains(error)
    }

    private func operationOK(_ result: [String: Any]) -> Bool {
        let targetGatePassed = result["targetGatePassed"] as? Bool ?? false
        let operation = result["operation"] as? [String: Any]
        return targetGatePassed && operation?["ok"] as? Bool == true
    }

    private func diagnostic(_ result: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "resultado no serializable"
        }
        return text
    }

    private func randomToken() -> String {
        // The native helper validates exactly 20 lowercase hex characters,
        // matching Python's secrets.token_hex(10) in the reference port.
        (0..<10).map { _ in String(format: "%02x", Int.random(in: 0...255)) }.joined()
    }
}
