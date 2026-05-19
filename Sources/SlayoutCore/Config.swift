import Foundation
import TOMLKit

public enum HyperTrigger: String, Equatable, Sendable {
    case capsLock = "caps_lock"
    case rightCmd = "right_cmd"
    case rightOption = "right_option"
    case f19
}

public enum WindowAction: Equatable, Sendable {
    case fullscreen
    case leftHalf, rightHalf, topHalf, bottomHalf
    case leftTwoThirds, middleTwoThirds, rightTwoThirds
    case leftThird, middleThird, rightThird
    case center
    case screen(String)
}

public struct MetaBindings: Equatable, Sendable {
    public var record: String?
    public var restoreLast: String?
    public var reload: String?

    public init(record: String? = nil, restoreLast: String? = nil, reload: String? = nil) {
        self.record = record
        self.restoreLast = restoreLast
        self.reload = reload
    }
}

public struct Config: Equatable, Sendable {
    public var hyperTrigger: HyperTrigger
    public var apps: [String: String]
    public var windows: [String: WindowAction]
    public var meta: MetaBindings

    public init(
        hyperTrigger: HyperTrigger = .capsLock,
        apps: [String: String] = [:],
        windows: [String: WindowAction] = [:],
        meta: MetaBindings = MetaBindings()
    ) {
        self.hyperTrigger = hyperTrigger
        self.apps = apps
        self.windows = windows
        self.meta = meta
    }

    public static let `default` = Config()
}

public enum ConfigError: Error, Equatable {
    case parseError(String)
    case unknownTrigger(String)
    case unknownAction(String)
    case wrongType(String)
}

/// Result of a resilient config parse: the (possibly partial) config plus a
/// list of human-readable warnings for individual entries that were skipped.
public struct ConfigParseResult: Equatable, Sendable {
    public var config: Config
    public var warnings: [String]
    public init(config: Config, warnings: [String]) {
        self.config = config
        self.warnings = warnings
    }
}

public enum ConfigLoader {
    /// Throws on structural TOML errors. Per-entry errors are returned as warnings
    /// so a single bad line doesn't blow away the whole config.
    public static func parseResilient(_ source: String) throws -> ConfigParseResult {
        let table: TOMLTable
        do {
            table = try TOMLTable(string: source)
        } catch {
            throw ConfigError.parseError(String(describing: error))
        }

        var config = Config()
        var warnings: [String] = []

        if let hyper = table["hyper"]?.table, let trigger = hyper["trigger"] {
            if let raw = trigger.string {
                if let parsed = HyperTrigger(rawValue: raw) {
                    config.hyperTrigger = parsed
                } else {
                    warnings.append("hyper.trigger: unknown trigger \"\(raw)\" — keeping default (caps_lock)")
                }
            } else {
                warnings.append("hyper.trigger must be a string — keeping default")
            }
        }

        if let apps = table["apps"]?.table {
            for (key, value) in apps {
                guard let name = value.string else {
                    warnings.append("apps.\(key): value must be a string — skipped")
                    continue
                }
                config.apps[normalizeKey(key)] = name
            }
        }

        if let windows = table["window"]?.table {
            for (key, value) in windows {
                guard let raw = value.string else {
                    warnings.append("window.\(key): value must be a string — skipped")
                    continue
                }
                do {
                    config.windows[normalizeKey(key)] = try parseWindowAction(raw)
                } catch {
                    warnings.append("window.\(key) = \"\(raw)\": unknown action — skipped")
                }
            }
        }

        if let meta = table["meta"]?.table {
            if let v = meta["record"]?.string { config.meta.record = normalizeKey(v) }
            if let v = meta["restore_last"]?.string { config.meta.restoreLast = normalizeKey(v) }
            if let v = meta["reload"]?.string { config.meta.reload = normalizeKey(v) }
        }

        return ConfigParseResult(config: config, warnings: warnings)
    }

    /// Strict parse that throws on the first per-entry error. Retained for
    /// existing callers and tests that want strict semantics.
    public static func parse(_ source: String) throws -> Config {
        let table: TOMLTable
        do {
            table = try TOMLTable(string: source)
        } catch {
            throw ConfigError.parseError(String(describing: error))
        }

        var config = Config()

        if let hyper = table["hyper"]?.table {
            if let trigger = hyper["trigger"] {
                guard let raw = trigger.string else {
                    throw ConfigError.wrongType("hyper.trigger must be a string")
                }
                guard let parsed = HyperTrigger(rawValue: raw) else {
                    throw ConfigError.unknownTrigger(raw)
                }
                config.hyperTrigger = parsed
            }
        }

        if let apps = table["apps"]?.table {
            for (key, value) in apps {
                guard let name = value.string else {
                    throw ConfigError.wrongType("apps.\(key) must be a string")
                }
                config.apps[normalizeKey(key)] = name
            }
        }

        if let windows = table["window"]?.table {
            for (key, value) in windows {
                guard let raw = value.string else {
                    throw ConfigError.wrongType("window.\(key) must be a string")
                }
                config.windows[normalizeKey(key)] = try parseWindowAction(raw)
            }
        }

        if let meta = table["meta"]?.table {
            if let v = meta["record"]?.string { config.meta.record = normalizeKey(v) }
            if let v = meta["restore_last"]?.string { config.meta.restoreLast = normalizeKey(v) }
            if let v = meta["reload"]?.string { config.meta.reload = normalizeKey(v) }
        }

        return config
    }

    /// US-keyboard shifted-symbol → unshifted-key aliases. The event tap reports
    /// the unshifted key, so a config entry of `"|"` would never match without
    /// this mapping (the actual keypress is reported as `"\\"`).
    private static let shiftedSymbolAliases: [String: String] = [
        "|": "\\", "?": "/", ":": ";", "\"": "'",
        "<": ",", ">": ".", "~": "`", "{": "[", "}": "]",
        "+": "=", "_": "-",
        "!": "1", "@": "2", "#": "3", "$": "4", "%": "5",
        "^": "6", "&": "7", "*": "8", "(": "9", ")": "0",
    ]

    private static func normalizeKey(_ key: String) -> String {
        let lower = key.lowercased()
        return shiftedSymbolAliases[lower] ?? lower
    }

    private static func parseWindowAction(_ raw: String) throws -> WindowAction {
        if raw.hasPrefix("screen:") {
            let name = String(raw.dropFirst("screen:".count))
            guard !name.isEmpty else { throw ConfigError.unknownAction(raw) }
            return .screen(name)
        }
        switch raw {
        case "fullscreen": return .fullscreen
        case "left-half": return .leftHalf
        case "right-half": return .rightHalf
        case "top-half": return .topHalf
        case "bottom-half": return .bottomHalf
        case "left-two-thirds": return .leftTwoThirds
        case "middle-two-thirds": return .middleTwoThirds
        case "right-two-thirds": return .rightTwoThirds
        case "left-third": return .leftThird
        case "middle-third": return .middleThird
        case "right-third": return .rightThird
        case "center": return .center
        default: throw ConfigError.unknownAction(raw)
        }
    }
}
