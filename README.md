# SpirvCore

The SPIR-V opcode tables, instruction encoding and a word-stream reader, as a
small Swift package with no dependencies. Extracted from
[PyShader](https://github.com/NucleantUI/PyShader), which emits SPIR-V, and
used by anything that needs to write or read a module without pulling in a
compiler.

```swift
.package(url: "https://github.com/NucleantUI/SpirvCore.git", branch: "master")
```

## Writing

`SpirvInstruction` is one instruction — an opcode and its operand words — and
`words` encodes it, word count in the high half of the first word:

```swift
import SpirvCore

var words: [UInt32] = [SpirvModuleReader.magic, 0x0001_0000, 0, bound, 0]
words += SpirvInstruction(.opCapability, [SpirvCapability.shader.rawValue]).words
words += SpirvInstruction(.opExtInstImport, [1] + SpirvInstruction.encode(string: "GLSL.std.450")).words
words += SpirvInstruction(.opTypeVoid, [2]).words
```

Literal strings go through `SpirvInstruction.encode(string:)` (null terminated,
padded to a word, little endian) and come back with
`SpirvInstruction.decode(string:from:)`.

## Reading

`SpirvModuleReader` is the inverse: it splits a word stream into its header and
instructions, from `[UInt32]` or from a `.spv` file's bytes in either
endianness.

```swift
let reader = try SpirvModuleReader(data: Data(contentsOf: url))
for instruction in reader.instructions {
    switch instruction.op {
    case .opExtInstImport: print(instruction.string(at: 1).string)
    case .opTypeVoid:      print("void is %\(instruction.operands[0])")
    default:               break
    }
}
```

Opcodes outside `SpirvOp` keep their raw number — `op` is optional and
`opcode` always holds the number — so a reader can skip or report an
instruction this package doesn't name yet. A bad magic number or a truncated
instruction throws `SpirvReadError`.

## What's in the tables

The tables are the whole of the Khronos grammar, SPIR-V 1.6 revision 7
(SPIRV-Headers `86f980c`, 2026-10-02), generated from it rather than written
by hand:

- `SpirvOp` — all 878 core instructions, extension and vendor ones included,
  with `hasResult` / `hasResultType` for indexing a module by result id.
- `GLSLstd450` — the complete GLSL.std.450 set.
- One enum per value kind (`SpirvCapability`, `SpirvStorageClass`,
  `SpirvDecoration`, `SpirvBuiltIn`, `SpirvExecutionMode`, `SpirvScope`,
  `SpirvGroupOperation`, `SpirvImageFormat`, …), 42 in all.
- One `OptionSet` per mask kind (`SpirvImageOperands`,
  `SpirvMemorySemantics`, `SpirvMemoryAccess`, `SpirvLoopControl`, …), 16 in
  all, each with `.all` for the bits the grammar defines.

Every case's doc comment carries what the grammar says about it: required
capabilities, the SPIR-V version that introduced it, and the extension for
non-core ones. Alternate spellings the grammar lists (`opSDotKHR`,
`SpirvMemorySemantics.none`) are static members that resolve to the one case.

OpenCL-only and vendor entries are in too, with their requirements in the doc
comment. An opcode newer than the pinned grammar still reads: `op` is nil and
`opcode` holds the number.

## Regenerating

The generated Swift in `Sources/SpirvCore/Generated/` is checked in, so the
package builds without any tool. To rebuild it from the pinned grammar in
`Grammar/`:

```
swift Tools/GenerateTables.swift           # rewrite the generated files
swift Tools/GenerateTables.swift --check   # exit 1 if they differ from the grammar
```

To move to a newer grammar, replace the two JSON files in `Grammar/` with the
`unified1` copies from a SPIRV-Headers commit, update `grammarCommit` and
`grammarCommitDate` at the top of the generator, run it, and run the tests:
they read the same JSON separately and fail on any case that is missing, extra,
or has a different value, and on a grammar kind the tests have no Swift type
for.

`halfBits` / `floatFromHalfBits` convert to and from IEEE 754 binary16 by hand,
since `Float16` is unavailable on x86_64 macOS.

## License

MIT. See [LICENSE](LICENSE).
