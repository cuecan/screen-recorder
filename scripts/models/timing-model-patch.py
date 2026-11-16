"""Run when the pinned revision of the timing model changes: it prints the edits, sizes and hashes that
TranscribeKit's TimingModelDownload holds (docs/decisions.md, 95). Needs Python 3.10 to 3.13 with coremltools.

Works out the few byte edits that add the timing head's full log-probabilities as an output of the
published model description (model.mlmodel), without re-serializing the rest of it.

timing-model-patch.py <published model.mlmodel> <out patched model.mlmodel> <out patch.json>

Core ML tools' own save rewrites the whole file in a different field order, which makes a byte patch as big
as the file. Here the protobuf is edited in place: one output added to the model's description, one output
name added to the program's main block, and the lengths of the messages around them corrected.
"""
import hashlib, json, sys
from coremltools.proto import Model_pb2, FeatureTypes_pb2

def varint(n):
    out = bytearray()
    while True:
        b = n & 0x7F; n >>= 7
        out.append(b | (0x80 if n else 0))
        if not n: return bytes(out)

def read_varint(data, pos):
    value = shift = 0
    while True:
        b = data[pos]; pos += 1
        value |= (b & 0x7F) << shift; shift += 7
        if not b & 0x80: return value, pos

def fields(data):
    """(field number, wire type, whole field's bytes, payload for length-delimited fields)."""
    pos, out = 0, []
    while pos < len(data):
        start = pos
        key, pos = read_varint(data, pos)
        number, wire = key >> 3, key & 7
        payload = None
        if wire == 0: _, pos = read_varint(data, pos)
        elif wire == 1: pos += 8
        elif wire == 5: pos += 4
        elif wire == 2:
            length, pos = read_varint(data, pos)
            payload = data[pos:pos + length]; pos += length
        else: raise SystemExit(f"wire type {wire}")
        out.append((number, wire, data[start:pos], payload))
    return out

def delimited(number, payload):
    return varint(number << 3 | 2) + varint(len(payload)) + payload

def rewrite(data, number, change, match=lambda payload: True):
    """The message with its first length-delimited field `number` that matches replaced by change(payload)."""
    out, done = bytearray(), False
    for n, wire, raw, payload in fields(data):
        if not done and n == number and wire == 2 and match(payload):
            out += delimited(n, change(payload)); done = True
        else:
            out += raw
    if not done: raise SystemExit(f"field {number} not found")
    return bytes(out)

def map_key(payload):
    return next(p for n, w, _, p in fields(payload) if n == 1).decode()

source = open(sys.argv[1], "rb").read()
NAME = b"logp_cast_fp16"

# The new output's description: a 16-bit float array, 1 x 750 x 23,863.
feature = Model_pb2.FeatureDescription()
feature.name = NAME.decode()
feature.type.multiArrayType.shape.extend([1, 750, 23863])
feature.type.multiArrayType.dataType = FeatureTypes_pb2.ArrayFeatureType.FLOAT16

# Model { description = 2 { output = 10 }, mlProgram = 502 { functions = 2 { "main": { block_specializations = 3
# { "CoreML8": Block { outputs = 2 } } } } } }
def add_block_output(block): return block + delimited(2, NAME)
def in_block_entry(entry): return rewrite(entry, 2, add_block_output)
def in_function(function): return rewrite(function, 3, in_block_entry, lambda p: map_key(p) == "CoreML8")
def in_function_entry(entry): return rewrite(entry, 2, in_function)
def in_program(program): return rewrite(program, 2, in_function_entry, lambda p: map_key(p) == "main")
patched = rewrite(source, 2, lambda description: description + delimited(10, feature.SerializeToString()))
patched = rewrite(patched, 502, in_program)

# The same model as the one Core ML tools wrote, field for field.
check = Model_pb2.Model(); check.ParseFromString(patched)
assert [o.name for o in check.description.output] == ["token_ids", "token_logprob", "logp_cast_fp16"], [o.name for o in check.description.output]
main = check.mlProgram.functions["main"]
assert list(main.block_specializations["CoreML8"].outputs) == ["token_ids", "token_logprob", "logp_cast_fp16"]

# The byte edits between the two, each (offset in the source, bytes to drop, bytes to put).
ops, i, j = [], 0, 0
while i < len(source) or j < len(patched):
    if i < len(source) and j < len(patched) and source[i] == patched[j]: i += 1; j += 1; continue
    for total in range(1, 200):
        hit = next(((d, total - d) for d in range(total + 1) if source[i + d:i + d + 32] == patched[j + total - d:j + total - d + 32]), None)
        if hit: break
    else: raise SystemExit("no way back in step")
    drop, put = hit
    ops.append((i, drop, patched[j:j + put])); i += drop; j += put
applied, pos = bytearray(), 0
for offset, drop, put in ops:
    applied += source[pos:offset] + put; pos = offset + drop
applied += source[pos:]
assert bytes(applied) == patched
open(sys.argv[2], "wb").write(patched)
json.dump({"source_sha256": hashlib.sha256(source).hexdigest(), "source_bytes": len(source),
           "result_sha256": hashlib.sha256(patched).hexdigest(), "result_bytes": len(patched),
           "edits": [[o, d, p.hex()] for o, d, p in ops]}, open(sys.argv[3], "w"), indent=1)
print(len(ops), "edits,", sum(len(p) for _, _, p in ops), "bytes put,", sum(d for _, d, _ in ops), "dropped")
for o, d, p in ops: print(" ", o, d, p.hex())
print("source", hashlib.sha256(source).hexdigest()); print("result", hashlib.sha256(patched).hexdigest(), len(patched))
