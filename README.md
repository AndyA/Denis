# denis: Extract Unique Lines From a Text File

What, like `uniq(1)`? Yes, a bit like that but removing uniq's restriction that the repeated lines have to be adjacent in the input. When the input data is too large to sort - or you need to preserve its order - `uniq` can't help you but `denis` can.

`denis` computes the sha256 hash of every line in its input and stores those hashes in a hashset. It outputs only those lines that it hasn't hashed previously. This means it uses memory in proportion to the number of unique lines in the input - 33 bytes per line or around 3.1GB per hundred million distinct lines. Apart from that there's no limit on the input size.

If you know the upper bound of the number of unique lines you can use the `--millions` option to pre-allocate enough storage. For example:

```sh
# We're expecting fewer than 200,000,000 uniques
$ denis --millions 200 dupes.json > dedup.json
```

If you don't pre-allocate the hashmap in this way it will grow as it fills by doubling in size when it becomes full. Because the hashmap is a single contiguous chunk of memory this pattern of allocations that you use about twice as much total memory as you would have if you had been able to use `--millions` or `-M` initially.

## Usage

```
USAGE:
  denis [OPTIONS] <files>...

ARGUMENTS:
  files   Files to process. Use '-' for stdin.

OPTIONS:
  -M, --millions <VALUE>   Pre-size the hash map to hold this many million entries.
  -h, --help               Show this help output.
      --color <VALUE>      When to use colors (*auto*, never, always).
```

## Examples

### Processing a list of files

```sh
$ denis dupes/*.txt > deduped.txt
```

### Reading STDIN

```sh
$ cat dupes/*.txt | denis --millions 200 - > deduped.txt
```

### Processing lots of files with progress (using `pv`)

```sh
$ find dupes -name '*.txt' -print0 \
  | xargs -0r cat                  \
  | pv -c --name input             \
  | denis -                        \
  | pv -c --name output > deduped.txt
```

## Building

To build `denis` [download](https://ziglang.org/download/) and install zig and then:

```sh
$ zig build -Doptimize=ReleaseFast
$ mv zig-out/bin/denis ~/.local/bin
```

Replace the bin directory with your preference.

## License

The MIT License (MIT)

Copyright (c) 2025 Andy Armstrong <andy@hexten.net>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
