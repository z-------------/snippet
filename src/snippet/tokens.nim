# Copyright (C) 2022 Zack Guard
# 
# This file is part of snippet.
# 
# snippet is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# snippet is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with snippet.  If not, see <http://www.gnu.org/licenses/>.

import ./types
import std/os

const
  ConfigDirName = "snippet"

proc getConfigPath(): string =
  getConfigDir() / ConfigDirName

proc createConfigDir() =
  createDir(getConfigPath())

proc getTokenPath(): string =
  getConfigPath() / ".token"

proc readToken*(): string =
  var file: File
  try:
    file = open(getTokenPath(), fmRead)
    result = file.readLine()
  except IOError:
    raise newException(SnippetError, "Failed to read login token. Please use --login.")
  finally:
    file.close()

proc writeLoginToken*(loginToken: string) =
  createConfigDir()
  let file = open(getTokenPath(), fmWrite)
  try:
    file.write(loginToken)
  finally:
    file.close()
