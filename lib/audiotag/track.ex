defmodule Track do
  alias AudioTag.ID3v2.Frame.{Text, APIC}

  defstruct artist: nil, sort_artist: nil, name: nil, album_name: nil, images: []

  def from_frames(frames) do
    Enum.reduce(frames, %Track{}, fn frame, track ->
      case frame do
        %Text{frame_id: "TPE1", text: text} ->
          %{track | artist: text}
        %Text{frame_id: "TSO2", text: text} ->
          %{track | sort_artist: text}
        %Text{frame_id: "TIT2", text: text} ->
          %{track | name: text}
        %Text{frame_id: "TALB", text: text} ->
          %{track | album_name: text}
        %APIC{} ->
          %{track | images: [frame | track.images]}
        _ ->
          track
      end
    end)
  end
end
