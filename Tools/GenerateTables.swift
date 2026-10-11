//
//  GenerateTables.swift
//  SpirvCore
//
//  Generates Sources/SpirvCore/Generated/*.swift from the pinned Khronos
//  grammar files in Grammar/. The generated Swift is checked in, so the package
//  builds without this tool; run it only to bump the grammar or change the
//  output shape.
//
//      swift Tools/GenerateTables.swift            # rewrite the generated files
//      swift Tools/GenerateTables.swift --check    # fail if they differ from the grammar
//

import Foundation

// MARK: - Pin

/// KhronosGroup/SPIRV-Headers commit the files in Grammar/ were taken from.
let grammarCommit = "86f980c731e62ae4eaf383d320449d71687936bf"
let grammarCommitDate = "2026-10-02"

// MARK: - Grammar model

struct Value: Decodable {
    let number: UInt64

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let n = try? c.decode(UInt64.self) {
            number = n
            return
        }
        let s = try c.decode(String.self)
        guard s.hasPrefix("0x"), let n = UInt64(s.dropFirst(2), radix: 16) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "bad value \(s)")
        }
        number = n
    }
}

struct Operand: Decodable {
    var kind: String
}

struct Instruction: Decodable {
    var opname: String
    var opcode: Int
    var aliases: [String]?
    var operands: [Operand]?
    var capabilities: [String]?
    var extensions: [String]?
    var version: String?
    var lastVersion: String?
}

struct Enumerant: Decodable {
    var enumerant: String
    var value: Value
    var aliases: [String]?
    var capabilities: [String]?
    var extensions: [String]?
    var version: String?
    var lastVersion: String?
}

struct Kind: Decodable {
    var category: String
    var kind: String
    var enumerants: [Enumerant]?
}

struct Grammar: Decodable {
    var major_version: Int?
    var minor_version: Int?
    var version: Int?
    var revision: Int
    var instructions: [Instruction]
    var operand_kinds: [Kind]?

    /// `SPIR-V 1.6 revision 7` for the core grammar, `grammar 100 revision 2` for an extended set.
    var edition: String {
        if let major_version, let minor_version {
            return "SPIR-V \(major_version).\(minor_version) revision \(revision)"
        }
        return "extended instruction set grammar version \(version ?? 0) revision \(revision)"
    }
}

// MARK: - Naming

/// Swift words that cannot be used as a bare identifier.
let reserved: Set<String> = [
    "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import",
    "init", "inout", "internal", "let", "open", "operator", "private", "precedencegroup",
    "protocol", "public", "rethrows", "static", "struct", "subscript", "typealias", "var",
    "break", "case", "catch", "continue", "default", "defer", "do", "else", "fallthrough",
    "for", "guard", "if", "in", "repeat", "return", "throw", "switch", "where", "while",
    "as", "false", "is", "nil", "self", "super", "throws", "true", "try",
]

func escaped(_ name: String) -> String {
    reserved.contains(name) ? "`\(name)`" : name
}

/// `FAbs` → `fAbs`, `GLCompute` → `glCompute`, `ESSL` → `essl`, `Rgba8` → `rgba8`.
/// Only the leading run of capitals is touched; the rest keeps its case.
func lowerCamel(_ s: String) -> String {
    let parts = s.split(separator: "_", omittingEmptySubsequences: true).map(String.init)
    var out = ""
    for (i, part) in parts.enumerated() {
        if i == 0 {
            out += lowerLeadingRun(part)
        } else if let first = part.first, first.isNumber {
            out += "_" + part
        } else {
            out += part.prefix(1).uppercased() + part.dropFirst()
        }
    }
    return out
}

func lowerLeadingRun(_ s: String) -> String {
    let chars = Array(s)
    var run = 0
    while run < chars.count, chars[run].isUppercase { run += 1 }
    if run == 0 { return s }
    var lowered = run
    // `GLCompute`: the last capital of the run starts the next word.
    if run > 1, run < chars.count, chars[run].isLowercase { lowered = run - 1 }
    return String(chars[..<lowered]).lowercased() + String(chars[lowered...])
}

func caseName(_ grammarName: String, kind: String) -> String {
    var name = lowerCamel(grammarName)
    if let first = name.first, first.isNumber {
        name = lowerCamel(kind) + name
    }
    return name
}

// MARK: - Documentation

func doc(
    capabilities: [String]?, extensions: [String]?, version: String?, lastVersion: String?
) -> String? {
    var parts: [String] = []
    if let capabilities, !capabilities.isEmpty {
        parts.append("Requires " + capabilities.map { "`\($0)`" }.joined(separator: ", ") + ".")
    }
    if let version, version != "1.0" {
        parts.append(version == "None" ? "Not in any core SPIR-V version." : "SPIR-V \(version).")
    }
    if let extensions, !extensions.isEmpty {
        parts.append("Extension: " + extensions.joined(separator: ", ") + ".")
    }
    if let lastVersion {
        parts.append("Last valid in SPIR-V \(lastVersion).")
    }
    return parts.isEmpty ? nil : parts.joined(separator: " ")
}

// MARK: - Emission

struct Output {
    var path: String
    var text: String
}

func header(file: String, source: String, grammar: Grammar) -> String {
    """
    //
    //  \(file)
    //  SpirvCore
    //
    //  GENERATED by Tools/GenerateTables.swift. Do not edit by hand.
    //  Source: \(source)
    //  \(grammar.edition),
    //  KhronosGroup/SPIRV-Headers \(grammarCommit.prefix(7)) (\(grammarCommitDate)).
    //

    """
}

struct Failure: Error, CustomStringConvertible {
    var description: String
}

/// Throws if two names would collide in one declaration scope.
func requireUnique(_ names: [String], in scope: String) throws {
    var seen: Set<String> = []
    for n in names where !seen.insert(n).inserted {
        throw Failure(description: "name collision in \(scope): \(n)")
    }
}

/// `items` in rows of `perLine`, continuation rows indented by `indent`.
func wrapped(_ items: [String], indent: String, perLine: Int) -> String {
    stride(from: 0, to: items.count, by: perLine).map { start in
        items[start..<min(start + perLine, items.count)].joined(separator: ", ")
    }.joined(separator: ",\n" + indent)
}

func emitInstructionEnum(
    typeName: String, rawType: String, typeDoc: String, instructions: [Instruction], withResultInfo: Bool
) throws -> String {
    let sorted = instructions.sorted { $0.opcode < $1.opcode }
    var names: [String] = []
    var out = "/// \(typeDoc)\n"
    out += "public enum \(typeName): \(rawType), Sendable {\n"
    for i in sorted {
        let n = escaped(lowerCamel(i.opname))
        names.append(n)
        if let d = doc(capabilities: i.capabilities, extensions: i.extensions, version: i.version, lastVersion: i.lastVersion) {
            out += "    /// \(d)\n"
        }
        out += "    case \(n) = \(i.opcode)\n"
    }
    out += "}\n"

    var aliasLines: [String] = []
    for i in sorted {
        for a in i.aliases ?? [] {
            let an = escaped(lowerCamel(a))
            names.append(an)
            aliasLines.append("    /// Alias of ``\(typeName)/\(lowerCamel(i.opname))``.\n    public static var \(an): \(typeName) { .\(escaped(lowerCamel(i.opname))) }")
        }
    }
    try requireUnique(names, in: typeName)
    if !aliasLines.isEmpty {
        out += "\nextension \(typeName) {\n" + aliasLines.joined(separator: "\n") + "\n}\n"
    }

    if withResultInfo {
        func hasResultType(_ i: Instruction) -> Bool { i.operands?.first?.kind == "IdResultType" }
        func hasResult(_ i: Instruction) -> Bool { i.operands?.contains { $0.kind == "IdResult" } ?? false }
        func cases(_ pick: (Instruction) -> Bool) -> String {
            wrapped(sorted.filter(pick).map { "." + escaped(lowerCamel($0.opname)) }, indent: "             ", perLine: 6)
        }
        out += """

        extension \(typeName) {
            /// Whether the instruction defines a result id, so `operands[0]` (or
            /// `operands[1]` when it also has a result type) is the id it defines.
            public var hasResult: Bool {
                switch self {
                case \(cases(hasResult)):
                    true
                default:
                    false
                }
            }

            /// Whether the instruction's first operand is a result type id.
            public var hasResultType: Bool {
                switch self {
                case \(cases(hasResultType)):
                    true
                default:
                    false
                }
            }
        }

        """
    }
    return out
}

func emitValueEnum(_ kind: Kind) throws -> String {
    let typeName = "Spirv" + kind.kind
    let all = kind.enumerants ?? []
    var names: [String] = []
    var out = "/// The SPIR-V `\(kind.kind)` operand values.\n"
    out += "public enum \(typeName): UInt32, Sendable {\n"
    var seenValues: Set<UInt64> = []
    for e in all {
        guard seenValues.insert(e.value.number).inserted else {
            throw Failure(description: "\(typeName): value \(e.value.number) listed twice; use `aliases`")
        }
        let n = escaped(caseName(e.enumerant, kind: kind.kind))
        names.append(n)
        if let d = doc(capabilities: e.capabilities, extensions: e.extensions, version: e.version, lastVersion: e.lastVersion) {
            out += "    /// \(d)\n"
        }
        out += "    case \(n) = \(e.value.number)\n"
    }
    out += "}\n"

    var aliasLines: [String] = []
    for e in all {
        for a in e.aliases ?? [] {
            let an = escaped(caseName(a, kind: kind.kind))
            let target = escaped(caseName(e.enumerant, kind: kind.kind))
            names.append(an)
            aliasLines.append("    /// Alias of ``\(typeName)/\(caseName(e.enumerant, kind: kind.kind))``.\n    public static var \(an): \(typeName) { .\(target) }")
        }
    }
    try requireUnique(names, in: typeName)
    if !aliasLines.isEmpty {
        out += "\nextension \(typeName) {\n" + aliasLines.joined(separator: "\n") + "\n}\n"
    }
    return out
}

func emitMask(_ kind: Kind) throws -> String {
    let typeName = "Spirv" + kind.kind
    let all = kind.enumerants ?? []
    var names: [String] = ["all"]
    var union: UInt64 = 0
    var members = ""
    func hex(_ v: UInt64) -> String { "0x" + String(v, radix: 16, uppercase: true) }
    /// `[]` for the zero mask: `rawValue: 0` makes the compiler warn about an empty option set.
    func literal(_ v: UInt64) -> String { v == 0 ? "[]" : "\(typeName)(rawValue: \(hex(v)))" }

    for e in all {
        let n = escaped(caseName(e.enumerant, kind: kind.kind))
        names.append(n)
        union |= e.value.number
        if let d = doc(capabilities: e.capabilities, extensions: e.extensions, version: e.version, lastVersion: e.lastVersion) {
            members += "    /// \(d)\n"
        }
        members += "    public static let \(n): \(typeName) = \(literal(e.value.number))\n"
        for a in e.aliases ?? [] {
            let an = escaped(caseName(a, kind: kind.kind))
            names.append(an)
            members += "    /// Alias of ``\(typeName)/\(caseName(e.enumerant, kind: kind.kind))``.\n"
            members += "    public static let \(an): \(typeName) = \(literal(e.value.number))\n"
        }
    }
    try requireUnique(names, in: typeName)

    var out = "/// The SPIR-V `\(kind.kind)` mask. Operands that a set bit adds follow the mask word in increasing bit order.\n"
    out += "public struct \(typeName): OptionSet, Sendable {\n"
    out += "    public let rawValue: UInt32\n\n"
    out += "    public init(rawValue: UInt32) {\n        self.rawValue = rawValue\n    }\n\n"
    out += members
    out += "\n    /// Every bit the grammar defines.\n"
    out += "    public static let all = \(typeName)(rawValue: \(hex(union)))\n"
    out += "}\n"
    return out
}

// MARK: - Run

let args = Array(CommandLine.arguments.dropFirst())
let checkOnly = args.contains("--check")

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let decoder = JSONDecoder()

func load(_ name: String) throws -> Grammar {
    try decoder.decode(Grammar.self, from: Data(contentsOf: root.appendingPathComponent("Grammar/\(name)")))
}

do {
    let core = try load("spirv.core.grammar.json")
    let glsl = try load("extinst.glsl.std.450.grammar.json")
    let coreSource = "Grammar/spirv.core.grammar.json"
    let glslSource = "Grammar/extinst.glsl.std.450.grammar.json"
    var outputs: [Output] = []

    // Instructions.
    var text = header(file: "SpirvOp.swift", source: coreSource, grammar: core) + "\n"
    text += try emitInstructionEnum(
        typeName: "SpirvOp", rawType: "UInt16",
        typeDoc: "Every core SPIR-V instruction, extension and vendor instructions included.",
        instructions: core.instructions, withResultInfo: true)
    outputs.append(Output(path: "Sources/SpirvCore/Generated/SpirvOp.swift", text: text))

    // GLSL.std.450.
    text = header(file: "GLSLstd450.swift", source: glslSource, grammar: glsl) + "\n"
    text += try emitInstructionEnum(
        typeName: "GLSLstd450", rawType: "UInt32",
        typeDoc: "GLSL.std.450 extended instruction numbers.",
        instructions: glsl.instructions, withResultInfo: false)
    outputs.append(Output(path: "Sources/SpirvCore/Generated/GLSLstd450.swift", text: text))

    // Operand kinds.
    let kinds = core.operand_kinds ?? []
    let valueKinds = kinds.filter { $0.category == "ValueEnum" }
    let maskKinds = kinds.filter { $0.category == "BitEnum" }

    text = header(file: "SpirvEnums.swift", source: coreSource, grammar: core)
    for k in valueKinds { text += "\n" + (try emitValueEnum(k)) }
    outputs.append(Output(path: "Sources/SpirvCore/Generated/SpirvEnums.swift", text: text))

    text = header(file: "SpirvMasks.swift", source: coreSource, grammar: core)
    for k in maskKinds { text += "\n" + (try emitMask(k)) }
    outputs.append(Output(path: "Sources/SpirvCore/Generated/SpirvMasks.swift", text: text))

    var stale: [String] = []
    for o in outputs {
        let url = root.appendingPathComponent(o.path)
        let existing = try? String(contentsOf: url, encoding: .utf8)
        if existing == o.text { continue }
        if checkOnly {
            stale.append(o.path)
        } else {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try o.text.write(to: url, atomically: true, encoding: .utf8)
            print("wrote \(o.path)")
        }
    }
    if checkOnly {
        if stale.isEmpty {
            print("generated tables match the grammar")
        } else {
            print("out of date: " + stale.joined(separator: ", "))
            exit(1)
        }
    } else {
        print("\(core.instructions.count) instructions, \(valueKinds.count) enums, \(maskKinds.count) masks, \(glsl.instructions.count) GLSL.std.450")
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
