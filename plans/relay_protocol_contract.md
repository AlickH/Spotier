# Spotier Relay Protocol v1 Contract

Spotier Swift core uses a Spotier-owned relay protocol. It does not speak the existing EasyTier relay wire protocol in this implementation pass.

## Transport

- `tcp://host:port` opens a plain TCP relay stream.
- `tls://host:port` opens a TLS relay stream.
- No other relay URL schemes are accepted.
- The relay connection is an explicit transport. Reconnect happens only when the caller starts a new `RelayTransport`.

## Record Format

Each relay stream carries length-prefixed encrypted records:

```text
uint32_be record_length
uint64_be sequence
bytes encrypted_core_frame
```

- `record_length` is the number of bytes after the length field.
- `record_length` includes the 8-byte sequence and encrypted frame bytes.
- `record_length` must be greater than or equal to 8.
- A receiver waits for the complete record before decoding it.
- Multiple complete records can be decoded from one stream chunk.

## Encryption

- `encrypted_core_frame` is produced by `SessionCrypto`.
- The sequence number in the relay record is authenticated by `SessionCrypto` associated data.
- The decrypted plaintext is a Spotier `CoreFrame` encoded by `FrameCodec`.

## Compatibility Decision

- Existing EasyTier relay compatibility is intentionally out of scope.
- Spotier-owned relay v1 is the only relay protocol supported by this Swift core pass.
- A future EasyTier compatibility layer must be a separate protocol decision, not mixed into v1.
