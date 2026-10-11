# Grammar

Pinned copies of the machine-readable SPIR-V grammar, the source of everything
in `Sources/SpirvCore/Generated/`.

| File | From |
|---|---|
| `spirv.core.grammar.json` | `include/spirv/unified1/spirv.core.grammar.json` |
| `extinst.glsl.std.450.grammar.json` | `include/spirv/unified1/extinst.glsl.std.450.grammar.json` |

Both are unmodified, taken from
[KhronosGroup/SPIRV-Headers](https://github.com/KhronosGroup/SPIRV-Headers) at
commit `86f980c731e62ae4eaf383d320449d71687936bf` (2026-10-02): SPIR-V 1.6
revision 7. MIT licensed, copyright The Khronos Group Inc. (see the header of
each file).

Regenerate with `swift Tools/GenerateTables.swift` from the package root.
