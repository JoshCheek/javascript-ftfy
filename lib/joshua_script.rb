require 'json'
require 'open3'
require 'continuation'

class JoshuaScript
  ESPARSE = File.expand_path "../node_modules/.bin/esparse", __dir__
  def self.eval(js)
    out, err, status = Open3.capture3(ESPARSE, '--loc', stdin_data: js)
    raise err unless status.success?
    ast = JSON.parse out, symbolize_names: true
    js = new
    js.enqueue ast
    js.run
  end

  def initialize
    @workers = []
    @queue   = Queue.new
  end

  def enqueue(code)
    @queue << code
    self
  end

  def run
    @start = Time.now
    result = nil
    # whenever pause is called, we will continue executing code from here
    callcc { |continuation| @pause = continuation }
    loop do
      @workers.select! &:alive?
      break if @queue.empty? && @workers.empty?
      result = evaluate @queue.shift
    end
    result
  end

  private

  def evaluate(ast)
    if ast.respond_to? :call
      return ast.call
    end

    case ast.fetch :type
    when 'Program'
      ast.fetch(:body).map { |child| evaluate child }.last
    when 'Invooooooooke!'
      code = ast.fetch :code
      params = code.fetch :params
      not_implemented if params.any?
      body = code.fetch(:body)
      evaluate body
    when 'ExpressionStatement'
      expr = ast.fetch(:expression)
      evaluate expr
    when 'Identifier'
      name = ast.fetch :name
      case name
      when 'showTime'
        line = ast.fetch(:loc).fetch(:end).fetch(:line)
        puts "[#{line}, #{show_time @start, Time.now}]"
      when 'setTimeout'
        method(:set_timeout)
      else
        not_implemented
      end
    when 'CallExpression'
      method = evaluate ast.fetch(:callee)
      args = ast.fetch(:arguments).map { |arg| evaluate arg }
      method.call *args
    when 'Literal'
      ast.fetch :value
    when 'BlockStatement'
      body = ast.fetch :body
      body.each { |child| evaluate child }
    when 'ArrowFunctionExpression'
      ast
      # id = ast.fetch(:id)
      # raise "Found an id: #{id.inspect}" if id
      # params = ast.fetch :params
      # raise "Found params: #{params.inspect}" if params
      # body = ast.fetch :body
    when 'ArrayExpression'
      ast.fetch(:elements).map { |child| evaluate child }
    when 'ObjectExpression'
      ast.fetch(:properties).each_with_object({}) do |prop, obj|
        key = prop.fetch(:key)
        if key.fetch(:type) == "Identifier"
          key = key.fetch(:name)
        else
          key = key.fetch(:value)
        end
        value = evaluate prop.fetch(:value)
        obj[key] = value
      end
    else
      require "pry"
      binding.pry
    end
  end


  def set_timeout(cb=nil, ms)
    cb &&= {type: 'Invooooooooke!', code: cb}

    timeout = lambda do |code|
      @workers << Thread.new do
        Thread.current.abort_on_exception = true
        sleep ms/1000.0
        enqueue code
      end
      Thread.pass # gets the sleeper thread running sooner
    end

    # return immediately if callback was given
    return timeout[cb] if cb

    # no callback, so pause execution until we timeout
    callcc do |continuation|
      timeout[continuation]
      @pause.call
    end
  end

  def not_implemented
    raise 'lol not even implemented'
  end

  def show_time(start, stop)
    time = ((stop - start)*1000).to_i.to_s + ' ms'
    time.inspect
  end

end
