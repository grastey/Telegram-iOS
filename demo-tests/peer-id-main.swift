import Foundation

// Buffer serialization is not exercised by the identity tests below.
public final class WriteBuffer {
    public func write<T>(_ value: inout T, offset: Int, length: Int) {}
}
public final class ReadBuffer {
    public var memory = UnsafeMutableRawPointer.allocate(byteCount: 8, alignment: 8)
    public var offset = 0
    public func read<T>(_ value: inout T, offset: Int, length: Int) {}
    deinit { memory.deallocate() }
}

for raw in [Int64(101), 7_059_873_186, 8_119_118_768, 38_183_889_840] {
    let peer = PeerId(namespace: ._internalFromInt32Value(0), id: ._internalFromInt64Value(raw))
    precondition(peer.id._internalGetInt64Value() == raw)
    precondition(PeerId(peer.toInt64()).id._internalGetInt64Value() == raw)
    if raw > Int64(UInt32.max) { precondition(peer.toInt64() != raw) }
}
print("Raw Telegram IDs remain distinct from packed Postbox IDs, including both test accounts")
