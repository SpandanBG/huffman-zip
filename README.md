# Compression Format:
```
<extra_bits_len>[<char><no of u8s>[<u8s>, ...], ...]<encoding>
```

- `<encoding>` : Post the huffman tree is created, the data is read again and and encoded in a list of u8s. For the last u8, if there are space for extra bits as padding, 0s are added.
- `<extra_bits_len>` : The number of padding 0s added to the last u8 if any.
- `[<char><no of u8s>[<u8s>, ...], ...]` : The huff man tree built
    - `<char>` : The character that is encoded.
    - `[<u8s>, ...]` : The encoding is store in a u64. this is split in to [8]u8 to efficiently store.
    - `<no of u8s>` : Instead of storing the entire 8 u8s, we only store the valid number of u8s. This holds the info on how many form the total of 8 have been stored.
