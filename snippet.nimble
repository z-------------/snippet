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
requires "jsony >= 1.1.3 & < 2.0.0"
