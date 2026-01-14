# sm-3ds

<!-- ![banner](resources/ghpreview.png) -->
![ceres station on Azahar](screenshots/sm-3ds.gif)

This is a 3DS port of Super Metroid, based on [the PC port by snesrev](https://github.com/snesrev/sm).

This runs at about 50fps on hardware per my testing.
If you switch to the backup SNES emulation mode this gets back to 60, but audio will not work.
And where's the fun in that anyways?
With some careful optimization, this could surely hit 60fps.

Saves are dubious right now, I have them working in emulation but not on hardware.
They should be stored in the SD card's `saves` directory.

![title screen on Azahar](screenshots/titlescreen.png)

## Building

### Setup

```bash
# Install devkitARM - https://devkitpro.org/wiki/Getting_Started

# Clone
git clone --recurse-submodules https://github.com/CharlesAverill/sm-3ds.git

# Install bannertool
git clone https://github.com/carstene1ns/3ds-bannertool.git --depth=1 && cd 3ds-bannertool
cmake -B build && cmake --build build && sudo cmake --install build
cd ..

# Install makerom
git clone https://github.com/3DSGuy/Project_CTR.git --depth=1
make -C Project_CTR/makerom deps -j
make -C Project_CTR/makerom program -j
sudo cp Project_CTR/makerom/bin/makerom /usr/bin

cd sm-3ds

# Place your copy of Super Metroid in romfs
cp ~/Games/sm.smc romfs

# Build SDL2
make sdl

# Build sm-3ds
make -j FULL_NATIVE=1
```

| Make Commands    | Action                                                                                    |
| -----------------| ----------------------------------------------------------------------------------------- |
| make             | 
| make 3ds         | The 3ds target will build a `<project name>.3ds` file.
| make 3dsx        | The 3dsx target will build both a `<project name>.3dsx` and a `<project name>.smdh` files.
| make cia         | The cia target will build a `<project name>.cia` file.
| make azahar      | The azahar target will build a `<project name>.3dsx` file and automatically run azahar.
| make elf         | The elf target will build a `<project name>.elf` file.
| make fbi         | The fbi target will build a `<project name>.cia` file and send it to your 3ds via [FBI].
| make hblauncher  | The hblauncher target will build a `<project name>.3dsx` file and send your 3ds via homebrew launcher.<sup>2</sup>
| make release     | The release target will build `.elf`, `.3dsx`, `.cia`, `.3ds` files and a zip file (.3dsx and .smdh only).<sup>3</sup>
