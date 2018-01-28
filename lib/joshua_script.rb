require 'pp'
require 'json'
require 'open3'
require 'continuation'
require 'joshua_script/ast'


class JoshuaScript
  ESPARSE = File.expand_path "../node_modules/.bin/esparse", __dir__

  def self.eval(js)
    out, err, status = Open3.capture3(ESPARSE, '--loc', stdin_data: js)
    raise err unless status.success?
    ast = JSON.parse out, symbolize_names: true
    js = new
    js.enqueue Ast.new(ast)
    js.run
  end

  def initialize
    @workers = []
    @queue   = Queue.new
    @globals = {
      'showTime'   => method(:show_time),
      'setTimeout' => method(:set_timeout),
    }
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
      result = evaluate @queue.shift, [@globals]
    end
    result
  end

  private

  # options are passed b/c of the output of esprima.
  # If this was for real, I'd transform their AST into my own internal
  # representation, but this is really just a thought experiment, so whatevz.
  def evaluate(ast, vars, identifier: :resolve)
    if ast.respond_to? :call
      return invoke(ast, vars, ast, [])
    end

    case ast.fetch :type
    when 'Program'
      ast.fetch(:body).map { |child| evaluate child, vars }.last
    when 'Invooooooooke!' # FIXME: should just be CallExpression?
      code = ast.fetch :code
      params = code.fetch :params
      not_implemented if params.any?
      body = code.fetch(:body)
      evaluate body, vars
    when 'Identifier'
      id = ast.fetch :name
      if identifier == :resolve
        vars.last.fetch id
      else
        id
      end
    when 'ExpressionStatement'
      expr = ast.fetch(:expression)
      evaluate expr, vars
    when 'CallExpression'
      method = evaluate ast.fetch(:callee), vars
      args   = ast.fetch(:arguments).map { |arg| evaluate arg, vars }
      invoke ast, vars, method, args
    when 'Literal'
      value = ast.fetch :value
      value = value.to_f if value.kind_of? Integer
      value
    when 'BlockStatement'
      body = ast.fetch :body
      body.each { |child| evaluate child, vars }
    when 'ArrowFunctionExpression'
      ast
    when 'ArrayExpression'
      ast.fetch(:elements).map { |child| evaluate child, vars }
    when 'ObjectExpression'
      ast.fetch(:properties).each_with_object({}) do |prop, obj|
        key = prop.fetch(:key)
        if key.fetch(:type) == "Identifier"
          key = key.fetch(:name)
        else
          key = key.fetch(:value)
        end
        value = evaluate prop.fetch(:value), vars
        obj[key] = value
      end
    when 'BinaryExpression'
      operator = ast.fetch :operator
      left     = evaluate ast.fetch(:left), vars
      right    = evaluate ast.fetch(:right), vars
      left.send operator, right
    when 'VariableDeclaration'
      ast.fetch(:declarations).each { |dec| evaluate dec, vars }
    when 'VariableDeclarator'
      name  = ast.fetch(:id).fetch(:name)
      value = evaluate ast.fetch(:init), vars
      vars.last[name] = value
    else
      require "pry"
      binding.pry
    end
  end


  # Have to take empty kwargs here b/c Ruby has a bug.
  # I reported it here: https://bugs.ruby-lang.org/issues/14415
  def set_timeout(cb=nil, ms, **)
    # pp cb
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
    raise NotImplementedError, 'lol not even implemented', caller
  end

  def show_time(ast:, **)
    line = ast.fetch(:loc).fetch(:end).fetch(:line)
    time = ((Time.now - @start)*1000).to_i.to_s + ' ms'
    puts "[#{line}, #{time.inspect}]"
  end

  def invoke(ast, vars, invokable, args)
    if invokable.respond_to? :call
      keywords = {}
      params   = []
      params   = invokable.parameters if invokable.respond_to? :parameters
      keywords[:ast] = ast if params.include? [:keyreq, :ast]
      invokable.call *args, **keywords
    else
      require "pry"
      binding.pry
    end
  end

end
