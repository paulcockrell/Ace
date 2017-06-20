defmodule MyServer do
  def start_link(config) do
    Ace.Server.start_link({__MODULE__, config})
  end

  def handle_connect(conn_info, app) do
    partial = {:start_line, conn_info}
    buffer = ""
    {"", {buffer, app, partial, conn_info}}
  end

  def handle_packet(packet, {buffer, app, partial, conn_info}) do
    handle_packet(buffer <> packet, {app, partial, conn_info})
  end
  # Need to handle query string or uri fragment
  # Also will not work if absolute url
  # Would be best to stick as is an look for performance else where
  # Sending the head only is probably a reasonable tradeoff
  def handle_packet("GET /" <> <<a, rest :: binary>>, {a, p, c}) when a in [?\s] do
    {"blob", {"", a, p, c}}
  end
end
