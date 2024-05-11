# zon2rpm

Fork of [zon2nix](https://github.com/nix-community/zon2nix)    
Convert Zig build information to rpm requirements

## Usage

```bash
zon2rpm <option> [path]
zon2rpm buildrequires
zon2rpm buildrequires /path/to/zls
zon2rpm buildrequires /path/to/zls/build.zig.zon
```

Available options are:
- buildrequires
- provides
