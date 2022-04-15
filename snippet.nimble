# Package

version       = "0.0.0"
author        = "Zack Guard"
description   = "Potentially the only command line snippeter."
license       = "GPL-3.0-or-later"
srcDir        = "src"
bin           = @["snippet"]


# Dependencies

requires "nim >= 1.6.4"
requires "cligen >= 1.5.23 & < 2.0.0"
requires "https://github.com/z-------------/jsony < 2.0.0"
