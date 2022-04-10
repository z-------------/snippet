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

import pkg/cligen
import std/os
import std/httpclient
import std/json
import std/sets
import std/strutils
import std/strformat

{.experimental: "overloadableEnums".}

const
  ApiBase = "https://gitlab.com/api/v4" # TODO: make this configurable at runtime
  ConfigDirName = "snippet"

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

proc api(endpoint: string; httpMethod = HttpGet; body = ""): JsonNode =
  let
    headers = newHttpHeaders({
      "Content-Type": "application/json",
      "PRIVATE-TOKEN": readToken(),
    })
    client = newHttpClient(headers = headers)
    response = client.request(ApiBase & endpoint, httpMethod = httpMethod, body = body)
  parseJson(response.body)

proc writeLoginToken(loginToken: string) =
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

proc listSnippets() =
  let snippetInfos = api("/snippets")
  for snippetInfo in snippetInfos:
    let
      webUrl = snippetInfo["web_url"].getStr
      title = snippetInfo["title"].getStr
    stdout.writeLine([webUrl, title].join(" "))

proc modifySnippet(updateId: string; filenames: seq[string]; title: string; visibility: Visibility): string =
  var
    isUpdate = updateId.len > 0
    existingFilenames: HashSet[string]
  if isUpdate:
    # need to get the snippet's existing filenames in order to set file action later
    let snippetInfo = api(&"/snippets/{updateId}")
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
  response["web_url"].getStr

proc main(update = ""; list = false; login = ""; title = ""; visibility = Public; private = false; filenames: seq[string]): int =
  # TODO read token via stdin instead
  if login.len > 0:
    writeLoginToken(login)
    stdout.writeLine("OK")
  elif list:
    listSnippets()
  else:
    if filenames.len <= 0:
      stderr.writeLine("No filenames provided.")
      return QuitFailure
    let snippetUrl = modifySnippet(update, filenames, title, if private: Private else: visibility)
    stdout.writeLine(snippetUrl)
  QuitSuccess

when isMainModule:
  dispatch(main)
