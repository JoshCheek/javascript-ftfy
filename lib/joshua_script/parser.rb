require 'json'
require 'open3'

class JoshuaScript
  module Parser
    BIN_DIR  = File.expand_path '../../bin', __dir__
    LOG_DIR  = File.expand_path '../../tmp', __dir__
    PORTFILE = File.join LOG_DIR, 'port'

    require 'net/http'
    require 'json'

    def self.parse(js, first_time=true)
      http         = Net::HTTP.new 'localhost', Parser.port
      request      = Net::HTTP::Post.new '/parse', 'Content-Type' => 'text/plain'
      request.body = js
      response     = http.request request
      json         = JSON.parse response.body, symbolize_names: true
      JoshuaScript::Ast.new json
    rescue Errno::ECONNREFUSED, # port file exists, but server isn't on that port
           Errno::EADDRNOTAVAIL # not sure
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
      start_time = Time.now
      write = File.open '/dev/null' # I think there's an OS indifferent way to do this, but can't remember what it is
      spawn File.join(BIN_DIR, 'parser'), in: :close, out: write
      loop do
        next sleep 0.01 unless File.exist? PORTFILE
        next sleep 0.01 unless start_time < File.mtime(PORTFILE)
        break
      end
      self.port = File.read(PORTFILE).to_i
    ensure
      write && write.close
    end
  end
end
