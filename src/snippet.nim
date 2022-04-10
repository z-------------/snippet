# snippet - Potentially the only command line snippeter.
# Copyright (C) 2022  Zack Guard
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

import std/os
import std/parseopt
import std/httpclient
import std/json
import std/sets
import std/strutils

# TODO: rework options using cligen

const
  ApiBase = "https://gitlab.com/api/v4"
  ConfigDirName = "snippet"

{.experimental: "overloadableEnums".}

type
  Visibility = enum
    Private = "private"
    Internal = "internal"
    Public = "public"

proc getConfigPath(): string =
  getConfigDir() / ConfigDirName

proc createConfigDir() =
  createDir(getConfigPath())

proc getTokenPath(): string =
  getConfigPath() / ".token"

proc readToken(): string =
  let file = open(getTokenPath(), fmRead)
  try:
    result = file.readLine()
  finally:
    file.close()

proc api(endpoint: string; httpMethod: HttpMethod; body = ""): JsonNode =
  let
    headers = newHttpHeaders({
      "Content-Type": "application/json",
      "PRIVATE-TOKEN": readToken(),
    })
    client = newHttpClient(headers = headers)
    response = client.request(ApiBase & endpoint, httpMethod = httpMethod, body = body)
  parseJson(response.body)

proc login(loginToken: string) =
  createConfigDir()
  let file = open(getTokenPath(), fmWrite)
  try:
    file.write(loginToken)
  finally:
    file.close()

proc handleError(response: JsonNode) =
  let error =
    if response.hasKey("error"):
      response["error"].getStr
    elif response.hasKey("message") and response["message"].hasKey("error"):
      response["message"]["error"].getStr
    else:
      ""
  if error != "":
    raise newException(CatchableError, error)

proc modifySnippet(updateId: string; filenames: seq[string]; title: string; visibility: Visibility): string =
  var
    isUpdate = updateId.len > 0
    existingFilenames: HashSet[string]
  if isUpdate:
    # need to get the snippet's existing filenames in order to set file action later
    let snippetInfo = api("/snippets/" & updateId, HttpGet)
    handleError(snippetInfo)
    for fileInfo in snippetInfo["files"]:
      existingFilenames.incl(fileInfo["path"].getStr)
  
  var requestJson = %*{
    "files": [],
    "visibility": $visibility,
    "title": (if title.len > 0: %title else: %(filenames[0])),
  }
  if isUpdate:
    requestJson["id"] = %updateId

  for filename in filenames:
    let file = open(filename, fmRead)
    try:
      let fileContent = file.readAll()
      var fileJson = %*{
        "file_path": filename,
        "content": fileContent,
      }
      if isUpdate:
        fileJson["action"] =
          if filename in existingFilenames:
            %"update"
          else:
            %"create"
      requestJson["files"].add(fileJson)
    finally:
      file.close()

  let
    endpoint = "/snippets" & (if isUpdate: "/" & updateId else: "")
    httpMethod = if isUpdate: HttpPut else: HttpPost
    response = api(endpoint, httpMethod, $requestJson)
  handleError(response)
  $response["id"].getInt

when isMainModule:
  # TODO read token via stdin instead
  var
    updateId = ""
    loginToken = ""
    title = ""
    visibility = Public
    filenames: seq[string]

  var optParser = initOptParser(commandLineParams())
  for kind, key, val in optParser.getOpt():
    case kind
    of cmdArgument:
      filenames.add(key)
    of cmdShortOption, cmdLongOption:
      case key
      of "login":
        loginToken = val
      of "u", "update":
        updateId = val
      of "title":
        title = val
      of "p", "private":
        visibility = Private
      of "visibility":
        visibility = parseEnum[Visibility](val)
    else:
      discard

  if loginToken.len > 0:
    login(loginToken)
    stdout.writeLine("OK")
  else:
    if filenames.len <= 0:
      stderr.writeLine("No filenames provided.")
      quit(QuitFailure)
    let id = modifySnippet(updateId, filenames, title, visibility)
    stdout.writeLine("https://gitlab.com/snippets/" & id)
