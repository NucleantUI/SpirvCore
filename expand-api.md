# Expand the spirv coverage with more enums etc of the bytecode..

Working notes. Not a plan of record — a list to pick from.

## Done: the tables

`SpirvOp`, `GLSLstd450`, and every enumerated operand kind in the grammar are
generated from the pinned Khronos grammar (SPIR-V 1.6 revision 7, SPIRV-Headers
`86f980c`) by `Tools/GenerateTables.swift` and checked in under
`Sources/SpirvCore/Generated/`:

| Table | Before | Now |
|---|---|---|
| `SpirvOp` | 178 | 878 (all core, extension and vendor instructions) |
| `GLSLstd450` | 81 | 81 (unchanged, now generated) |
| value-enum types | 11, 1–19 cases each | 42, complete |
| mask types | 0 (4 placeholder enums) | 16 `OptionSet`s |

That covers everything the earlier version of this file listed in Tiers 1–3,
including `Scope`, `MemorySemantics`, `MemoryAccess`, `GroupOperation` and the
other operand kinds that had no type, the compute builtins, `SpecId`, the bit
and atomic instructions, subgroup ops, and the OpenCL/kernel half. Names that
existed before keep their spelling and value; `SpirvImageOperands`,
`SpirvFunctionControl`, `SpirvSelectionControl` and `SpirvLoopControl` went
from single-case enums to `OptionSet`s (`.lod`, `.none`, `.inline` still
resolve, `.rawValue` is the same).

`SpirvOp.hasResult` / `.hasResultType` are generated alongside, from the
grammar's operand lists.

Tests: `Tests/SpirvCoreTests/GrammarTests.swift` reads the pinned JSON itself
and checks every instruction, every value-enum case (both directions), every
mask's bit set, GLSL.std.450, `hasResult`, plus a block of literal values taken
from the specification rather than the file.

## Done: downstream

PyShader builds against these tables as of PyShader `12569ab`. Spirv2PyShader's
`modelName` names any known stage now. Its hand-written `hasResult(_:)`, which
treated every opcode off its list as a value, is replaced by `hasResultType`.
Once the barrier and demote opcodes had names, the hand-written version read
them as values and trapped on the zero-operand ones.

What PyShader can build on the full tables is in PyShader's own
`expand-api.md`.

## Open: API shape, not table size

These change call sites rather than adding cases.

1. **Operands a mask bit adds.** The grammar says which extra operands follow
   a mask word (`Lod` → one `IdRef`, `Grad` → two, …, in increasing bit
   order). The `OptionSet`s model the bits but not that rule, which is easy
   to get wrong at the call site.
2. **Two instruction types, and the writer can't emit an unnamed opcode.**
   `SpirvInstruction.op` is a non-optional `SpirvOp`;
   `SpirvModuleReader.Instruction` is a separate struct with `opcode: UInt16`
   + `op: SpirvOp?`. With 878 named opcodes this only bites for opcodes newer
   than the pinned grammar, but a read–modify–write round trip still can't
   carry one.
3. **No operand model.** `hasResult` is there; the per-opcode operand-kind
   list is not, so nothing is validated against it (the reader checks only
   that the word count fits the stream) and there is no disassembler. The
   grammar has the lists; the generator would emit a table.
4. **Context-dependent literals.** `OpConstant`'s value is one word or two
   depending on the type's bit width. `halfBits`/`floatFromHalfBits` cover
   16-bit; 64-bit has nothing on either side.
5. **Header values are magic numbers elsewhere.** PyShader's
   `SpirvModuleBuilder.build()` writes `0x0723_0203`, `0x0001_0000` and a
   generator word as literals. A `SpirvVersion` (1.0–1.6 as words) and a
   generator-id constant belong here.
6. **No writer-side module layout.** The logical section order (capabilities →
   extensions → `OpExtInstImport` → `OpMemoryModel` → `OpEntryPoint` →
   execution modes → debug → annotations → types/constants/globals →
   functions) lives in PyShader's builder. The ordering and header assembly
   are generic; type/constant dedup and id allocation are PyShader's.
7. **Other extended instruction sets.** Only GLSL.std.450 has a typed enum.
   `NonSemantic.DebugPrintf` is the one with obvious value (printf from a
   shader under test); `OpenCL.std` and `NonSemantic.Shader.DebugInfo100` are
   in the same grammar directory if ever needed. The generator already takes
   an extended-set grammar, so each is one more call.

## Open: tests that are missing

- Round trip: read a PyShader-emitted `.spv`, re-emit it, compare words.
- Big-endian input — `SpirvModuleReader(data:)` byte-swaps but no test feeds
  it a swapped module.
- Truncated/garbage edge cases beyond bad magic: zero word count, a count that
  runs past the end, a literal string with no terminator, a byte count not a
  multiple of 4.
- `halfBits` against the full 16-bit space rather than eight samples — all
  65536 patterns round-trip in milliseconds.
