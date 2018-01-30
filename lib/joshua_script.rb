require 'pp'
require 'json'
require 'open3'
require 'continuation'
require 'joshua_script/ast'

# TODO:
# * Switch from continuations to fibers
# * make vars fiber local so we don't have to pass them through every call to evaluate

module Parser
  BIN_DIR  = File.expand_path '../bin', __dir__
  LOG_DIR  = File.expand_path '../log', __dir__
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

class JoshuaScript
  ESPARSE = File.expand_path "../node_modules/.bin/esparse", __dir__

  def self.eval(source, stdout:)
    js = new stdout: stdout
    js.enqueue Parser.parse source
    js.run
  end

  def initialize(stdout:)
    @stdout  = stdout
    @workers = []
    @queue   = Queue.new
    @globals = {
      'showTime'    => method(:show_time),
      'setTimeout'  => method(:set_timeout),
      'showVersion' => method(:show_version),
      'console'     => {
        'log' => method(:console_log),
      },
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
    return ast unless ast

    if ast.respond_to? :call
      return invoke(ast, vars, ast, [])
    end

    case ast.fetch :type
    when 'Program'
      ast.fetch(:body).map { |child| evaluate child, vars }.last
    when 'Identifier'
      id = ast.fetch :name
      if identifier == :resolve
        scope = find_scope vars, id
        raise "Undefined: #{id}" if !scope # FIXME: untested temp(?) hack
        scope[id]
      else
        id
      end
    when 'ExpressionStatement'
      expr = ast.fetch(:expression)
      evaluate expr, vars
    when 'Invooooooooke!' # FIXME: should just be CallExpression?
      code = ast.fetch :code
      params = code.fetch :params
      not_implemented if params.any?
      body = code.fetch(:body)
      evaluate body, vars
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
      body.map { |child| evaluate child, vars }.last
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
    when 'AssignmentExpression'
      name  = evaluate ast.fetch(:left), vars, identifier: :to_string
      value = evaluate ast.fetch(:right), vars
      scope = find_scope vars, name
      scope[name] = value
    when 'ArrowFunctionExpression', 'FunctionExpression'
      ast[:scope] = vars.dup
      ast
    when 'FunctionDeclaration'
      ast[:scope] = vars.dup
      name = ast.fetch :id
      name = evaluate name, vars, identifier: :to_s if name
      vars.last[name] = ast
      ast
    when 'EmptyStatement' # I think it's from a semicolon on its own line
      nil
    when 'ReturnStatement'
      # FIXME: need a way to bail on the fn if we want to return
      evaluate ast[:argument], vars
    when 'MemberExpression'
      object = evaluate ast[:object], vars
      prop   = evaluate ast[:property], vars, identifier: :to_s
      object[prop]
    when 'IfStatement', 'ConditionalExpression'
      test = evaluate ast[:test], vars
      if test
        evaluate ast[:consequent], vars
      else
        evaluate ast[:alternate], vars
      end
    else
      require "pry"
      binding.pry
    end
  end


  # ===== Helpers ======
  private def not_implemented
    raise NotImplementedError, 'lol not even implemented', caller
  end

  private def find_scope(vars, name)
    vars.reverse_each.find { |scope| scope.key? name }
  end

  private def get_line(ast)
    ast.fetch(:loc).fetch(:end).fetch(:line)
  end

  private def invoke(ast, vars, invokable, args)
    if invokable.respond_to? :call
      keywords = {}
      params   = []
      params   = invokable.parameters if invokable.respond_to? :parameters
      keywords[:ast] = ast if params.include? [:keyreq, :ast]
      invokable.call *args, **keywords
    else
      body    = invokable[:body]
      context = invokable[:params]
                  .map { |param| evaluate param, vars, identifier: :to_string }
                  .zip(args)
                  .to_h
      fn_scope = invokable[:scope]
      vars = [*fn_scope, context]
      result = evaluate body, vars
      vars.pop
      result
    end
  end

  # ===== Native Functions =====

  # Have to take empty kwargs here b/c Ruby has a bug.
  # I reported it here: https://bugs.ruby-lang.org/issues/14415
  def set_timeout(cb=nil, ms, **)
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

  def show_version(ast:, **)
    @stdout.puts "[#{get_line ast}, \"\\\"JavaScript\\\" version l.o.l aka \\\"JoshuaScript\\\" aka \\\"JS... FTFY\\\"\"]"
  end

  def show_time(ast:, **)
    time = ((Time.now - @start)*1000).to_i.to_s + ' ms'
    @stdout.puts "[#{get_line ast}, #{time.inspect}]"
  end

  def console_log(to_log, ast:, **)
    @stdout.puts "[#{get_line ast}, #{to_log.inspect}]"
  end
end
