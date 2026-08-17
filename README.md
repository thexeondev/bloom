# Bloom

Client patch for the game **Silver Palace**, implemented to work with [Roze](https://git.xeondev.com/roze/roze)

## Requirements
The only dependency is the Zig Compiler, version `0.17.0-dev.1778+767d25269`: [Linux](https://ziglang.org/builds/zig-x86_64-linux-0.17.0-dev.1778+767d25269.tar.xz)/[Windows](https://ziglang.org/builds/zig-x86_64-windows-0.17.0-dev.1778+767d25269.zip)

#### Supported client versions: CB2 (Global), builds `0.10.80.0` and `0.10.82.1`.

## Setup
First, compile it with zig according to the requirements section.
```sh
$ zig build
```
Next, navigate to the `zig-out/bin` directory, you need 2 files:
- `red_rose.exe`
- `bloom.dll`

Move both files to the client binaries directory: `SilverPalace/Binaries/Win64`

Now, if you have an un-prepared client, you have to move all pak files to their main directory. This is required because this patch disables the hot-update mechanism to avoid accidental complexity on the server side.

- Move all files from `SilverPalace/Saved/PersistentDownloadDir/Paks/` to `SilverPalace/Content/Paks`.
- Move the directory `SilverPalace/Saved/PersistentDownloadDir/LanguagePaks` to be inside of `SilverPalace/Content/Paks`.
- Move all files from `SDKGamedata/Paks/` to `SilverPalace/Content/Paks`.

After this, it must be ready to go. Launch the `red_rose.exe` binary you've copied earlier. If you see a console window appear, it works, you can connect to the server.

## Contributing
[Donate](https://boosty.to/xeondev/donate).

[Join project-specific discord server](https://red-rose.xeondev.com).

[Join ReversedRooms discord server](https://discord.xeondev.com).

[Join ReversedRooms telegram channel](https://t.me/reversedrooms).

The contributions (in form of patches) can be submitted in one of our discord servers. You can also get an account on [our git instance](https://git.xeondev.com/) after a number of accepted contributions.

## License
This repository was made public in the hopes that it will be useful. However, it comes with no warranty whatsoever (expressed or implied).
It's licensed under [GNU Affero General Public License v3](LICENSE).
