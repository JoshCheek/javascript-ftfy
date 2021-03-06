require 'json'
require 'fiber'
require 'joshua_script/ast'
require 'joshua_script/parser'
require 'set'


class JoshuaScript
  def self.eval(source, stdout:, print_every_line:)
    js = new stdout: stdout, print_every_line: print_every_line
    js.enqueue Parser.parse source, print_every_line: print_every_line
    js.run
  end

  module Helpers
    private def get_line(ast)
      ast.fetch(:loc).fetch(:end).fetch(:line)
    end
  end
  include Helpers

  class UnhandledAst < StandardError
    include Helpers
    def initialize(ast)
      @ast = ast
      super "Unhandled AST #{ast[:type].inspect} on line #{get_line ast}"
    end
  end



  def initialize(stdout:, print_every_line: true)
    @print_every_line = print_every_line
    @stdout  = stdout
    @workers = []
    @queue   = Queue.new
    @global  = {
      'showTime'    => method(:show_time),
      'setTimeout'  => method(:set_timeout),
      'showVersion' => method(:show_version),
      'require'     => method(:js_require),
      'console'     => {
        'log' => method(:console_log),
      },
    }
    @global['global'] = @global
  end

  attr_reader :global

  def enqueue(code)
    @queue << code
    self
  end

  def run
    @start = Time.now
    result = nil
    loop do
      @workers.select! &:alive?
      break if @queue.empty? && @workers.empty?
      work = @queue.shift
      if work.respond_to? :resume
        work.resume
      else
        Fiber.new do
          Thread.current[:scopes] = [global]
          Thread.current[:these]  = [global]
          result = evaluate work
        end.resume
      end
    end
    result
  end

  private

  # options are passed b/c of the output of esprima.
  # If this was for real, I'd transform their AST into my own internal
  # representation, but this is really just a thought experiment, so whatevz.
  def evaluate(ast, identifier: :resolve)
    return ast unless ast

    # it's an internal method: a block, method, or continuation
    if ast.respond_to? :call
      return invoke(ast, [], ast: ast)
    end

    case ast[:type]
    when 'Program'
      ast[:body].map { |child| evaluate child }.last

    when 'I SEE YA!'
      result = evaluate ast[:to_record], identifier: identifier
      print_recorded ast, result
      result

    when 'Identifier'
      name = ast[:name]
      if identifier == :resolve
        scope = find_scope scopes, name
        raise "Undefined: #{name}" if !scope # FIXME: untested temp(?) hack
        scope[name]
      else
        name
      end

    when 'ExpressionStatement'
      evaluate ast[:expression]

    when 'Invooooooooke!' # FIXME: this is an internal call, unify it w/ the others
      invoke ast[:invokable], ast[:args], ast: ast

    when 'CallExpression'
      method = evaluate ast[:callee]
      args   = ast[:arguments].map { |arg| evaluate arg }
      invoke method, args, ast: ast

    when 'Literal'
      value = ast.fetch :value
      value = value.to_f if value.kind_of? Integer
      value

    when 'BlockStatement'
      ast[:body].map { |child|
        # FIXME: `let` will need this to push/pop new vars, I think
        evaluate child
      }.last

    when 'ArrayExpression'
      ast.fetch(:elements).map { |child| evaluate child }

    when 'ObjectExpression'
      ast[:properties].each_with_object({}) do |prop, obj|
        key   = evaluate prop[:key], identifier: :to_s
        value = evaluate prop[:value]
        obj[key] = value
      end

    when 'BinaryExpression'
      operator = ast[:operator]
      left     = evaluate ast[:left]
      right    = evaluate ast[:right]
      left, right = left.to_i, right.to_i if integer_binary_op? operator
      left.send operator, right

    when 'VariableDeclaration'
      ast[:declarations].each { |dec| evaluate dec }

    when 'VariableDeclarator'
      name  = evaluate ast[:id], identifier: :to_s
      value = evaluate ast[:init]
      scopes.last[name] = value

    when 'AssignmentExpression'
      if ast[:left].type == 'MemberExpression'
        binding = evaluate ast[:left][:object]
        name    = evaluate ast[:left][:property], identifier: :to_s
      else
        name    = evaluate ast[:left], identifier: :to_string
        binding = find_scope scopes, name
      end
      value = evaluate ast[:right]
      binding[name] = value

    when 'ArrowFunctionExpression', 'FunctionExpression'
      ast          = ast.dup
      ast[:scopes] = scopes.dup # make it a closure
      ast[:this]   = this
      ast

    when 'FunctionDeclaration'
      ast[:scopes] = scopes.dup # this is why it's a closure
      name = ast[:id]
      name = evaluate name, identifier: :to_s if name
      scopes.last[name] = ast
      ast

    when 'EmptyStatement' # I think it's from a semicolon on its own line
      nil

    when 'ReturnStatement'
      # FIXME: need a way to bail on the fn if we want to return early
      # right now it only works b/c the return statements are the last line
      result = evaluate ast[:argument]

    when 'MemberExpression'
      object    = evaluate ast[:object]
      id_type   = ast[:computed] ? :resolve : :to_s
      prop_name = evaluate ast[:property], identifier: id_type
      # Hacky bs that allows us to get some useful functionality now,
      # without implementing prototypes or `this`
      begin
        prop = object[prop_name]
        if fn?(prop) && prop.respond_to?(:type) && prop.type != 'ArrowFunctionExpression'
          prop = prop.dup
          prop[:this] = object
        end
        prop
      rescue
        case object
        when Array
          case prop_name.intern
          when :length
            object.length
          when :push
            lambda do |val, **|
              object.push val
              val
            end
          when :forEach
            lambda do |cb, **|
              object.each do |e|
                invoke cb, [e], ast: ast
              end
            end
          end
        else
          raise
        end
      end

    when 'IfStatement', 'ConditionalExpression'
      test = evaluate ast[:test]
      if test
        evaluate ast[:consequent]
      else
        evaluate ast[:alternate]
      end

    when 'LogicalExpression'
      operator = ast[:operator]
      case operator
      when '&&'
        evaluate(ast[:left]) && evaluate(ast[:right])
      when '||'
        evaluate(ast[:left]) || evaluate(ast[:right])
      else raise "What operator is this? #{operator.inspect}"
      end

    when 'UpdateExpression'
      name        = evaluate ast[:argument], identifier: :to_s
      scope       = find_scope scopes, name
      pre_value   = scope[name]
      method      = ast[:operator][0] # plus or minus
      scope[name] = scope[name].public_send(method, 1)
      ast[:prefix] ? scope[name] : pre_value

    when 'ForStatement'
      evaluate ast[:init]
      loop do
        break unless evaluate ast[:test]
        evaluate ast[:body]
        evaluate ast[:update]
      end

    when 'ThisExpression'
      this

    when 'ImportDeclaration'
      source_name = evaluate ast[:source]
      required = js_require(source_name)
      ast[:specifiers].map do |specifier|
        local_name = evaluate specifier[:local], identifier: :to_s
        imported_name = evaluate specifier[:imported], identifier: :to_s
        scopes.last[local_name] = required[imported_name]
      end

    when 'UnaryExpression'
      raise not_implemented unless ast[:prefix]
      obj = evaluate ast[:argument]
      operator = ast[:operator]
      operator += '@' if operator == '-'
      obj.send operator

    when 'TemplateLiteral'
      exprs  = ast[:expressions].map { |e| evaluate e }
      quasis = ast[:quasis].map { |q| q[:value][:cooked] }
      quasis.zip(exprs).map { |q, e| "#{q}#{value_to_string e}" }.join("")

    else
      if (@stdout.tty? && $stdin.tty?) || defined?(RSpec)
        pp ast
        require "pry"
        binding().pry
      else
        raise UnhandledAst, ast
      end
    end
  end

  # ===== Helpers ======
  private def not_implemented
    raise NotImplementedError, 'lol not even implemented', caller
  end

  private def scopes
    Thread.current[:scopes]
  end

  private def this
    Thread.current[:these].last
  end

  private def find_scope(scopes, name)
    scopes.reverse_each.find { |scope| scope.key? name }
  end

  private def invoke(invokable, args, ast:)
    if invokable.respond_to? :call
      invokable.call *args, ast: ast
    else
      old_scopes = scopes()
      Thread.current[:these].push invokable[:this, global]
      Thread.current[:scopes] = [
        *invokable[:scopes],
        construct_args(invokable[:params], args).to_h
      ]
      begin
        evaluate invokable[:body]
      ensure
        Thread.current[:scopes] = old_scopes
        Thread.current[:these].pop
      end
    end
  end

  private def construct_args(params, args)
    params.zip(args).flat_map do |param, arg|
      case param[:type]
      when 'Identifier'
        [[param[:name], arg]]
      when 'ArrayPattern'
        # uhm, should we verify arg is an array here? (or maybe "iterable" or w/e the JS word is for it)
        construct_args param[:elements], arg
      when 'ObjectPattern'
        param[:properties].flat_map do |prop|
          # should we verify arg is an object and key is an identifier?
          name, value = prop[:key][:name], prop[:value]
          if value.type == 'Identifier' && value[:name] == name
            [[name, arg[name]]]
          else
            construct_args [value], [arg[name]]
          end
        end
      else
        raise "Unhandled param type: #{param[:type].inspect}"
      end
    end
  end

  def integer_binary_op?(operator)
    operator == '|' || operator == '&' || operator == '<<' || operator == '>>'
  end

  def fn?(obj)
    return true if obj.respond_to? :call
    obj.kind_of?(Ast) && obj[:body]
  end

  def print_recorded(ast, result)
    @stdout.puts "[#{get_line ast}, #{JSON.dump inspect_value result}]"
  end

  def value_to_string(value)
    case value
    when Float
      int = value.to_i
      value = int if value == int
    end
    value.to_s
  end

  def inspect_value(value, key=rand)
    manage = !Thread.current[:inspection_set]
    if manage
      Thread.current[:inspection_set] = Set.new
    end
    values = Thread.current[:inspection_set]
    if(values.include? value)
      return '[...]'
    else
      values << value
    end

    case value
    when String, TrueClass, FalseClass
      value.inspect.gsub("\n", '\n')
    when Numeric
      if value.to_i == value
        value.to_i.inspect
      else
        value.inspect
      end
    when Symbol
      value.to_s
    when NilClass
      'null'
    when Array
      "[" << value.map { |child| inspect_value child }.join(", ") << "]"
    when Hash
      obj = "{"
      value.each do |k, v|
        key_str = inspect_value k.to_s
        key_str = $1 if key_str =~ /\A"([a-zA-Z]+)"\z/
        obj << key_str << ": " << inspect_value(v) << ", "
      end
      obj.chomp! ", "
      obj << "}"
    when Ast
      value.source_code.gsub("\n", '\n')
    when Method
      "function() { [native code: #{value.owner}##{value.name}] }"
    when Proc
      "function() { [native code] }"
    else
      require "pry"
      binding.pry
    end
  ensure
    Thread.current[:inspection_set] = nil if manage
  end

  # ===== Native Functions =====

  # Have to take empty kwargs here b/c Ruby has a bug.
  # I reported it here: https://bugs.ruby-lang.org/issues/14415
  def set_timeout(cb=nil, ms=nil, ast:, **)
    if cb.kind_of?(Numeric) && ms.nil?
      ms, cb = cb, nil
    else
      ms ||= 0
    end
    cb &&= {
      type:      'Invooooooooke!',
      invokable: cb,
      scope:     [global],
      args:      [],
      loc:       ast.loc,
    }

    timeout = lambda do |code|
      if ms == 0
        # don't give multiple threads sleeping for 0ms
        # the chance to run out of order
        enqueue code
      else
        @workers << Thread.new do
          Thread.current.abort_on_exception = true
          sleep ms/1000.0
          enqueue code
        end
        Thread.pass # gets the sleeper thread running sooner
      end
      nil
    end

    # return immediately if callback was given
    return timeout[cb] if cb

    # no callback, so pause execution until we timeout
    timeout[Fiber.current]
    Fiber.yield
  end

  def show_version(ast:, **)
    @stdout.puts "[#{get_line ast}, \"\\\"JavaScript\\\" version l.o.l aka \\\"JoshuaScript\\\" aka \\\"JS... FTFY\\\"\"]"
  end

  def show_time(*args, ast:, **)
    time = ((Time.now - @start)*1000).to_i.to_s + ' ms'
    @stdout.puts "[#{get_line ast}, #{time.inspect}]"
  end

  def console_log(*values, ast:, **)
    values.push "" if values.empty?
    values.each do |value|
      value = inspect_value value unless value.is_a? String
      line  = @print_every_line ? -1 : get_line(ast)
      @stdout.puts "[#{line}, #{JSON.dump value}]"
    end
    nil
  end

  def js_require(filename, **)
    case filename
    when 'fs'
      { 'readFile' => method(:js_read_file) }
    else raise "No such file: #{filename.inspect}"
    end
  end

  def js_read_file(filename, encoding, callback=nil, ast:, **)
    if callback
      @workers << Thread.new do
        Thread.current.abort_on_exception = true
        body = File.read(filename)
        enqueue type:      'Invooooooooke!',
                invokable: callback,
                scope:     [global],
                args:      [nil, body],
                loc:       ast.loc
      end
      nil
    else
      body = nil
      f = Fiber.current
      @workers << Thread.new do
        Thread.current.abort_on_exception = true
        body = File.read filename
        enqueue f
      end
      Fiber.yield
      body
    end
  end
end
