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

`SpirvOp` and the enums beside it (`GLSLstd450`, `SpirvCapability`,
`SpirvStorageClass`, `SpirvDecoration`, `SpirvBuiltIn`, `SpirvDim`,
`SpirvImageFormat`, execution/loop/selection control, …) cover the subset of
SPIR-V 1.0 that PyShader emits and its decompiler reads, with values taken
straight from the Khronos `spirv.core.grammar`. Not the whole instruction set;
adding a case is a one-line change.

`halfBits` / `floatFromHalfBits` convert to and from IEEE 754 binary16 by hand,
since `Float16` is unavailable on x86_64 macOS.

## License

MIT. See [LICENSE](LICENSE).
