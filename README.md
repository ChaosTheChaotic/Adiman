<div style="
    background: linear-gradient(145deg, #ffffff0d 0%, #ffffff05 100%);
    padding: 12px 24px;
    border-radius: 12px;
    margin: 20px auto;
    display: inline-flex;
    align-items: center;
    gap: 20px;
    box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
    border: 1px solid #ffffff15;
    backdrop-filter: blur(8px);
    transition: transform 0.2s ease;
">
    <img src="images/Adiman.png" width="82" style="filter: drop-shadow(0 2px 4px rgba(0,0,0,0.1));">
    <h1 style="
        margin: 0;
        font-size: 2.5rem;
        font-weight: 600;
        background: linear-gradient(45deg, #fff 0%, #a0aec0 100%);
        -webkit-background-clip: text;
        background-clip: text;
        color: transparent;
        text-shadow: 0 2px 4px rgba(0,0,0,0.1);
    ">Adiman</h1>
</div>

<a href="https://github.com/flutter/flutter">![](https://img.shields.io/badge/Built%20in-Flutter-%23369FE7)</a>
<a href="https://github.com/fzyzcjy/flutter_rust_bridge">![](https://img.shields.io/badge/Built%20with-Flutter%20Rust%20Bridge-%23369FE7)</a>
<a href="https://ghloc.vercel.app/ChaosTheChaotic/Adiman?branch=main">![](https://img.shields.io/endpoint?url=https://ghloc.vercel.app/api/ChaosTheChaotic/Adiman/badge?style=flat&logo=dart&logoColor=aqua&label=Total%20Lines&color=darkturquoise)</a>

A flutter music player app I made for linux using [flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge) for efficency (as I can't code well) inspired by [namida](https://github.com/namidaco/namida) as you will have seen by the obvious fact that the name is just namida backwards.

# Dependencies (These apply even when not building)

- Ffmpeg
- Spotdl (via python if you want downloading songs to work)

# Installing

(There are only linux builds currently) Head over to [releases](https://github.com/ChaosTheChaotic/Adiman/releases/latest), download the appimage for your architecture, mark executable (if needed) and run the appimage

# Features

- Can play music (duh)
- Adaptive ui
- Playlists
- Downloading songs via spotdl command line (this takes a while due to all the rate limits so unfortunately you just have to wait it out)
- Waveform seekbar
- Lyrics from online source ([lrclib](https://lrclib.net/))
- Shuffle option (mostly untested due to me not using it that often)
- Mpris support
- Shuffling
- Sorting searching
- Artist separators (Also untested due to me not using it that often)
- Caching
- Choosable music folder
- Auto conversion of non-mp3 songs via ffmpeg (if you have many of these files you might have to wait a bit before reloading the library)
- Horribly inefficent code

# Screenshots

<div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; margin-top: 20px;">
  <img src="images/main-screen-2.png" style="border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1);">
  <img src="images/music-player.png" style="border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1);">
  <img src="images/settings.png" style="border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1);">
  <img src="images/download.png" style="border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1);">
  <img src="images/playlists.png" style="border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1);">
  <img src="images/multi-select.png" style="border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1);">
</div>

# Building
To build you must have [flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge) installed, (obviously) the flutter sdk and rust (obviously). You should also have the repo cloned on your machine. To generate the dart to go with the rust you should run `flutter_rust_bridge_codegen generate` and to build the rust you must run `flutter build linux` inside the source directory.

## Helpful people
- DuckTheCrowolf (thevietnamesecrow on discord) for making the logo
