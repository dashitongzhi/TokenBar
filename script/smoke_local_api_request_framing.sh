#!/usr/bin/env bash
set -euo pipefail

API_URL="${TOKENBAR_API_URL:-http://127.0.0.1:3847}"

API_URL="$API_URL" ruby <<'RUBY'
require "socket"
require "uri"

uri = URI(ENV.fetch("API_URL"))
host = uri.host
port = uri.port

def response_for(host, port, chunks)
  socket = TCPSocket.new(host, port)
  chunks.each do |chunk|
    socket.write(chunk)
    sleep 0.05
  end
  response = +""
  loop { response << socket.readpartial(4096) }
rescue EOFError
  socket.close if socket
  response
end

fragmented = response_for(host, port, [
  "GET /health HTTP/1.1\r\nHost: #{host}\r\n",
  "Connection: close\r\n\r\n"
])
abort "fragmented request did not return HTTP 200" unless fragmented.start_with?("HTTP/1.1 200 OK\r\n")
abort "fragmented request did not return TokenBar health payload" unless fragmented.include?(%q{"status":"ok"})

oversized = response_for(host, port, [
  "POST /policy/evaluate HTTP/1.1\r\nHost: #{host}\r\nContent-Length: 1048577\r\nConnection: close\r\n\r\n"
])
abort "oversized request did not return HTTP 413" unless oversized.start_with?("HTTP/1.1 413 Payload Too Large\r\n")

puts "Verified local API HTTP framing: fragmented request succeeds and oversized body is rejected"
RUBY
