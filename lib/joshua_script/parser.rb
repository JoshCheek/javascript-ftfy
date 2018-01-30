require 'json'
require 'open3'

class JoshuaScript
  module Parser
    BIN_DIR  = File.expand_path '../../bin', __dir__
    LOG_DIR  = File.expand_path '../../log', __dir__
    OUT_LOG  = File.join LOG_DIR, 'out.log'
    ERR_LOG  = File.join LOG_DIR, 'err.log'
    PORTFILE = File.join LOG_DIR, 'port'

    require 'net/http'
    require 'json'

    def self.parse(js, first_time=true)
      http         = Net::HTTP.new 'localhost', Parser.port
      request      = Net::HTTP::Post.new '/parse', 'Content-Type' => 'text/plain'
      request.body = js
      response     = nil
      response   = http.request request
      raw        = response.body
      json       = JSON.parse raw, symbolize_names: true
      JoshuaScript::Ast.new json
    rescue Errno::ECONNREFUSED # port file exists, but server isn't on that port  # =>
      raise unless first_time
      Parser.start_server
      return parse(js, false)
    end

    def self.port=(port)
      @port = port
    end

    def self.port
      @port ||= File.exist?(PORTFILE) ? File.read(PORTFILE) : start_server
    end

    def self.start_server
      Dir.mkdir LOG_DIR unless Dir.exist? LOG_DIR
      out = File.open OUT_LOG, 'w'
      err = File.open ERR_LOG, 'w'
      start_time = Time.now
      spawn File.join(BIN_DIR, 'parser'), in: :close, out: out, err: err
      loop do
        next sleep 0.01 unless File.exist? PORTFILE
        next sleep 0.01 unless start_time < File.stat(PORTFILE).mtime
        break
      end
      self.port = File.read(PORTFILE).to_i
    ensure
      out && out.close
      err && err.close
    end
  end
end
