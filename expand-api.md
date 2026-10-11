# Expand the spirv coverage with more enums etc of the bytecode..

Working notes on what SpirvCore does *not* cover yet. Not a plan of record and
not complete — a list to pick from. Numbers below were measured against
`spirv.core.grammar.json` from SPIRV-Headers `unified1` (SPIR-V 1.6 rev 7,
checked 2026-10-10), so they are the real gaps, not guesses. Anything added
should take its value from that grammar, as the current tables do.

## Where the line sits today

| Table | Covered | Of | Note |
|---|---|---|---|
| `SpirvOp` | 178 | 340 core instructions (versioned, no extension gate) | 163 missing; ~115 of those are SPIR-V 1.0 |
| `GLSLstd450` | 81 | 81 | complete, nothing to do |
| `SpirvCapability` | 5 | 307 (51 shader-relevant missing) | the thinnest table by far |
| `SpirvExecutionMode` | 2 | 101 (27 shader-relevant missing) | |
| `SpirvDecoration` | 19 | 152 (19 shader-relevant missing) | |
| `SpirvBuiltIn` | 11 | 129 (23 shader-relevant missing) | no compute builtins at all |
| `SpirvImageFormat` | 2 | 42 (40 missing) | only `unknown` + `rgba8` |
| `SpirvImageOperands` | 1 | 17 (11 shader-relevant missing) | and it is a mask, see below |
| `SpirvDim` | 4 | 8 | missing `Rect`, `Buffer`, `SubpassData` |
| `SpirvStorageClass` | 13 | 29 | complete for the shader-relevant ones |
| `SpirvLoopControl` / `SelectionControl` / `FunctionControl` | 1 / 1 / 2 | 21 / 3 / 6 | `none` only, plus `inline`; placeholders |

Fifteen operand kinds that appear in core shader instructions have no Swift
type at all: `MemorySemantics`, `MemoryAccess`, `Scope`, `GroupOperation`,
`FPRoundingMode`, `FPFastMathMode`, `AccessQualifier`, `LinkageType`,
`SamplerAddressingMode`, `SamplerFilterMode`, `FunctionParameterAttribute`,
`ImageChannelOrder`, `ImageChannelDataType`, `KernelEnqueueFlags`,
`KernelProfilingInfo`. The first four are the ones a shader actually needs —
atomics and barriers cannot be written without `Scope` and `MemorySemantics`.

## Instructions worth adding, in the order they will be wanted

Tier 1 maps onto the "Not yet" table in PyShader's `shader-api-status.md`:
nothing there can be emitted until the opcode exists here.

**Tier 1 — what PyShader is already blocked on**

- Bit instructions `201`–`205`: `OpBitFieldInsert`, `OpBitFieldSExtract`,
  `OpBitFieldUExtract`, `OpBitReverse`, `OpBitCount`. PyShader lists
  `bitcount` / `findLSB` / `reverse_bits` as to-do; `findILsb`/`findSMsb`/
  `findUMsb` already exist in `GLSLstd450`, so only the core five are missing.
- Extended arithmetic `149`–`152`: `OpIAddCarry`, `OpISubBorrow`,
  `OpUMulExtended`, `OpSMulExtended`. Ungated (no capability), and the natural
  landing spot for hash-style integer code.
- Atomics and barriers `224`, `225`, `227`–`242`: `OpControlBarrier`,
  `OpMemoryBarrier`, `OpAtomicLoad` … `OpAtomicXor`. Needs `Scope`,
  `MemorySemantics` (a mask) and `MemoryAccess` (a mask) alongside.
- Compute builtins in `SpirvBuiltIn`: `NumWorkgroups` 24, `WorkgroupSize` 25,
  `WorkgroupId` 26, `LocalInvocationId` 27, `LocalInvocationIndex` 29.
  `globalInvocationId` is there alone today, which is enough for the current
  one-thread-per-pixel compute target and nothing else.
- Fragment control in `SpirvExecutionMode`: `OriginLowerLeft` 8,
  `PixelCenterInteger` 6, `EarlyFragmentTests` 9, `DepthReplacing` 12,
  `DepthGreater`/`DepthLess`/`DepthUnchanged` 14–16. Writing `FragDepth`
  (already in `SpirvBuiltIn`) is invalid without `DepthReplacing`.
- `SpirvBuiltIn.HelperInvocation` 23, `SpirvDecoration.SpecId` 1,
  `NoContraction` 42, `Invariant` 18, `Volatile`/`Coherent`/`Restrict`/
  `Aliased` 19–23. `SpecId` is the odd one out: all five `OpSpecConstant*`
  opcodes are covered but the decoration that gives a spec constant its id
  is not, so specialization constants can't actually be emitted.
- Image sampling variants `91`–`97`: the four `OpImageSampleProj*` and
  `OpImageDrefGather`. Plus `OpImageQuerySamples` 107 to round out the query
  set (`ImageQuery` capability is already declared).
- `SpirvImageFormat`: the 40 missing formats. `rgba8` only is fine for the
  current storage-image output; `rgba32f`/`rgba16f`/`r32f`/`r32ui` are the
  first ones anything else will ask for. This is a flat transcription — the
  cheapest big win in the file.
- `SpirvDim.Buffer` 5 and `SubpassData` 6 — texel buffers and input
  attachments respectively, both ordinary Vulkan shader territory.
- Capabilities for the above and for wider scalars: `Int8` 39, `Int64` 11,
  `Float64` 10, `Geometry` 2, `Tessellation` 3, `ClipDistance` 32,
  `CullDistance` 33, `SampleRateShading` 35, `InputAttachment` 40,
  `Sampled1D` 43, `SampledBuffer` 46, `ImageBuffer` 47, `ImageCubeArray` 34,
  `StorageImageExtendedFormats` 49, `StorageImageReadWithoutFormat` 55,
  `StorageImageWriteWithoutFormat` 56, `InterpolationFunction` 52 (needed by
  the `interpolateAt*` GLSL entries that are already in the table).
- Execution models `TessellationControl` 1, `TessellationEvaluation` 2,
  `Geometry` 3 — PyShader only emits `Fragment` and `GLCompute` today, and
  `Vertex` is already here, so this is just finishing the enum.
- `SpirvMemoryModel.Simple` 0 (and `Vulkan` 3 if the Vulkan memory model ever
  comes up; it is 1.5 + `VulkanMemoryModel`).

**Tier 2 — real shader features, no current caller**

- Subgroup ops `333`–`366` (`OpGroupNonUniform*`, 34 instructions), with
  `GroupOperation` and the eight `GroupNonUniform*` capabilities 61–68.
  This is the single largest coherent block left.
- Geometry stage: `OpEmitVertex` 218, `OpEndPrimitive` 219, and the streams
  pair 220/221, plus the `InputPoints` … `OutputTriangleStrip` execution modes
  19–29 and builtins `PrimitiveId` 7, `InvocationId` 8, `Layer` 9,
  `ViewportIndex` 10.
- Tessellation: execution modes 1–5, 10, 24–26, builtins `TessLevelOuter` 11,
  `TessLevelInner` 12, `TessCoord` 13, `PatchVertices` 14, decoration
  `Patch` 15.
- SPIR-V 1.4 additions `400`–`403`: `OpCopyLogical`, `OpPtrEqual`,
  `OpPtrNotEqual`, `OpPtrDiff`.
- `OpDemoteToHelperInvocation` 5380 and `OpTerminateInvocation` 4416. Both are
  in 1.6; `OpTerminateInvocation` is still extension-tagged in the grammar
  (`SPV_KHR_terminate_invocation`) and is the modern spelling of what
  `discard()` emits as `OpKill` today. Worth a note in PyShader that `OpKill`
  is deprecated at 1.6 before anything bumps the version word.
- `FPRoundingMode` and `FPFastMathMode` enums + the decorations 39/40 that
  carry them — relevant the moment half-precision storage shows up.
- `SpirvExecutionMode.LocalSizeId` 38 (1.2): workgroup size from an id rather
  than three literals, which is how a specializable local size is written.
- `OpPtrAccessChain` 67 / `OpInBoundsPtrAccessChain` 70 — only under
  `VariablePointers`/`PhysicalStorageBufferAddresses`, so Tier 2 at best.

**Tier 3 — probably never, decide explicitly**

The OpenCL/Kernel half of the instruction set is roughly 90 of the 163 missing
instructions: pipes (`274`–`288`, `322`–`324`), device enqueue (`291`–`304`),
events (`OpTypeEvent` 34, `OpTypeDeviceEvent` 35, `OpTypeQueue` 37,
`OpGroupAsyncCopy` 259, `OpGroupWaitEvents` 260), the `Groups` ops `261`–`271`
(superseded by `GroupNonUniform*` for shaders), named barriers (`327`–`329`),
generic pointers (`121`–`123`, `69`), `OpSatConvert*` 118/119, `OpSizeOf` 321,
`OpLifetimeStart`/`Stop` 256/257, atomic flags 318/319, and the
`ImageChannelOrder`/`ImageChannelDataType`/`SamplerAddressingMode`/
`SamplerFilterMode`/`KernelEnqueueFlags` enums. Same for sparse residency
(`305`–`316`, `320`) and transform feedback (`Xfb` modes, `XfbBuffer`/
`XfbStride` decorations).

None of it is wrong to add, but it is bulk that nothing in this workspace will
call. The useful move is to say so in the README rather than leave the reader
guessing whether a missing opcode is an oversight or a decision.

## API shape, not just table size

These matter more than the opcode count, because they change call sites rather
than adding cases.

1. **Masks are modelled as value enums.** `ImageOperands`, `FunctionControl`,
   `SelectionControl`, `LoopControl` — and `MemoryAccess`/`MemorySemantics`
   when they arrive — are `BitEnum` in the grammar. `SpirvImageOperands` with
   a single `lod = 0x2` case cannot express `Lod | Grad | ConstOffset`, which
   is exactly what a general `sample()` needs. These should be `OptionSet`s.
   The encoding rule belongs here too: the extra operands follow the mask in
   increasing bit order, which is easy to get wrong at the call site and is
   the kind of thing this package exists to own.
2. **Two instruction types, and the writer can't emit an unnamed opcode.**
   `SpirvInstruction.op` is a non-optional `SpirvOp`; `SpirvModuleReader.Instruction`
   is a separate struct with `opcode: UInt16` + `op: SpirvOp?`. The reader can
   pass through an opcode the tables don't name, the writer cannot — so a
   round trip (read a module, change one thing, write it back) is impossible
   today for any module containing an unnamed instruction. A raw-opcode
   initializer on the writer, or one shared instruction type, fixes it.
3. **No `hasResult` / `hasResultType`.** Of 878 grammar instructions, 731 have
   a result id and 670 a result type. Without that table every reader
   hard-codes `operands[0]` vs `operands[1]` per opcode — which is what
   `Spirv2PyShader/Module/ModuleIndex.swift` does. Two generated properties on
   `SpirvOp` would let a reader index a module by result id generically, and
   that is the single most reusable thing missing.
4. **No operand model, so nothing is validated or printable.** 31 of the
   *already covered* instructions have optional or variadic operands, and the
   reader checks only "word count fits in the stream" — never against the
   expected operand list. A generated operand-kind table per opcode would give
   word-count validation, a real disassembler (`description` on an
   instruction), and correct literal-string skipping in the middle of an
   operand list. It would also give `SpirvOp` a name string, which the reader's
   error messages currently can't produce for an unnamed opcode.
5. **Context-dependent literals.** `OpConstant`'s value is
   `LiteralContextDependentNumber` — one word or two depending on the type's
   bit width, signedness mattering for sign extension. There is no helper for
   64-bit constants on the write side (`Int64`/`Float64` take two words) and no
   way to decode one on the read side without the caller tracking type widths.
   `halfBits`/`floatFromHalfBits` cover 16-bit; 64-bit has nothing.
6. **Header values are magic numbers elsewhere.** `SpirvModuleReader.magic`
   exists, but PyShader's `SpirvModuleBuilder.build()` writes `0x0723_0203`,
   `0x0001_0000` and a generator word as literals. A `SpirvVersion` (1.0–1.6 as
   words, with encode/decode) and a generator-id constant belong here, so
   "what version do we emit" is one place.
7. **No writer-side module layout.** The logical layout the spec requires
   (capabilities → extensions → `OpExtInstImport` → `OpMemoryModel` →
   `OpEntryPoint` → execution modes → debug → annotations → types/constants/
   globals → functions) lives in PyShader's builder. The section ordering and
   header assembly are generic; the type/constant dedup and id allocation are
   PyShader's business. Splitting at that seam would give SpirvCore a writer
   worth the name without dragging `ShaderType` in.
8. **Only one extended instruction set.** `GLSLstd450` is complete, but
   `OpExtInst` is otherwise untyped. `NonSemantic.DebugPrintf` is the one with
   obvious value (printf from a shader under test); `OpenCL.std` and
   `NonSemantic.Shader.DebugInfo100` are there if ever needed.

## How to keep the tables honest

Hand-writing cases does not scale to 878 instructions and 307 capabilities,
and the risk is not volume but silent wrong values. Options:

- **Generate from the grammar.** Commit a pinned copy of
  `spirv.core.grammar.json` plus a small generator, and check the generated
  Swift in so the package stays dependency-free and builds without a tool.
  Keeps hand-written helpers (`halfBits`, the reader, string codec) separate
  from generated tables. Also the only practical way to get `hasResult`,
  operand kinds and opcode names.
- **Keep transcribing by hand, but add a test that pins the values.** A test
  that reads a committed grammar copy and asserts every Swift case matches
  catches typos without a build-time generator. Cheaper, and it keeps the
  "adding a case is a one-line change" property the README advertises.

Either way the README's "What's in the tables" paragraph should say which
SPIR-V version and grammar revision the tables were taken from.

## Tests that are missing

- Round trip: read a PyShader-emitted `.spv`, re-emit it, compare words. This
  is the test that would have caught (2) above.
- Big-endian input — `SpirvModuleReader(data:)` byte-swaps but no test feeds it
  a swapped module.
- Truncated/garbage edge cases beyond bad magic: zero word count, a count that
  runs past the end, a literal string with no terminator, a byte count not a
  multiple of 4.
- Enum values against the grammar (see above).
- `halfBits` against the full 16-bit space rather than eight samples —
  all 65536 patterns round-trip in milliseconds.
