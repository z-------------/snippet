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

import ./snippet/types
import ./snippet/api
import ./snippet/tokens
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

# subcommands #

type
  Visibility = enum
    Private = "private"
    Internal = "internal"
    Public = "public"

type
  ListSnippetsResponse = seq[SnippetInfo]
  SnippetInfo = object
    webUrl: string
    title: string
    files: seq[SnippetInfoFile]
    visibility: Visibility
  SnippetInfoFile = object
    path: string
    rawUrl: string

proc listSnippets() =
  let snippets = api("/snippets").fromJson(ListSnippetsResponse)
  for snippet in snippets:
    let visibilityStr =
      if snippet.visibility == Public:
        ""
      else:
        &" ({snippet.visibility})"
    stdout.writeLine(&"{snippet.webUrl} {snippet.title}{visibilityStr}")

type
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
  let isUpdate = updateId != ""

  if not isUpdate and filenames.len == 0:
    raise newException(SnippetError, "No filename(s) provided.")

  var existingFilenames: HashSet[string]
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

  setGitlabInstance(gitlabInstance)
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
    @[a.argKeys, $T, if default.isSome: $default.get else: ""]

  dispatch(snippet)
