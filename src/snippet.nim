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
import pkg/jsony
import std/httpclient
import std/os
import std/sets
import std/strformat
import std/strutils
import std/terminal

{.experimental: "overloadableEnums".}

const
  ApiBase = "https://gitlab.com/api/v4" # TODO: make this configurable at runtime
  ConfigDirName = "snippet"

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

proc writeLoginToken(loginToken: string) =
  createConfigDir()
  let file = open(getTokenPath(), fmWrite)
  try:
    file.write(loginToken)
  finally:
    file.close()

type
  ApiResponse = object
    message: ApiResponseMessage
    error: string
  ApiResponseMessage = object
    error: string
  ApiError = object of CatchableError

proc handleError(response: ApiResponse) =
  let error =
    if response.error != "":
      response.error
    elif response.message.error != "":
      response.message.error
    else:
      ""
  if error != "":
    raise newException(ApiError, error)

func isOk(code: HttpCode): bool =
  not (code.is4xx or code.is5xx)

proc api(endpoint: string; httpMethod = HttpGet; body = ""): string =
  let
    headers = newHttpHeaders({
      "Content-Type": "application/json",
      "PRIVATE-TOKEN": readToken(),
    })
    client = newHttpClient(headers = headers)
    response = client.request(ApiBase & endpoint, httpMethod = httpMethod, body = body)
  if not response.code.isOk:
    raise newException(ApiError, $response.code)
  try:
    handleError(response.body.fromJson(ApiResponse))
  except JsonError:
    discard
  response.body

proc api(endpoint: string; httpMethod = HttpGet; body: auto): string =
  api(endpoint, httpMethod, body.toJson())

type
  ListSnippetsResponse = seq[ListSnippetsItem]
  ListSnippetsItem = object
    webUrl: string
    title: string

proc listSnippets() =
  let snippetInfos = api("/snippets").fromJson(ListSnippetsResponse)
  for snippetInfo in snippetInfos:
    stdout.writeLine([snippetInfo.webUrl, snippetInfo.title].join(" "))

type
  Visibility = enum
    Private = "private"
    Internal = "internal"
    Public = "public"
  SnippetResponse = object
    files: seq[SnippetFile]
  SnippetFile = object
    path: string
  ModifySnippetRequest = object
    files: seq[ModifySnippetFile]
    visibility: Visibility
    title: string
    id: string
  ModifySnippetFile = object
    file_path: string # XXX is there a way to tell jsony to convert to snake_case when serializing?
    content: string
    action: ModifySnippetFileAction
  ModifySnippetFileAction = enum
    Create = "create"
    Update = "update"
    Delete = "delete"
    Move = "move"
  ModifySnippetResponse = object
    webUrl: string

proc modifySnippet(updateId: string; filenames: seq[string]; title: string; visibility: Visibility): string =
  var
    isUpdate = updateId.len > 0
    existingFilenames: HashSet[string]
  if isUpdate:
    # need to get the snippet's existing filenames in order to set file action later
    let snippetInfo = api(&"/snippets/{updateId}").fromJson(SnippetResponse)
    for fileInfo in snippetInfo.files:
      existingFilenames.incl(fileInfo.path)
  
  var request = ModifySnippetRequest(
    visibility: visibility,
    title: (if title.len > 0: title else: filenames[0]),
  )
  if isUpdate:
    request.id = updateId

  for filename in filenames:
    let file = open(filename, fmRead)
    try:
      let fileContent = file.readAll()
      var fileJson = ModifySnippetFile(
        filePath: filename,
        content: fileContent,
      )
      if isUpdate:
        fileJson.action =
          if filename in existingFilenames:
            Update
          else:
            Create
      request.files.add(fileJson)
    finally:
      file.close()

  let
    endpoint = "/snippets" & (if isUpdate: "/" & updateId else: "")
    httpMethod = if isUpdate: HttpPut else: HttpPost
    response = api(endpoint, httpMethod, request).fromJson(ModifySnippetResponse)
  response.webUrl

proc deleteSnippet(id: string) =
  discard api(&"/snippets/{id}", HttpDelete)

proc snippet(update = ""; list = false; delete = ""; login = false; title = ""; visibility = Public; private = false; filenames: seq[string]): int =
  if login:
    let token = readPasswordFromStdin("Enter token: ")
    writeLoginToken(token)
    stdout.writeLine("OK")
  elif list:
    listSnippets()
  elif delete != "":
    deleteSnippet(delete)
  else:
    if filenames.len <= 0:
      stderr.writeLine("No filenames provided.")
      return QuitFailure
    let snippetUrl = modifySnippet(update, filenames, title, if private: Private else: visibility)
    stdout.writeLine(snippetUrl)
  QuitSuccess

when isMainModule:
  dispatch(snippet)
