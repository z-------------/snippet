import snippet/json
import pkg/jsony
import std/httpcore

export json

var
  request: string
  response: string

proc setResponse*(response: sink string) =
  mockapi.response = response

proc getRequest*(): lent string =
  request

proc api*(endpoint: string; httpMethod = HttpGet; body = ""): string =
  request = body
  response

proc api*(endpoint: string; httpMethod = HttpGet; body: auto): string =
  api(endpoint, httpMethod, body.toJson())

proc setGitlabInstance*(gitlabInstance: string) =
  discard
