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
import std/uri

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

# token helpers #

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

# serialization #

func includeHook[T](v: Option[T]): bool =
  v.isSome

# api helper #

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

# subcommands #

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
    visibility: Option[Visibility]
    title: Option[string]
    id: Option[string]
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

proc modifySnippet(updateId: string; filenames: seq[string]; title: string; visibility: Option[Visibility]) =
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

  var request: ModifySnippetRequest
  request.visibility = visibility
  if title != "":
    request.title = title.some
  elif not isUpdate:
    request.title = filenames[0].some
  if isUpdate:
    request.id = updateId.some

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
      let content = api(&"/snippets/{id}/files/{branchName.get}/{filePath.encodeUrl()}/raw")
      stdout.write(content)
    else:
      raise newException(SnippetError, &"There is no file named '{filePath}' in the snippet. Available files are: " & snippetInfo.files.map(file => file.path).join(", "))

# main #

proc snippet(update = ""; list = false; delete = ""; read = ""; login = false; title = ""; visibility = Visibility.none; private = false; gitlabInstance = "https://gitlab.com"; filenames: seq[string]): int =
  let visibility =
    if private:
      Private.some
    else:
      visibility

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
      modifySnippet(update, filenames, title, visibility)
    QuitSuccess
  except SnippetError as e:
    stderr.writeLine(e.msg)
    QuitFailure

when isMainModule:
  import pkg/cligen
  import pkg/cligen/argcvt

  const NimblePkgVersion {.strDefine.} = "Unknown version"
  cligen.clCfg.version = NimblePkgVersion

  func argParse[T](dest: var Option[T]; default: Option[T]; a: var ArgcvtParams): bool =
    var optVal: T
    if not argParse(optVal, T.default, a):
      return false
    dest = optVal.some
    true

  func argHelp[T](default: Option[T]; a: var ArgcvtParams): seq[string] =
    @[a.argKeys, "Option[" & $T & "]", $default]

  dispatch(snippet)
