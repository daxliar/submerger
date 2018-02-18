# SubMerger - SRT Subtitles Merger

Lua script to merge two input subtitles in SRT format in a new SRT file.  
This tool is meant to help people that are learning new languages and would need to have on screen the two translations at the same time.  
Here is an example of how VLC would playback the file generated (colors are configurable).

![GitHub Logo](/images/submerger.png)

## Usage

It requires first the two input subtitle fils in SRT format then an out SRT file 

```bash
 $ ./submerger.lua <input srt file 1> <input srt file 2> <output srt file> [html color code 1] [html color code 2]
```

### Esample

```bash
$ ./submerger.lua first_language.srt second_language.srt merged.srt
Imported 620 blocks from "first_language.srt"
Imported 587 blocks from "second_language.srt"
Written 514 blocks to "merged.srt"
```

## Requirements

Lua 5.1 or later is required.

## TODO

* Make this command line tool a VLC addon.
