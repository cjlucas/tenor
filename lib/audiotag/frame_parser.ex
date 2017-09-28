defmodule AudioTag.FrameParser do
  @callback matches?(FileReader.t) :: {bool, FileReader.t}
  @callback parse(FileReader.t) :: {:ok, any, FileReader.t} | {:error, term, FileReader.t}
end
