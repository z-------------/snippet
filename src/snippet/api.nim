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
import ./json
import ./tokens
import pkg/jsony
import std/httpclient

export json

const
  ApiBase = "/api/v4"

type
  ApiResponse = object
    message: ApiResponseMessage
    error: string
  ApiResponseMessage = object
    error: string
  ApiError* = object of SnippetError
  Config = object
    gitlabInstance: string

var
  config: Config

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
  code.is2xx

proc api*(endpoint: string; httpMethod = HttpGet; body = ""): string =
  assert config.gitlabInstance != ""

  let
    headers = newHttpHeaders({
      "Content-Type": "application/json",
      "PRIVATE-TOKEN": readToken(),
    })
    client = newHttpClient(headers = headers)
    response = client.request(config.gitlabInstance & ApiBase & endpoint, httpMethod = httpMethod, body = body)
  if not response.code.isOk:
    raise newException(ApiError, $response.code)
  try:
    handleError(response.body.fromJson(ApiResponse))
  except JsonError:
    discard
  response.body

proc api*(endpoint: string; httpMethod = HttpGet; body: auto): string =
  api(endpoint, httpMethod, body.toJson())

proc setGitlabInstance*(gitlabInstance: sink string) =
  config.gitlabInstance = gitlabInstance
