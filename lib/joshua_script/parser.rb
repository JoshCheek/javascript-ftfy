require 'set'
require 'json'
require 'net/http'

class JoshuaScript
  module Parser
    SyntaxError = Class.new RuntimeError

    BIN_DIR  = File.expand_path '../../bin', __dir__
    LOG_DIR  = File.expand_path '../../tmp', __dir__
    PORTFILE = File.join LOG_DIR, 'port'

    def self.parse(js, first_time=true, print_every_line: false)
      http         = Net::HTTP.new 'localhost', Parser.port
      request      = Net::HTTP::Post.new '/parse', 'Content-Type' => 'text/plain'
      request.body = js
      response     = http.request request
      json         = JSON.parse response.body, symbolize_names: true
      if response.code == '200'
        json       = print_every_line json if print_every_line
        JoshuaScript::Ast.new json, source: js
      else
        message = json.fetch(:error)
        raise SyntaxError, message
      end
    rescue Errno::ECONNREFUSED, # port file exists, but server isn't on that port
           Errno::EADDRNOTAVAIL # not sure
      raise unless first_time
      Parser.start_server
      return parse(js, false, print_every_line: print_every_line)
    end

    def self.port=(port)
      @port = port
    end

    def self.port
      @port ||= File.exist?(PORTFILE) ? File.read(PORTFILE) : start_server
    end

    def self.start_server
      Dir.mkdir LOG_DIR unless Dir.exist? LOG_DIR
      # precision isn't high enough that the portfile's time is always after the start time,
      # so use precision of only seconds, and subtract a second from it to reduce infinite loops from precision issues
      start_time = Time.now.to_i - 1 # 1 second ago, to account for imprecise timing
      write = File.open '/dev/null' # I think there's an OS indifferent way to do this, but can't remember what it is
      spawn File.join(BIN_DIR, 'parser'), in: :close, out: write
      loop do
        next sleep 0.01 unless File.exist? PORTFILE
        next sleep 0.01 unless start_time <= File.mtime(PORTFILE).to_i
        break
      end
      self.port = File.read(PORTFILE).to_i
    ensure
      write && write.close
    end

    def self.print_every_line(json)
      recorded = record_printables json
      printables = Set.new recorded.map { |_, r| r[:obj] }
      wrap_printables json, printables
    end

    def self.record_printables(json, recorded={})
      if should_record?(json, recorded)
        line = json[:loc][:end][:line]
        recorded[line] = json[:loc].dup
        recorded[line][:obj] = json
      end

      case json
      when Hash
        json.each do |key, value|
          next if key == :type || key == :loc || key == :params
          record_printables value, recorded
        end
      when Array
        json.each { |val| record_printables val, recorded }
      end
      recorded
    end

    NONRECORDABLES = %w[
      Identifier
      Property
      VariableDeclarator
      VariableDeclaration
      ImportDeclaration
    ].map(&:freeze).freeze
    def self.should_record?(potential, recorded)
      return false unless potential.kind_of? Hash
      return false unless loc = potential[:loc]
      return false if NONRECORDABLES.include? potential[:type]
      return true  unless prev = recorded[loc[:end][:line]]
      return true  if loc[:end][:column] > prev[:end][:column]
      return false
    end

    def self.wrap_printables(json, printables)
      case json
      when Hash
        new_json = json.map { |k, v|
          [k, wrap_printables(v, printables)]
        }.to_h
        if printables.include? json
          {type: "I SEE YA!", loc: json[:loc], to_record: new_json}
        else
          new_json
        end
      when Array
        json.map { |e| wrap_printables e, printables }
      else
        json
      end
    end
  end
end
