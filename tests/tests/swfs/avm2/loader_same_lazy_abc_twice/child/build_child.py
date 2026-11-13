#!/usr/bin/env python3
"""
build_child.py <Child.abc> <child.swf>

Builds child.swf with a real library, which asc.jar alone can't produce: a DefineShape (a 40x20 px
rectangle, id 1), a DefineSprite (id 2) placing it, the code (DoABC) and a SymbolClass linking
sprite 2 to ChildClip and the movie to Child.

    java -jar tools/asc/asc.jar -import playerglobal.abc -in ChildClip.as Child.as
    python3 build_child.py Child.abc ../child.swf
"""
import struct
import sys


class Bits:
    def __init__(self):
        self.out = bytearray()
        self.acc = 0
        self.n = 0

    def put(self, value, nbits):
        for i in range(nbits - 1, -1, -1):
            self.acc = (self.acc << 1) | ((value >> i) & 1)
            self.n += 1
            if self.n == 8:
                self.out.append(self.acc)
                self.acc = self.n = 0

    def sbits(self, value, nbits):
        self.put(value & ((1 << nbits) - 1), nbits)

    def flush(self):
        if self.n:
            self.out.append(self.acc << (8 - self.n))
            self.acc = self.n = 0
        return bytes(self.out)


def rect(xmin, xmax, ymin, ymax, nbits=16):
    b = Bits()
    b.put(nbits, 5)
    for v in (xmin, xmax, ymin, ymax):
        b.sbits(v, nbits)
    return b.flush()


def tag(code, body=b""):
    if len(body) < 63:
        return struct.pack("<H", (code << 6) | len(body)) + body
    return struct.pack("<HI", (code << 6) | 63, len(body)) + body


def define_shape(char_id, w, h):
    # twips
    W, H = w * 20, h * 20
    body = struct.pack("<H", char_id) + rect(0, W, 0, H)
    # one solid fill (red), no line styles
    body += bytes([1, 0x00, 0xCC, 0x00, 0x00]) + bytes([0])
    b = Bits()
    b.put(1, 4)  # NumFillBits
    b.put(0, 4)  # NumLineBits
    # StyleChangeRecord: moveTo(0,0) + FillStyle1 = 1
    b.put(0, 1)  # non-edge
    b.put(0, 1)  # StateNewStyles
    b.put(0, 1)  # StateLineStyle
    b.put(1, 1)  # StateFillStyle1
    b.put(0, 1)  # StateFillStyle0
    b.put(1, 1)  # StateMoveTo
    b.put(1, 5)
    b.sbits(0, 1)
    b.sbits(0, 1)
    b.put(1, 1)  # FillStyle1 index
    # straight edges, 16 bits per coordinate
    for dx, dy in ((W, 0), (0, H), (-W, 0), (0, -H)):
        b.put(1, 1)  # edge
        b.put(1, 1)  # straight
        b.put(16 - 2, 4)  # NumBits - 2
        if dy == 0:
            b.put(0, 1)  # not general line
            b.put(0, 1)  # horizontal
            b.sbits(dx, 16)
        else:
            b.put(0, 1)
            b.put(1, 1)  # vertical
            b.sbits(dy, 16)
    b.put(0, 6)  # EndShapeRecord
    return tag(2, body + b.flush())


def define_sprite(char_id, shape_id):
    place = tag(26, bytes([0x02]) + struct.pack("<HH", 1, shape_id))  # PlaceObject2: HasCharacter
    body = struct.pack("<HH", char_id, 1) + place + tag(1) + tag(0)
    return tag(39, body)


def symbol_class(pairs):
    body = struct.pack("<H", len(pairs))
    for cid, name in pairs:
        body += struct.pack("<H", cid) + name.encode() + b"\0"
    return tag(76, body)


def main():
    abc = open(sys.argv[1], "rb").read()
    tags = (
        tag(69, struct.pack("<I", 0x08))  # FileAttributes: ActionScript 3
        + tag(9, bytes([0xFF, 0xFF, 0xFF]))  # SetBackgroundColor
        + define_shape(1, 40, 20)
        + define_sprite(2, 1)
        + tag(82, struct.pack("<I", 1) + b"\0" + abc)  # DoABC, lazy
        + symbol_class([(2, "ChildClip"), (0, "Child")])
        + tag(1)
        + tag(0)
    )
    body = rect(0, 200 * 20, 0, 200 * 20) + struct.pack("<HH", 24 << 8, 1) + tags
    swf = b"FWS" + bytes([11]) + struct.pack("<I", 8 + len(body)) + body
    open(sys.argv[2], "wb").write(swf)


if __name__ == "__main__":
    main()
