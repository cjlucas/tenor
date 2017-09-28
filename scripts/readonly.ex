System.argv
|> Enum.map(&Path.join(&1, "**/*.mp3"))
|> Enum.map(&Path.wildcard/1)
|> List.flatten
|> Enum.each(fn fname ->
  data = File.read!(fname)
  IO.puts byte_size(data)
end)
