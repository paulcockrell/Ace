defmodule Ace.HTTP.Request do
  @moduledoc """
  This should eventually be extracted to Raxx as interface

  start-line (request-line)
  +(header-line)
  CRLF
  [message-body]
  """

  # def parse(raw) do
  #   {start_line, rest} <- parse_start_line(raw)
  #
  # end

  @request_line_limit 8000
  @empty_lines_limit 1

  @doc """

  ## Examples

      # iex> "GET / HTTP/1.1\\r\\n"
      # ...> |> parse_start_line()
      # {:ok, {:GET, "/", {1, 1}}, ""}
      #
      # iex> "\\r\\nGET / HTTP/1.1\\r\\n"
      # ...> |> parse_start_line()
      # {:GET, "/", {1, 1}}
      #
      # The request-line must not start with whitespace.
      # iex> " GET / HTTP/1.1\\r\\n"
      # ...> |> parse_start_line()
      # {:error, _}
  """
  def parse_start_line(buffer) do
    parse_method(buffer, @request_line_limit)
  end

  def parse_method(" " <> _rest, _rem) do
    {:error, :whitespace_start}
  end
  # macro to write method limits multiple runs with different known methods
  # however could have a `use Request.Parser methods: [:CUSTOM]`
  def parse_method("GET " <> rest, rem) do
    parse_uri(rest, rem - 4)
  end
  def parse_method(start_line, rem) do
    unknown_method(start_line)
  end

  def unknown_method(start_line) do

  end

  def parse_uri(" " <> _rest, rem) do
    {:error, :single_space_only}
  end
  def parse_uri(buffer"/" <> _rest, rem) do
    URI.parse
    {:error, :single_space_only}
  end

end
