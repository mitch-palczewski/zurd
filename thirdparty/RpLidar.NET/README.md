# RpLidar.NET (vendored, patched)

Serial driver for Slamtec RPLIDAR A-series sensors, used by `scripts/lidar/LidarDevice.cs`.

- **Upstream:** <https://github.com/asheesh1996/RpLidar.NET>
- **Version:** NuGet `RpLidar.NET` 1.1.0, source commit `767d7192bea537049b27e0fc944e5f2eab687e19`
- **License:** MIT, see [LICENSE](LICENSE)

The source is copied in, not referenced as a NuGet package, because the packaged driver loses data
in Sensitivity mode (the mode an A1 uses). The files compile straight into the `zurd` assembly;
namespaces are unchanged (`RpLidar.NET`, `RpLidar.NET.Entities`, ...), so our code still uses
`using RpLidar.NET;`.

Only the library project's `.cs` files are copied. Its `.csproj`, the example app and the README
are not. `.editorconfig` here compiles the files the way upstream does (no nullable checks, the
same warnings silenced), and `thirdparty/.gdignore` keeps Godot from scanning the folder, since
none of it is Godot script.

## Patches

Every change is marked with a `// zurd patch:` comment. All are in the Sensitivity/Boost
("express scan", ultra-capsule) decoding path.

1. **Points lost at every serial read** (`RpLidarSerialDevice.ParseExpressData`,
   `RplidarProcessedResult.IsTrailer`, `DataResponseHelper.WaitUltraCapsuledNode`). A capsule's 96
   points can only be decoded once the next capsule arrives. The parser always ends with an item
   that only carries leftover bytes, and the driver treated that item like a bad packet and forgot
   the previous capsule. So the first capsule of every read produced nothing: a wedge of about 25°
   lost per read, a third to a half of all points. Because the lost wedges shift each rotation, the
   picture blinked between halves of the room.
2. **Points lost around 0°** (`ParseExpressData`). The driver also forgot the previous capsule at
   every rotation start, and dropped the capsule that crosses 0° on every other rotation. The C SDK
   does neither; the angle maths already handles the wrap.
3. **Bytes parsed twice** (`ParseExpressData`, `_prevData`). In some cases already-parsed bytes
   stayed in the buffer and were decoded again. The buffer now holds exactly the unparsed bytes.
4. **Phantom points** (`UltraCapsuleToNormal`). The "invalid prediction" marker -512 was compared
   against `0xFFFFFE00`, which C compares as unsigned (so it equals -512) but C# compares as a
   `uint` (so it never matches). Invalid samples came out as points 2–4 m closer than the real
   surface.

Checked offline by feeding the same synthetic Sensitivity-mode byte stream, cut into random
serial-read-sized chunks, through the original and the patched decoder: the original returned
about 60% of the points with gaps of up to 51° and phantom points; the patched one returned every
point, full 360° coverage and no phantoms.

## Known gaps (not fixed)

- **Standard mode returns no points.** `WaitAndParseData` has no decoder for it. On an A1 use
  Sensitivity.
- **Boost mode** is for A2/A3, per upstream's README.
- `RpLidarSerialDevice.Start()` retries forever without sleeping when the port is bad, and
  `Connect()` swallows open errors. `LidarDevice` avoids both and never calls `Start()`.

## Updating

To take a newer upstream version: copy the library project's `.cs` files over these, then re-apply
the patches above (search for `// zurd patch:` in the old copy first), and check whether upstream
has fixed any of them.
