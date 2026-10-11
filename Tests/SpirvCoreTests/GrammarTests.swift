import Foundation
import Testing
import SpirvCore

// Checks the generated tables against the pinned grammar in Grammar/, read
// here independently of Tools/GenerateTables.swift, plus a few literal values
// from the SPIR-V specification that do not come from the grammar file at all.

// MARK: - Grammar, as the tests read it

private struct Grammar: Decodable {
    struct Operand: Decodable { var kind: String }
    struct Instruction: Decodable {
        var opname: String
        var opcode: Int
        var aliases: [String]?
        var operands: [Operand]?
    }
    struct Enumerant: Decodable {
        var enumerant: String
        var value: Value
        var aliases: [String]?
    }
    struct Kind: Decodable {
        var category: String
        var kind: String
        var enumerants: [Enumerant]?
    }
    /// Values are integers for `ValueEnum` kinds and `"0x…"` strings for `BitEnum` kinds.
    struct Value: Decodable {
        var number: UInt32
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let n = try? c.decode(UInt32.self) {
                number = n
            } else {
                let s = try c.decode(String.self)
                number = UInt32(s.dropFirst(2), radix: 16)!
            }
        }
    }

    var instructions: [Instruction]
    var operand_kinds: [Kind]?
}

private let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func loadGrammar(_ name: String) throws -> Grammar {
    let data = try Data(contentsOf: packageRoot.appendingPathComponent("Grammar/\(name)"))
    return try JSONDecoder().decode(Grammar.self, from: data)
}

/// `OpFAbs`, `opFAbs`, `` `private` ``, `Private` all compare equal.
private func normalized(_ s: String) -> String {
    s.lowercased().filter { $0.isLetter || $0.isNumber }
}

// MARK: - Swift type per grammar kind

private struct ValueKind: Sendable {
    var kind: String
    /// The case name for a raw value, nil when the Swift enum has no such case.
    var name: @Sendable (UInt32) -> String?

    init<E: RawRepresentable & Sendable>(_ kind: String, _ type: E.Type) where E.RawValue == UInt32 {
        self.kind = kind
        name = { E(rawValue: $0).map { String(describing: $0) } }
    }
}

private struct MaskKind: Sendable {
    var kind: String
    var make: @Sendable (UInt32) -> UInt32
    var all: UInt32

    init<M: OptionSet & Sendable>(_ kind: String, _ type: M.Type, all: M) where M.RawValue == UInt32 {
        self.kind = kind
        make = { M(rawValue: $0).rawValue }
        self.all = all.rawValue
    }
}

private let valueKinds: [ValueKind] = [
    .init("SourceLanguage", SpirvSourceLanguage.self),
    .init("ExecutionModel", SpirvExecutionModel.self),
    .init("AddressingModel", SpirvAddressingModel.self),
    .init("MemoryModel", SpirvMemoryModel.self),
    .init("ExecutionMode", SpirvExecutionMode.self),
    .init("StorageClass", SpirvStorageClass.self),
    .init("Dim", SpirvDim.self),
    .init("SamplerAddressingMode", SpirvSamplerAddressingMode.self),
    .init("SamplerFilterMode", SpirvSamplerFilterMode.self),
    .init("ImageFormat", SpirvImageFormat.self),
    .init("ImageChannelOrder", SpirvImageChannelOrder.self),
    .init("ImageChannelDataType", SpirvImageChannelDataType.self),
    .init("FPRoundingMode", SpirvFPRoundingMode.self),
    .init("FPDenormMode", SpirvFPDenormMode.self),
    .init("QuantizationModes", SpirvQuantizationModes.self),
    .init("FPOperationMode", SpirvFPOperationMode.self),
    .init("OverflowModes", SpirvOverflowModes.self),
    .init("LinkageType", SpirvLinkageType.self),
    .init("AccessQualifier", SpirvAccessQualifier.self),
    .init("HostAccessQualifier", SpirvHostAccessQualifier.self),
    .init("FunctionParameterAttribute", SpirvFunctionParameterAttribute.self),
    .init("Decoration", SpirvDecoration.self),
    .init("BuiltIn", SpirvBuiltIn.self),
    .init("Scope", SpirvScope.self),
    .init("GroupOperation", SpirvGroupOperation.self),
    .init("KernelEnqueueFlags", SpirvKernelEnqueueFlags.self),
    .init("Capability", SpirvCapability.self),
    .init("RayQueryIntersection", SpirvRayQueryIntersection.self),
    .init("RayQueryCommittedIntersectionType", SpirvRayQueryCommittedIntersectionType.self),
    .init("RayQueryCandidateIntersectionType", SpirvRayQueryCandidateIntersectionType.self),
    .init("PackedVectorFormat", SpirvPackedVectorFormat.self),
    .init("CooperativeMatrixLayout", SpirvCooperativeMatrixLayout.self),
    .init("CooperativeMatrixUse", SpirvCooperativeMatrixUse.self),
    .init("TensorClampMode", SpirvTensorClampMode.self),
    .init("InitializationModeQualifier", SpirvInitializationModeQualifier.self),
    .init("LoadCacheControl", SpirvLoadCacheControl.self),
    .init("StoreCacheControl", SpirvStoreCacheControl.self),
    .init("NamedMaximumNumberOfRegisters", SpirvNamedMaximumNumberOfRegisters.self),
    .init("FPEncoding", SpirvFPEncoding.self),
    .init("CooperativeVectorMatrixLayout", SpirvCooperativeVectorMatrixLayout.self),
    .init("ComponentType", SpirvComponentType.self),
    .init("GatherModes", SpirvGatherModes.self),
]

private let maskKinds: [MaskKind] = [
    .init("ImageOperands", SpirvImageOperands.self, all: .all),
    .init("FPFastMathMode", SpirvFPFastMathMode.self, all: .all),
    .init("SelectionControl", SpirvSelectionControl.self, all: .all),
    .init("LoopControl", SpirvLoopControl.self, all: .all),
    .init("FunctionControl", SpirvFunctionControl.self, all: .all),
    .init("MemorySemantics", SpirvMemorySemantics.self, all: .all),
    .init("MemoryAccess", SpirvMemoryAccess.self, all: .all),
    .init("KernelProfilingInfo", SpirvKernelProfilingInfo.self, all: .all),
    .init("RayFlags", SpirvRayFlags.self, all: .all),
    .init("FragmentShadingRate", SpirvFragmentShadingRate.self, all: .all),
    .init("RawAccessChainOperands", SpirvRawAccessChainOperands.self, all: .all),
    .init("CooperativeMatrixOperands", SpirvCooperativeMatrixOperands.self, all: .all),
    .init("CooperativeMatrixReduce", SpirvCooperativeMatrixReduce.self, all: .all),
    .init("TensorAddressingOperands", SpirvTensorAddressingOperands.self, all: .all),
    .init("MatrixMultiplyAccumulateOperands", SpirvMatrixMultiplyAccumulateOperands.self, all: .all),
    .init("TensorOperands", SpirvTensorOperands.self, all: .all),
]

// MARK: - Tests

@Suite("Grammar tables")
struct GrammarTests {
    @Test("every instruction in the grammar is a SpirvOp with the grammar's opcode and name")
    func instructions() throws {
        let grammar = try loadGrammar("spirv.core.grammar.json")
        for i in grammar.instructions {
            guard let op = SpirvOp(rawValue: UInt16(i.opcode)) else {
                Issue.record("\(i.opname) (\(i.opcode)) has no SpirvOp case")
                continue
            }
            #expect(normalized("\(op)") == normalized(i.opname), "\(i.opname) is \(op)")
        }
        // …and nothing in SpirvOp that the grammar does not define.
        let defined = Set(grammar.instructions.map(\.opcode))
        for raw in 0...UInt16.max where SpirvOp(rawValue: raw) != nil {
            #expect(defined.contains(Int(raw)), "SpirvOp case \(raw) is not in the grammar")
        }
    }

    @Test("instruction aliases resolve to their instruction")
    func instructionAliases() {
        #expect(SpirvOp.opSDotKHR == .opSDot)
        #expect(SpirvOp.opUDotKHR == .opUDot)
        #expect(SpirvOp.opSUDotKHR == .opSUDot)
    }

    @Test("hasResult and hasResultType follow the grammar's operand lists")
    func resultInfo() throws {
        let grammar = try loadGrammar("spirv.core.grammar.json")
        var withResult = 0
        var withType = 0
        for i in grammar.instructions {
            let op = try #require(SpirvOp(rawValue: UInt16(i.opcode)))
            let operands = i.operands ?? []
            let expectedType = operands.first?.kind == "IdResultType"
            let expectedResult = operands.contains { $0.kind == "IdResult" }
            #expect(op.hasResultType == expectedType, "\(i.opname) hasResultType")
            #expect(op.hasResult == expectedResult, "\(i.opname) hasResult")
            if op.hasResultType { #expect(op.hasResult, "\(i.opname): a result type implies a result") }
            withResult += op.hasResult ? 1 : 0
            withType += op.hasResultType ? 1 : 0
        }
        #expect(withResult == 731)
        #expect(withType == 670)

        // By hand, from the specification.
        #expect(SpirvOp.opIAdd.hasResultType && SpirvOp.opIAdd.hasResult)
        #expect(SpirvOp.opLabel.hasResult && !SpirvOp.opLabel.hasResultType)
        #expect(SpirvOp.opTypeVoid.hasResult && !SpirvOp.opTypeVoid.hasResultType)
        #expect(!SpirvOp.opStore.hasResult && !SpirvOp.opStore.hasResultType)
        #expect(!SpirvOp.opBranch.hasResult)
    }

    @Test("every value enum matches the grammar, both ways")
    func valueEnums() throws {
        let grammar = try loadGrammar("spirv.core.grammar.json")
        let kinds = (grammar.operand_kinds ?? []).filter { $0.category == "ValueEnum" }
        let known = Dictionary(uniqueKeysWithValues: valueKinds.map { ($0.kind, $0) })

        // A grammar bump that adds a kind fails here until the table above has it.
        let missing = Set(kinds.map(\.kind)).subtracting(known.keys)
        #expect(missing.isEmpty, "grammar kinds without a Swift type in this test: \(missing.sorted())")
        #expect(known.count == kinds.count)

        for kind in kinds {
            guard let swift = known[kind.kind] else { continue }
            let enumerants = kind.enumerants ?? []
            var defined: Set<UInt32> = []
            for e in enumerants {
                defined.insert(e.value.number)
                guard let name = swift.name(e.value.number) else {
                    Issue.record("\(kind.kind).\(e.enumerant) = \(e.value.number) has no case")
                    continue
                }
                // Digit-leading names (`1D`) are prefixed with the kind (`dim1D`).
                let accepted = ([e.enumerant] + (e.aliases ?? [])).flatMap { [normalized($0), normalized(kind.kind + $0)] }
                #expect(accepted.contains(normalized(name)), "\(kind.kind) \(e.value.number): \(name) vs \(e.enumerant)")
            }
            // Nothing extra in the Swift enum: the low range in full, and a
            // neighbourhood around each large vendor value (those reach 10^9).
            let low: UInt32 = 100_000
            var probes: [UInt32] = Array(0...low)
            for v in defined where v > low {
                probes += (v - 64)...(v + 64)
            }
            for raw in probes where swift.name(raw) != nil {
                #expect(defined.contains(raw), "\(kind.kind) has a case \(raw) that the grammar does not define")
            }
        }
    }

    @Test("every mask covers exactly the bits the grammar defines")
    func masks() throws {
        let grammar = try loadGrammar("spirv.core.grammar.json")
        let kinds = (grammar.operand_kinds ?? []).filter { $0.category == "BitEnum" }
        let known = Dictionary(uniqueKeysWithValues: maskKinds.map { ($0.kind, $0) })

        let missing = Set(kinds.map(\.kind)).subtracting(known.keys)
        #expect(missing.isEmpty, "grammar kinds without a Swift type in this test: \(missing.sorted())")
        #expect(known.count == kinds.count)

        for kind in kinds {
            guard let swift = known[kind.kind] else { continue }
            let union = (kind.enumerants ?? []).reduce(UInt32(0)) { $0 | $1.value.number }
            #expect(swift.all == union, "\(kind.kind).all is \(swift.all), the grammar's bits are \(union)")
            for e in kind.enumerants ?? [] {
                #expect(swift.make(e.value.number) == e.value.number)
            }
        }
    }

    @Test("GLSL.std.450 matches its grammar")
    func glsl() throws {
        let grammar = try loadGrammar("extinst.glsl.std.450.grammar.json")
        #expect(grammar.instructions.count == 81)
        for i in grammar.instructions {
            guard let inst = GLSLstd450(rawValue: UInt32(i.opcode)) else {
                Issue.record("\(i.opname) (\(i.opcode)) has no GLSLstd450 case")
                continue
            }
            #expect(normalized("\(inst)") == normalized(i.opname))
        }
        let defined = Set(grammar.instructions.map(\.opcode))
        for raw in 0..<256 where GLSLstd450(rawValue: UInt32(raw)) != nil {
            #expect(defined.contains(raw))
        }
    }

    // Literal values from the SPIR-V specification, not read from the grammar file.
    @Test("values the specification fixes")
    func literals() {
        // Core opcodes PyShader could not emit before.
        #expect(SpirvOp.opIAddCarry.rawValue == 149)
        #expect(SpirvOp.opBitFieldInsert.rawValue == 201)
        #expect(SpirvOp.opBitCount.rawValue == 205)
        #expect(SpirvOp.opControlBarrier.rawValue == 224)
        #expect(SpirvOp.opMemoryBarrier.rawValue == 225)
        #expect(SpirvOp.opAtomicIAdd.rawValue == 234)
        #expect(SpirvOp.opAtomicXor.rawValue == 242)
        #expect(SpirvOp.opEmitVertex.rawValue == 218)
        #expect(SpirvOp.opGroupNonUniformElect.rawValue == 333)
        #expect(SpirvOp.opTerminateInvocation.rawValue == 4416)
        #expect(SpirvOp.opDemoteToHelperInvocation.rawValue == 5380)

        // Operand kinds that had no type at all.
        #expect(SpirvScope.crossDevice.rawValue == 0)
        #expect(SpirvScope.device.rawValue == 1)
        #expect(SpirvScope.workgroup.rawValue == 2)
        #expect(SpirvScope.subgroup.rawValue == 3)
        #expect(SpirvGroupOperation.reduce.rawValue == 0)
        #expect(SpirvGroupOperation.exclusiveScan.rawValue == 2)
        #expect(SpirvMemorySemantics.acquire.rawValue == 0x2)
        #expect(SpirvMemorySemantics.acquireRelease.rawValue == 0x8)
        #expect(SpirvMemorySemantics.sequentiallyConsistent.rawValue == 0x10)
        #expect(SpirvMemorySemantics.uniformMemory.rawValue == 0x40)
        #expect(SpirvMemorySemantics.workgroupMemory.rawValue == 0x100)
        #expect(SpirvMemorySemantics.imageMemory.rawValue == 0x800)
        #expect(SpirvMemoryAccess.volatile.rawValue == 0x1)
        #expect(SpirvMemoryAccess.aligned.rawValue == 0x2)

        // Shader features the notes called out.
        #expect(SpirvBuiltIn.numWorkgroups.rawValue == 24)
        #expect(SpirvBuiltIn.workgroupId.rawValue == 26)
        #expect(SpirvBuiltIn.localInvocationId.rawValue == 27)
        #expect(SpirvBuiltIn.localInvocationIndex.rawValue == 29)
        #expect(SpirvBuiltIn.helperInvocation.rawValue == 23)
        #expect(SpirvDecoration.specId.rawValue == 1)
        #expect(SpirvDecoration.noContraction.rawValue == 42)
        #expect(SpirvExecutionMode.pixelCenterInteger.rawValue == 6)
        #expect(SpirvExecutionMode.earlyFragmentTests.rawValue == 9)
        #expect(SpirvExecutionMode.depthReplacing.rawValue == 12)
        #expect(SpirvExecutionModel.geometry.rawValue == 3)
        #expect(SpirvCapability.int64.rawValue == 11)
        #expect(SpirvCapability.float64.rawValue == 10)
        #expect(SpirvCapability.groupNonUniformBallot.rawValue == 64)
        #expect(SpirvImageFormat.rgba32f.rawValue == 1)
        #expect(SpirvImageFormat.r32f.rawValue == 3)
        #expect(SpirvDim.buffer.rawValue == 5)
        #expect(SpirvDim.subpassData.rawValue == 6)
    }

    @Test("masks combine and keep the names the old enums had")
    func maskSemantics() {
        let operands: SpirvImageOperands = [.lod, .constOffset]
        #expect(operands.rawValue == 0x2 | 0x8)
        #expect(operands.contains(.lod))
        #expect(!operands.contains(.grad))
        #expect(SpirvImageOperands.lod.rawValue == 0x2)
        #expect(SpirvImageOperands.none.isEmpty)
        #expect(SpirvFunctionControl.inline.rawValue == 1)
        #expect(SpirvFunctionControl.none.rawValue == 0)
        #expect(SpirvLoopControl.none.rawValue == 0)
        #expect(SpirvSelectionControl.none.rawValue == 0)
        // `None` is an alias of `Relaxed` for memory semantics.
        #expect(SpirvMemorySemantics.none == .relaxed)
        // Unknown bits fall outside `all`.
        #expect(!SpirvImageOperands(rawValue: 0x8000_0000).isSubset(of: .all))
        #expect(SpirvImageOperands.all.contains([.lod, .grad]))
    }

    @Test("enumerant aliases resolve to their enumerant")
    func enumAliases() {
        #expect(SpirvCapability.storageUniformBufferBlock16 == .storageBuffer16BitAccess)
        #expect(SpirvCapability.storageUniform16 == .uniformAndStorageBuffer16BitAccess)
    }

    @Test("the names PyShader already uses keep their values")
    func downstreamNames() {
        #expect(SpirvStorageClass.private.rawValue == 6)
        #expect(SpirvStorageClass.storageBuffer.rawValue == 12)
        #expect(SpirvExecutionModel.glCompute.rawValue == 5)
        #expect(SpirvExecutionMode.localSize.rawValue == 17)
        #expect(SpirvExecutionMode.originUpperLeft.rawValue == 7)
        #expect(SpirvBuiltIn.globalInvocationId.rawValue == 28)
        #expect(SpirvBuiltIn.fragCoord.rawValue == 15)
        #expect(SpirvDim.dim2D.rawValue == 1)
        #expect(SpirvImageFormat.rgba8.rawValue == 4)
        #expect(SpirvSourceLanguage.essl.rawValue == 1)
        #expect(SpirvDecoration.builtIn.rawValue == 11)
        #expect(SpirvCapability.derivativeControl.rawValue == 51)
        #expect(GLSLstd450.fAbs.rawValue == 4)
        #expect(GLSLstd450.findILsb.rawValue == 73)
        #expect(GLSLstd450.nClamp.rawValue == 81)
    }
}
