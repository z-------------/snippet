import std/options

func includeHook*[T](v: Option[T]): bool =
  v.isSome
