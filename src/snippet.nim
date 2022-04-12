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
import std/options
import std/os
import std/sequtils
import std/sets
import std/strformat
import std/strutils
import std/sugar
import std/terminal

{.experimental: "overloadableEnums".}

const
  ApiBase = "/api/v4"
  ConfigDirName = "snippet"

type
  Globals = object
    gitlabInstance: string
  SnippetError = object of CatchableError
  ApiError = object of SnippetError

var
  globals: Globals

proc getConfigPath(): string =
  getConfigDir() / ConfigDirName

proc createConfigDir() =
  createDir(getConfigPath())

proc getTokenPath(): string =
  getConfigPath() / ".token"

proc readToken(): string =
  var file: File
  try:
    file = open(getTokenPath(), fmRead)
    result = file.readLine()
  except IOError:
    raise newException(SnippetError, "Failed to read login token. Please use --login.")
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
    response = client.request(globals.gitlabInstance & ApiBase & endpoint, httpMethod = httpMethod, body = body)
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
  ListSnippetsResponse = seq[SnippetInfo]
  SnippetInfo = object
    webUrl: string
    title: string
    files: seq[SnippetInfoFile]
  SnippetInfoFile = object
    path: string
    rawUrl: string

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

proc modifySnippet(updateId: string; filenames: seq[string]; title: string; visibility: Visibility) =
  if filenames.len <= 0:
    raise newException(SnippetError, "No filename(s) provided.")

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
  stdout.writeLine(response.webUrl)

proc deleteSnippet(id: string) =
  discard api(&"/snippets/{id}", HttpDelete)

proc readSnippet(id: string; filePath: string) =
  if filePath == "":
    let content = api(&"/snippets/{id}/raw")
    stdout.write(content)
  else:
    let snippetInfo = api(&"/snippets/{id}").fromJson(SnippetInfo)
    var
      branchName: Option[string]
    for file in snippetInfo.files:
      if file.path == filePath:
        branchName = file.rawUrl.dup(removeSuffix(filePath)).split('/')[^2].some
        break
    if branchName.isSome:
      let content = api(&"/snippets/{id}/files/{branchName.get}/{filePath}/raw")
      stdout.write(content)
    else:
      raise newException(SnippetError, &"There is no file named '{filePath}' in the snippet. Available files are: " & snippetInfo.files.map(file => file.path).join(", "))

proc snippet(update = ""; list = false; delete = ""; read = ""; login = false; title = ""; visibility = Public; private = false; gitlabInstance = "https://gitlab.com"; filenames: seq[string]): int =
  globals.gitlabInstance = gitlabInstance
  try:
    if login:
      let token = readPasswordFromStdin("Enter token: ")
      writeLoginToken(token)
      stdout.writeLine("OK")
    elif list:
      listSnippets()
    elif delete != "":
      deleteSnippet(delete)
    elif read != "":
      readSnippet(read, if filenames.len >= 1: filenames[0] else: "")
    else:
      modifySnippet(update, filenames, title, if private: Private else: visibility)
    QuitSuccess
  except SnippetError as e:
    stderr.writeLine(e.msg)
    QuitFailure

when isMainModule:
  const NimblePkgVersion {.strDefine.} = "Unknown version"
  cligen.clCfg.version = NimblePkgVersion

  dispatch(snippet)
