[![Build Status](https://github.com/ytdl-org/youtube-dl/workflows/CI/badge.svg)](https://github.com/ytdl-org/youtube-dl/actions?query=workflow%3ACI)


youtube-dl - download videos from youtube.com or other video platforms

- [INSTALLATION](#installation)
- [DESCRIPTION](#description)
- [OPTIONS](#options)
- [CONFIGURATION](#configuration)
- [OUTPUT TEMPLATE](#output-template)
- [FORMAT SELECTION](#format-selection)
- [VIDEO SELECTION](#video-selection)
- [FAQ](#faq)
- [DEVELOPER INSTRUCTIONS](#developer-instructions)
- [EMBEDDING YOUTUBE-DL](#embedding-youtube-dl)
- [BUGS](#bugs)
- [COPYRIGHT](#copyright)

# INSTALLATION

To install it right away for all UNIX users (Linux, macOS, etc.), type:

    sudo curl -L https://yt-dl.org/downloads/latest/youtube-dl -o /usr/local/bin/youtube-dl
    sudo chmod a+rx /usr/local/bin/youtube-dl

If you do not have curl, you can alternatively use a recent wget:

    sudo wget https://yt-dl.org/downloads/latest/youtube-dl -O /usr/local/bin/youtube-dl
    sudo chmod a+rx /usr/local/bin/youtube-dl

Windows users can [download an .exe file](https://yt-dl.org/latest/youtube-dl.exe) and place it in any location on their [PATH](https://en.wikipedia.org/wiki/PATH_%28variable%29) except for `%SYSTEMROOT%\System32` (e.g. **do not** put in `C:\Windows\System32`).

You can also use pip:

    sudo -H pip install --upgrade youtube-dl

This command will update youtube-dl if you have already installed it. See the [pypi page](https://pypi.python.org/pypi/youtube_dl) for more information.

macOS users can install youtube-dl with [Homebrew](https://brew.sh/):

    brew install youtube-dl

Or with [MacPorts](https://www.macports.org/):

    sudo port install youtube-dl

Alternatively, refer to the [developer instructions](#developer-instructions) for how to check out and work with the git repository. For further options, including PGP signatures, see the [youtube-dl Download Page](https://ytdl-org.github.io/youtube-dl/download.html).

# DESCRIPTION
**youtube-dl** is a command-line program to download videos from YouTube.com and a few more sites. It requires the Python interpreter, version 2.6, 2.7, or 3.2+, and it is not platform specific. It should work on your Unix box, on Windows or on macOS. It is released to the public domain, which means you can modify it, redistribute it or use it however you like.

    youtube-dl [OPTIONS] URL [URL...]

# OPTIONS
    -h, --help                           Print this help text and exit
    --version                            Print program version and exit
    -U, --update                         Update this program to latest version.
                                         Make sure that you have sufficient
                                         permissions (run with sudo if needed)
    -i, --ignore-errors                  Continue on download errors, for
                                         example to skip unavailable videos in a
                                         playlist
    --abort-on-error                     Abort downloading of further videos (in
                                         the playlist or the command line) if an
                                         error occurs
    --dump-user-agent                    Display the current browser
                                         identification
    --list-extractors                    List all supported extractors
    --extractor-descriptions             Output descriptions of all supported
                                         extractors
    --force-generic-extractor            Force extraction to use the generic
                                         extractor
    --default-search PREFIX              Use this prefix for unqualified URLs.
                                         For example "gvsearch2:" downloads two
                                         videos from google videos for youtube-
                                         dl "large apple". Use the value "auto"
                                         to let youtube-dl guess ("auto_warning"
                                         to emit a warning when guessing).
                                         "error" just throws an error. The
                                         default value "fixup_error" repairs
                                         broken URLs, but emits an error if this
                                         is not possible instead of searching.
    --ignore-config                      Do not read configuration files. When
                                         given in the global configuration file
                                         /etc/youtube-dl.conf: Do not read the
                                         user configuration in
                                         ~/.config/youtube-dl/config
                                         (%APPDATA%/youtube-dl/config.txt on
                                         Windows)
    --config-location PATH               Location of the configuration file;
                                         either the path to the config or its
                                         containing directory.
    --flat-playlist                      Do not extract the videos of a
                                         playlist, only list them.
    --mark-watched                       Mark videos watched (YouTube only)
    --no-mark-watched                    Do not mark videos watched (YouTube
                                         only)
    --no-color                           Do not emit color codes in output

## Network Options:
    --proxy URL                          Use the specified HTTP/HTTPS/SOCKS
                                         proxy. To enable SOCKS proxy, specify a
                                         proper scheme. For example
                                         socks5://127.0.0.1:1080/. Pass in an
                                         empty string (--proxy "") for direct
                                         connection
    --socket-timeout SECONDS             Time to wait before giving up, in
                                         seconds
    --source-address IP                  Client-side IP address to bind to
    -4, --force-ipv4                     Make all connections via IPv4
    -6, --force-ipv6                     Make all connections via IPv6

## Geo Restriction:
    --geo-verification-proxy URL         Use this proxy to verify the IP address
                                         for some geo-restricted sites. The
                                         default proxy specified by --proxy (or
                                         none, if the option is not present) is
                                         used for the actual downloading.
    --geo-bypass                         Bypass geographic restriction via
                                         faking X-Forwarded-For HTTP header
    --no-geo-bypass                      Do not bypass geographic restriction
                                         via faking X-Forwarded-For HTTP header
    --geo-bypass-country CODE            Force bypass geographic restriction
                                         with explicitly provided two-letter ISO
                                         3166-2 country code
    --geo-bypass-ip-block IP_BLOCK       Force bypass geographic restriction
                                         with explicitly provided IP block in
                                         CIDR notation

## Video Selection:
    --playlist-start NUMBER              Playlist video to start at (default is
                                         1)
    --playlist-end NUMBER                Playlist video to end at (default is
                                         last)
    --playlist-items ITEM_SPEC           Playlist video items to download.
                                         Specify indices of the videos in the
                                         playlist separated by commas like: "--
                                         playlist-items 1,2,5,8" if you want to
                                         download videos indexed 1, 2, 5, 8 in
                                         the playlist. You can specify range: "
                                         --playlist-items 1-3,7,10-13", it will
                                         download the videos at index 1, 2, 3,
                                         7, 10, 11, 12 and 13.
    --match-title REGEX                  Download only matching titles (regex or
                                         caseless sub-string)
    --reject-title REGEX                 Skip download for matching titles
                                         (regex or caseless sub-string)
    --max-downloads NUMBER               Abort after downloading NUMBER files
    --min-filesize SIZE                  Do not download any videos smaller than
                                         SIZE (e.g. 50k or 44.6m)
    --max-filesize SIZE                  Do not download any videos larger than
                                         SIZE (e.g. 50k or 44.6m)
    --date DATE                          Download only videos uploaded in this
                                         date
    --datebefore DATE                    Download only videos uploaded on or
                                         before this date (i.e. inclusive)
    --dateafter DATE                     Download only videos uploaded on or
                                         after this date (i.e. inclusive)
    --min-views COUNT                    Do not download any videos with less
                                         than COUNT views
    --max-views COUNT                    Do not download any videos with more
                                         than COUNT views
    --match-filter FILTER                Generic video filter. Specify any key
                                         (see the "OUTPUT TEMPLATE" for a list
                                         of available keys) to match if the key
                                         is present, !key to check if the key is
                                         not present, key > NUMBER (like
                                         "comment_count > 12", also works with
                                         >=, <, <=, !=, =) to compare against a
                                         number, key = 'LITERAL' (like "uploader
                                         = 'Mike Smith'", also works with !=) to
                                         match against a string literal and & to
                                         require multiple matches. Values which
                                         are not known are excluded unless you
                                         put a question mark (?) after the
                                         operator. For example, to only match
                                         videos that have been liked more than
                                         100 times and disliked less than 50
                                         times (or the dislike functionality is
                                         not available at the given service),
                                         but who also have a description, use
                                         --match-filter "like_count > 100 &
                                         dislike_count <? 50 & description" .
    --no-playlist                        Download only the video, if the URL
                                         refers to a video and a playlist.
    --yes-playlist                       Download the playlist, if the URL
                                         refers to a video and a playlist.
    --age-limit YEARS                    Download only videos suitable for the
                                         given age
    --download-archive FILE              Download only videos not listed in the
                                         archive file. Record the IDs of all
                                         downloaded videos in it.
    --include-ads                        Download advertisements as well
                                         (experimental)

## Download Options:
    -r, --limit-rate RATE                Maximum download rate in bytes per
                                         second (e.g. 50K or 4.2M)
    -R, --retries RETRIES                Number of retries (default is 10), or
                                         "infinite".
    --fragment-retries RETRIES           Number of retries for a fragment
                                         (default is 10), or "infinite" (DASH,
                                         hlsnative and ISM)
    --skip-unavailable-fragments         Skip unavailable fragments (DASH,
                                         hlsnative and ISM)
    --abort-on-unavailable-fragment      Abort downloading when some fragment is
                                         not available
    --keep-fragments                     Keep downloaded fragments on disk after
                                         downloading is finished; fragments are
                                         erased by default
    --buffer-size SIZE                   Size of download buffer (e.g. 1024 or
                                         16K) (default is 1024)
    --no-resize-buffer                   Do not automatically adjust the buffer
                                         size. By default, the buffer size is
                                         automatically resized from an initial
                                         value of SIZE.
    --http-chunk-size SIZE               Size of a chunk for chunk-based HTTP
                                         downloading (e.g. 10485760 or 10M)
                                         (default is disabled). May be useful
                                         for bypassing bandwidth throttling
                                         imposed by a webserver (experimental)
    --playlist-reverse                   Download playlist videos in reverse
                                         order
    --playlist-random                    Download playlist videos in random
                                         order
    --xattr-set-filesize                 Set file xattribute ytdl.filesize with
                                         expected file size
    --hls-prefer-native                  Use the native HLS downloader instead
                                         of ffmpeg
    --hls-prefer-ffmpeg                  Use ffmpeg instead of the native HLS
                                         downloader
    --hls-use-mpegts                     Use the mpegts container for HLS
                                         videos, allowing to play the video
                                         while downloading (some players may not
                                         be able to play it)
    --external-downloader COMMAND        Use the specified external downloader.
                                         Currently supports aria2c,avconv,axel,c
                                         url,ffmpeg,httpie,wget
    --external-downloader-args ARGS      Give these arguments to the external
                                         downloader

## Filesystem Options:
    -a, --batch-file FILE                File containing URLs to download ('-'
                                         for stdin), one URL per line. Lines
                                         starting with '#', ';' or ']' are
                                         considered as comments and ignored.
    --id                                 Use only video ID in file name
    -o, --output TEMPLATE                Output filename template, see the
                                         "OUTPUT TEMPLATE" for all the info
    --output-na-placeholder PLACEHOLDER  Placeholder value for unavailable meta
                                         fields in output filename template
                                         (default is "NA")
    --autonumber-start NUMBER            Specify the start value for
                                         %(autonumber)s (default is 1)
    --restrict-filenames                 Restrict filenames to only ASCII
                                         characters, and avoid "&" and spaces in
                                         filenames
    -w, --no-overwrites                  Do not overwrite files
    -c, --continue                       Force resume of partially downloaded
                                         files. By default, youtube-dl will
                                         resume downloads if possible.
    --no-continue                        Do not resume partially downloaded
                                         files (restart from beginning)
    --no-part                            Do not use .part files - write directly
                                         into output file
    --no-mtime                           Do not use the Last-modified header to
                                         set the file modification time
    --write-description                  Write video description to a
                                         .description file
    --write-info-json                    Write video metadata to a .info.json
                                         file
    --write-annotations                  Write video annotations to a
                                         .annotations.xml file
    --load-info-json FILE                JSON file containing the video
                                         information (created with the "--write-
                                         info-json" option)
    --cookies FILE                       File to read cookies from and dump
                                         cookie jar in
    --cache-dir DIR                      Location in the filesystem where
                                         youtube-dl can store some downloaded
                                         information permanently. By default
                                         $XDG_CACHE_HOME/youtube-dl or
                                         ~/.cache/youtube-dl . At the moment,
                                         only YouTube player files (for videos
                                         with obfuscated signatures) are cached,
                                         but that may change.
    --no-cache-dir                       Disable filesystem caching
    --rm-cache-dir                       Delete all filesystem cache files

## Thumbnail Options:
    --write-thumbnail                    Write thumbnail image to disk
    --write-all-thumbnails               Write all thumbnail image formats to
                                         disk
    --list-thumbnails                    Simulate and list all available
                                         thumbnail formats

## Verbosity / Simulation Options:
    -q, --quiet                          Activate quiet mode
    --no-warnings                        Ignore warnings
    -s, --simulate                       Do not download the video and do not
                                         write anything to disk
    --skip-download                      Do not download the video
    -g, --get-url                        Simulate, quiet but print URL
    -e, --get-title                      Simulate, quiet but print title
    --get-id                             Simulate, quiet but print id
    --get-thumbnail                      Simula
