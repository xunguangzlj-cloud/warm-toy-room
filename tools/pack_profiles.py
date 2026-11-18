"""由完整网页包生成按硬件选择的无损资源包。用法：python tools/pack_profiles.py docs"""
import gzip
import hashlib
import itertools
import json
from pathlib import Path
import re
import struct
import sys
import zlib

site = Path(sys.argv[1])
manifest = json.loads((site / 'payload.js').read_text(encoding='utf8').split('=', 1)[1].strip().rstrip(';'))
asset = manifest['index.pck']
source = gzip.decompress(b''.join((site / part['path']).read_bytes() for part in asset['parts']))
base, index = struct.unpack_from('<QQ', source, 24)
assert base == 112
count, = struct.unpack_from('<I', source, index)
cursor = index + 4
files = {}
for _ in range(count):
    size, = struct.unpack_from('<I', source, cursor)
    cursor += 4
    name = source[cursor:cursor + size].rstrip(b'\0').decode()
    cursor += size
    offset, size, checksum, flags = struct.unpack_from('<QQ16sI', source, cursor)
    cursor += 36
    data = memoryview(source)[base + offset:base + offset + size]
    assert hashlib.md5(data).digest() == checksum and flags == 0, name
    files[name] = data

# 装入本仓库的场景入口，交互控制器与基础游戏脚本保持原包内容。
files['extension/rooms.gd'] = (Path(__file__).resolve().parents[1] / 'extension/rooms.gd').read_bytes()

families = [('s3tc', 'etc2'), ('bptc', 'astc')]
choices = {pair: {k: {} for k in (*pair, 'both')} for pair in families}
imports = set()
variants = set()
pattern = re.compile(rb'^path\.(\w+)="res://([^"]+)"\r?$', re.M)
for name, data in files.items():
    if not name.endswith('.import'):
        continue
    raw = bytes(data)
    matches = pattern.findall(raw)
    if not matches:
        continue
    pair = tuple(tag.decode() for tag, _ in matches)
    group = choices[pair]
    imports.add(name)
    for tag, target in matches:
        tag, target = tag.decode(), target.decode()
        variants.add(target)
        group[tag][target] = files[target]
        # 已验证该设备支持此版本，直接指定路径，使纹理和光照贴图互相独立。
        group[tag][name] = pattern.sub(lambda m: b'path="res://' + m[2] + b'"' if m[1].decode() == tag else b'', raw)
        group['both'][target] = files[target]
    group['both'][name] = data

def deflate(data, final=False):
    encoder = zlib.compressobj(8, zlib.DEFLATED, -15)
    return encoder.compress(data) + encoder.flush(zlib.Z_FINISH if final else zlib.Z_FULL_FLUSH)

def save_chunks(data):
    parts = []
    for start in range(0, len(data), 4 << 20):
        block = data[start:start + (4 << 20)]
        path = 'payload/opt-' + hashlib.sha256(block).hexdigest()[:24] + '.bin'
        if not (site / path).exists():
            (site / path).write_bytes(block)
        parts.append({'path': path, 'bytes': len(block)})
    return parts

def pack_group(entries):
    body = bytearray()
    lookup, offsets = {}, {}
    for name, data in sorted(entries.items()):
        md5 = hashlib.md5(data).digest()
        if md5 not in offsets:
            offsets[md5] = len(body)
            body.extend(data)
            body.extend(bytes(-len(body) % 16))
        lookup[name] = (offsets[md5], len(data), md5)
    return body, lookup, save_chunks(deflate(body))

groups = {'common': pack_group({n: d for n, d in files.items() if n not in imports and n not in variants})}
for pair, choice in choices.items():
    for tag in pair:
        groups[tag] = pack_group(choice[tag])
    # 双格式兼容时只额外存储原始导入表，无需复制两组大纹理。
    groups['imports-' + pair[0]] = pack_group({n: d for n, d in choice['both'].items() if n in imports})

profiles = {}
for a, b in itertools.product((*families[0], 'both'), (*families[1], 'both')):
    order = ['common']
    for tag, pair in zip((a, b), families):
        order.extend([*pair, 'imports-' + pair[0]] if tag == 'both' else [tag])
    rows = {}
    position = 0
    for label in order:
        body, lookup, _ = groups[label]
        for name, (offset, size, checksum) in lookup.items():
            rows[name] = struct.pack('<QQ16sI', position + offset, size, checksum, 0)
        position += len(body)
    directory = bytearray(struct.pack('<I', len(rows)))
    for name, entry in sorted(rows.items()):
        key = name.encode()
        key += bytes(-len(key) % 4)
        directory.extend(struct.pack('<I', len(key)) + key + entry)
    header = bytearray(source[:base])
    struct.pack_into('<Q', header, 32, base + position)
    head = save_chunks(b'\x1f\x8b\x08\0\0\0\0\0\0\xff' + deflate(header))
    crc = zlib.crc32(header)
    for label in order:
        crc = zlib.crc32(groups[label][0], crc)
    length = base + position + len(directory)
    footer = save_chunks(deflate(directory, True) + struct.pack('<II', zlib.crc32(directory, crc), length))
    assert len(head) == len(footer) == 1
    profiles[a + '-' + b] = {'head': head[0], 'groups': order, 'tail': footer[0], 'originalBytes': length}
    # 流式复核组合的 gzip 完整性、资源索引顺序及实际内容。
    decoder = zlib.decompressobj(31)
    data_hash, expected = hashlib.sha256(), hashlib.sha256()
    expected.update(header)
    for label in order:
        expected.update(groups[label][0])
    expected.update(directory)
    all_parts = head + [part for label in order for part in groups[label][2]] + footer
    for part in all_parts:
        data_hash.update(decoder.decompress((site / part['path']).read_bytes()))
    assert decoder.eof and data_hash.digest() == expected.digest()
    print(a, b, sum(p['bytes'] for p in all_parts), length, flush=True)
config = {'groups': {name: group[2] for name, group in groups.items()}, 'profiles': profiles}
(site / 'profiles.js').write_text('globalThis.TOYROOM_PROFILES=' + json.dumps(config, separators=(',', ':')) + ';', encoding='utf8')
