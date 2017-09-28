defmodule AudioTag.FrameParser do
  @callback matches?(FileReader.t) :: {bool, FileReader.t}
  @callback parse(FileReader.t) :: {FileReader.t, any}
end
