import snippet {.all.}
import ./mockapi

import std/unittest
import std/httpcore
import std/json
import std/options

const
  SnippetFilename = "tests/snippet.txt"
  SnippetContent = staticRead("snippet.txt")

suite "request construction":
  test "list snippets":
    setResponse("[]")
    listSnippets()
    check getRequest() == ""

  test "modify snippet -- create (1)":
    setResponse("{}")
    modifySnippet(updateId = "", filenames = @[SnippetFilename], title = "Test Snippet", visibility = Private.some)
    check getRequest().parseJson() == %*{
      "files": [{
        "file_path": SnippetFilename,
        "content": SnippetContent,
        "action": "create",
      }],
      "visibility": "private",
      "title": "Test Snippet",
    }

  test "modify snippet -- create (2)":
    setResponse("{}")
    modifySnippet(updateId = "", filenames = @[SnippetFilename], title = "Test Snippet", visibility = Visibility.none)
    check getRequest().parseJson() == %*{
      "files": [{
        "file_path": SnippetFilename,
        "content": SnippetContent,
        "action": "create",
      }],
      "title": "Test Snippet",
    }

  test "modify snippet -- update (1)":
    setResponse("{}")
    modifySnippet(updateId = "69420", filenames = @[SnippetFilename], title = "Test Snippet", visibility = Visibility.none)
    check getRequest().parseJson() == %*{
      "id": "69420",
      "files": [{
        "file_path": SnippetFilename,
        "content": SnippetContent,
        "action": "create",
      }],
      "title": "Test Snippet",
    }

  test "modify snippet -- update (2)":
    setResponse("{}")
    modifySnippet(updateId = "69420", filenames = @[SnippetFilename], title = "", visibility = Public.some)
    check getRequest().parseJson() == %*{
      "id": "69420",
      "files": [{
        "file_path": SnippetFilename,
        "content": SnippetContent,
        "action": "create",
      }],
      "visibility": "public",
    }
