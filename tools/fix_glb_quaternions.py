#!/usr/bin/env python3
"""Corrige a continuidade dos quaternions de rotação em um .glb.

## O defeito

O bake das animações grava `rotation_quaternion` quadro a quadro. O Blender pode
gravar `q` em um quadro e `-q` no seguinte: as duas representações são a **mesma
rotação**, mas o sinal numérico é oposto. A interpolação entre elas passa pelo
caminho longo — o osso gira quase 180° em um único passo.

Medido no modelo atual (canal `forearm.r`):

| clipe | trocas de sinal no GLB | trocas depois do import na Godot |
| --- | --- | --- |
| `walking` | 0 | 0 |
| `jog` | 4 | **4** |
| `swing_loop` | 4 | 4 |

A Godot importa rotações de glTF como track `TYPE_VALUE` (valor bruto), **não**
como `TYPE_ROTATION_3D`. Só o segundo tipo recebe a correção automática de
continuidade do motor. Por isso a troca de sinal sobrevive ao import e aparece em
jogo como o personagem "se mexendo sozinho" / tremendo.

## A correção

Percorrer cada canal de rotação e trocar o sinal de uma chave quando
`dot(chave_anterior, chave_atual) < 0`. Como `q` e `-q` são a mesma rotação, isso
**não altera a pose** em nenhum quadro: muda apenas o caminho da interpolação,
que passa a ser o curto.

Uso:
    python3 tools/fix_glb_quaternions.py <entrada.glb> [saida.glb]

Sem saída informada, grava no próprio arquivo (com backup `.bak`).
"""

from __future__ import annotations

import json
import struct
import sys


def _read_accessor(gltf, blob, index):
    acc = gltf["accessors"][index]
    view = gltf["bufferViews"][acc["bufferView"]]
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    comp_size = 4  # float32
    n_comp = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[acc["type"]]
    stride = view.get("byteStride") or comp_size * n_comp
    out = []
    for k in range(acc["count"]):
        off = start + k * stride
        out.append(struct.unpack_from("<" + "f" * n_comp, blob, off))
    return out, start, stride, n_comp


def _write_accessor(blob, start, stride, values):
    """Regrava os valores no mesmo lugar (mesmo tamanho em bytes)."""
    buf = bytearray(blob)
    for k, vals in enumerate(values):
        off = start + k * stride
        struct.pack_into("<" + "f" * len(vals), buf, off, *vals)
    return bytes(buf)


def fix_quaternions(path_in: str, path_out: str | None = None) -> int:
    data = open(path_in, "rb").read()
    if data[:4] != b"glTF":
        raise SystemExit("nao e um arquivo glb: %s" % path_in)

    magic, version, total = struct.unpack_from("<III", data, 0)
    off = 12
    json_chunk = None
    bin_chunk = None
    bin_offset = None
    while off < total:
        clen, ctype = struct.unpack_from("<II", data, off)
        payload = data[off + 8 : off + 8 + clen]
        if ctype == 0x4E4F534A:  # JSON
            json_chunk = payload
        elif ctype == 0x004E4942:  # BIN
            bin_chunk = payload
            bin_offset = off + 8
        off += 8 + clen

    gltf = json.loads(json_chunk)
    blob = bin_chunk

    total_flips = 0
    for anim in gltf.get("animations", []):
        for channel in anim.get("channels", []):
            if channel["target"]["path"] != "rotation":
                continue
            sampler = anim["samplers"][channel["sampler"]]
            quats, start, stride, n_comp = _read_accessor(gltf, blob, sampler["output"])
            if n_comp != 4:
                continue
            flips = 0
            fixed = [quats[0]]
            for k in range(1, len(quats)):
                prev = fixed[-1]
                cur = quats[k]
                dot = sum(prev[i] * cur[i] for i in range(4))
                if dot < 0.0:
                    cur = tuple(-c for c in cur)
                    flips += 1
                fixed.append(cur)
            if flips:
                blob = _write_accessor(blob, start, stride, fixed)
                total_flips += flips

    if total_flips == 0:
        print("nenhuma troca de sinal encontrada; nada a fazer.")
        return 0

    # Remonta o GLB com o BIN modificado.
    json_bytes = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    json_bytes += b" " * ((4 - len(json_bytes) % 4) % 4)
    bin_bytes = blob + b"\x00" * ((4 - len(blob) % 4) % 4)
    out = bytearray()
    out += struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(json_bytes) + 8 + len(bin_bytes))
    out += struct.pack("<II", len(json_bytes), 0x4E4F534A) + json_bytes
    out += struct.pack("<II", len(bin_bytes), 0x004E4942) + bin_bytes

    target = path_out or path_in
    if target == path_in:
        open(path_in + ".bak", "wb").write(data)
    open(target, "wb").write(bytes(out))
    print("corrigidas %d trocas de sinal -> %s" % (total_flips, target))
    return total_flips


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    fix_quaternions(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
