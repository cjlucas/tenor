defmodule AudioTag.ID3v2.Frame do
  defmodule TXXX do
    defstruct [:description, :value]
  end

  defmodule Text do
    defstruct [:frame_id, :text]
  end

  defmodule APIC do
    defstruct [:mime_type, :type, :description, :data]
  end

  defmodule Unknown do
    defstruct [:frame_id, :data]
  end

  def parse_frame({"TXXX", _size, _flags, _data} = frame) do
    {_, encoding, text} = parse_text_frame(frame)
   
    # parse_text_frame handles the conversion to utf8, leaving us with a binary
    # where the description and value are seperated by a single NULL byte
    {desc, value} = split_encoded_text(0, text)

    %TXXX{description: desc, value: value}
  end

  def parse_frame({<<"T", _::binary>>, _size, _flags, _dara} = frame) do
    {frame_id, _, text} = parse_text_frame(frame)
    %Text{frame_id: frame_id, text: text}
  end

  def parse_frame({"APIC", _size, _flags, data}) do
    <<encoding, rest::binary>> = data

    {mime_type, <<type, rest::binary>>} = split_encoded_text(encoding, rest)
    {description, data} = split_encoded_text(encoding, rest)

    %APIC{mime_type: mime_type, type: type, description: description, data: data}
  end

  def parse_frame({frame_id, _size, _flags, data}) do
    %Unknown{frame_id: frame_id, data: data}
  end

  def parse_text_frame({frame_id, _size, _flags, data} = frame) do
    <<encoding, text::binary>> = data
    {frame_id, encoding, text} =
      case text do
        "" ->
          {frame_id, encoding, text}
        _ ->
          case encoding do
            0 ->
              {frame_id, encoding, text}
            1 ->
              <<bom::bytes-size(2), text::binary>> = text
              endianness =
                case bom do
                  <<255, 254>> -> :little
                  <<254, 255>> -> :big
                end

              {frame_id, encoding, :unicode.characters_to_binary(text, {:utf16, endianness})}
            2 ->
              {frame_id, encoding, :unicode.characters_to_binary(text, {:utf16, :big})}
            3 ->
              {frame_id, encoding, text}
          end
      end

    # HACK: Although the ID3v2.4 spec states that any encoded text must be
    # terminated either by $00 or $00 00 (for 8-bit and 16-bit encodings respectively),
    # but some tag writers may not write these terminating NULL bytes.
    #
    # As the text is already converted from its original encoding to UTF-8 at this
    # point, we can check to see if their is a terminating $00, and remove it.
    text =
      if byte_size(text) > 0 && :binary.at(text, byte_size(text) - 1) == 0 do
        sz = byte_size(text) - 1
        <<text::bytes-size(sz), _::binary>> = text
        text
      else
        text
      end

    {frame_id, encoding, text}
  end

  defp split_encoded_text(encoding, bin) do
    delim =
      case encoding do
        0 -> <<0>>
        1 -> <<0, 0>>
        2 -> <<0, 0>>
        3 -> <<0>>
      end

    {offset, len} = :binary.match(bin, delim)

    <<left::bytes-size(offset), _::bytes-size(len), rest::binary>> = bin
    {left, rest}
  end
end

