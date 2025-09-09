//
//  DCMDictionary.swift
//
//  A lightweight wrapper around the property list used to
//  look up human‑readable names for DICOM tags.
//  The Swift 6 port retains the
//  original semantics while embracing Swift idioms such as
//  singletons and generics.
//
//  The dictionary itself is stored in ``DCMDictionary.plist``
//  which must reside in the main bundle.  The keys in that
//  file are hexadecimal strings corresponding to the 32‑bit
//  tag and the values are two character VR codes followed by
//  a textual description.  The caller is responsible for
//  splitting the VR and description when needed.
//
//  Note: this class does not attempt to verify the contents
//  of the plist; if the file is missing or malformed the
//  dictionary will simply be empty.  Accesses to unknown keys
//  return ``nil`` rather than throwing.
//

import Foundation

/// Singleton facade for looking up DICOM tag descriptions from a
/// bundled property list.  Unlike the Objective‑C version,
/// this implementation does not rely on ``NSObject`` or manual
/// memory management.  Instead, the dictionary is loaded once
/// lazily on first access and cached for the lifetime of the
/// process.
public final class DCMDictionary: @unchecked Sendable {
    /// Shared global instance.  The dictionary is loaded on demand
    /// using ``lazy`` so that applications which never access
    /// DICOM metadata do not pay the cost of parsing the plist.
    static let shared = DCMDictionary()

    /// Underlying storage for the tag mappings.  Keys are
    /// hex strings (e.g. ``"00020002"``) and values are
    /// strings beginning with the two character VR followed by
    /// ``":"`` and a description.  This type alias aids
    /// readability and makes testing easier.
    private typealias RawDictionary = [String: String]

    /// Internal backing store.  Marked as ``lazy`` so the
    /// property list is only read when first used.  In the event
    /// that the resource cannot be loaded the dictionary will be
    /// empty and lookups will safely return ``nil``.
    private lazy var dictionary: RawDictionary = {
        guard let url = Bundle.main.url(forResource: "DCMDictionary", withExtension: "plist") else {
            // If the plist cannot be located we log a warning once.
            #if DEBUG
            print("[DCMDictionary] Warning: DCMDictionary.plist not found in bundle")
            #endif
            return [:]
        }
        do {
            let data = try Data(contentsOf: url)
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            return plist as? RawDictionary ?? [:]
        } catch {
            // Parsing errors will result in an empty dictionary.  We
            // deliberately avoid throwing here to allow clients to
            // continue operating even if metadata is missing.
            #if DEBUG
            print("[DCMDictionary] Error parsing plist: \(error)")
            #endif
            return [:]
        }
    }()

    // MARK: - Public Interface
    
    /// Returns the raw value associated with the supplied key.  The
    /// caller must split the VR code from the description if
    /// necessary.  Keys are expected to be eight hexadecimal
    /// characters representing the 32‑bit DICOM tag.
    ///
    /// - Parameter key: A hexadecimal string identifying a DICOM tag.
    /// - Returns: The string from the plist if present, otherwise
    ///   ``nil``.
    func value(forKey key: String) -> String? {
        dictionary[key]
    }
    
    // MARK: - Private Methods

    /// Private initialiser to enforce the singleton pattern.
    private init() {}
}

// MARK: - DCMDictionary Extensions

public extension DCMDictionary {
    
    // MARK: - Convenience Methods
    
    /// Returns just the VR code for a given tag
    /// - Parameter key: A hexadecimal string identifying a DICOM tag
    /// - Returns: The VR code (first 2 characters) or nil if not found
    static func vrCode(forKey key: String) -> String? {
        guard let value = shared.value(forKey: key),
              value.count >= 2 else { return nil }
        return String(value.prefix(2))
    }
    
    /// Returns just the description for a given tag
    /// - Parameter key: A hexadecimal string identifying a DICOM tag
    /// - Returns: The description (after "XX:") or nil if not found
    static func description(forKey key: String) -> String? {
        guard let value = shared.value(forKey: key),
              let colonIndex = value.firstIndex(of: ":") else { return nil }
        return String(value[value.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
    }
    
    /// Formats a tag as a standard DICOM tag string
    /// - Parameter tag: The 32-bit tag value
    /// - Returns: Formatted tag string in the format "(XXXX,XXXX)"
    static func formatTag(_ tag: UInt32) -> String {
        let group = (tag >> 16) & 0xFFFF
        let element = tag & 0xFFFF
        return String(format: "(%04X,%04X)", group, element)
    }
}