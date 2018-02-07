require 'json'
require 'fiber'
require 'joshua_script/ast'
require 'joshua_script/parser'


class JoshuaScript
  ESPARSE = File.expand_path "../node_modules/.bin/esparse", __dir__

  def self.eval(source, stdout:, print_every_line:)
    js = new stdout: stdout
    js.enqueue Parser.parse source, print_every_line: print_every_line
    js.run
  end

  def initialize(stdout:)
    @stdout  = stdout
    @workers = []
    @queue   = Queue.new
    @global = {
      'showTime'    => method(:show_time),
      'setTimeout'  => method(:set_timeout),
      'showVersion' => method(:show_version),
      'require'     => method(:js_require),
      'console'     => {
        'log' => method(:console_log),
      },
    }
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
        raise "Undefined: #{name.inspect}" if !scope # FIXME: untested temp(?) hack
        scope[name]
      else
        name
      end

    when 'ExpressionStatement'
      evaluate ast[:expression]

    when 'Invooooooooke!' # FIXME: this is an internal call, unify it w/ the others
      invoke ast[:invokable], ast[:args], ast: ast

    when 'QuotedCode'
      ast

    when 'CallExpression'
      invokable = evaluate ast[:callee]
      if invokable.kind_of?(Ast) && evaluate(invokable[:id], identifier: :to_s).start_with?("macro$")
        args = ast[:arguments]
        code = expand_macro invokable, args
        evaluate code
      else
        args = ast[:arguments].map { |arg| evaluate arg }
        invoke invokable, args, ast: ast
      end

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
      # FIXME: setting scopes on the AST causes it to clobber the previous scopes
      # There should probably be a "callable" abstraction pulled out of here
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
      obj.send ast[:operator]

    else
      pp ast
      require "pry"
      binding().pry
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

  private def get_line(ast)
    ast.fetch(:loc).fetch(:end).fetch(:line)
  end

  private def invoke(invokable, args, ast:)
    if invokable.respond_to? :call
      invokable.call *args, ast: ast
    else
      old_scopes = scopes()
      Thread.current[:these].push invokable[:this, global]
      Thread.current[:scopes] = [
        *invokable[:scopes],
        invokable[:params]
          .map { |param| evaluate param, identifier: :to_string }
          .zip(args)
          .to_h
      ]
      begin
        evaluate invokable[:body]
      ensure
        Thread.current[:scopes] = old_scopes
        Thread.current[:these].pop
      end
    end
  end

  private def expand_macro(invokable, args)
    not_implemented if invokable.kind_of?(Proc) || invokable.kind_of?(Method)
    locals = invokable[:params]
              .map { |param| evaluate param, identifier: :to_string }
              .zip(args)
              .to_h
    do_expand_macro invokable[:body], locals
  end

  def do_expand_macro(invokable, locals)
    return invokable unless invokable.kind_of? Ast
    return invokable if invokable.kind_of?(Proc) || invokable.kind_of?(Method)
    expanded = Ast.new(
      { type:   invokable.type,
        loc:    invokable.loc,
      },
      source: invokable.source,
    )

    case invokable.type
    when 'Literal', 'MemberExpression'
      return invokable

    when 'Identifier'
      return locals.fetch invokable[:name]

    when 'BlockStatement'
      expanded[:body] = invokable[:body].map { |child| do_expand_macro child, locals }

    when 'ExpressionStatement'
      expanded[:expression] = do_expand_macro invokable[:expression], locals

    when 'IfStatement'
      expanded[:test]       = do_expand_macro invokable[:test],       locals
      expanded[:consequent] = do_expand_macro invokable[:consequent], locals
      expanded[:alternate]  = do_expand_macro invokable[:alternate],  locals

    when 'UnaryExpression'
      expanded[:prefix]   = invokable[:prefix]
      expanded[:operator] = invokable[:operator]
      expanded[:argument] = do_expand_macro invokable[:argument], locals

    when 'I SEE YA!'
      expanded[:to_record] = do_expand_macro invokable[:to_record], locals

    when 'CallExpression'
      expanded[:arguments] = invokable[:arguments].map do |argument|
        do_expand_macro argument, locals
      end
      expanded[:callee]    = do_expand_macro invokable[:callee], locals

    when 'TemplateLiteral'
      if invokable[:expressions].length == 1 &&
          invokable[:quasis].map { |el| el[:value][:cooked] } == ['', '']
        quoted = do_expand_macro invokable[:expressions][0], locals
        return Ast.new(
          { type:   'QuotedCode',
            loc:    quoted.loc,
            quoted: quoted,
          },
          source: quoted.source,
        )
        invokable[:expressions].length
      else
        not_implemented
      end

    else
      require "pry"
      binding().pry
    end

    expanded
  end

  def fn?(obj)
    return true if obj.respond_to? :call
    obj.kind_of?(Ast) && obj[:body]
  end

  def print_recorded(ast, result)
    @stdout.puts "[#{get_line ast}, #{JSON.dump inspect_value result}]"
  end

  def inspect_value(value)
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
        obj << k.to_s << ": " << inspect_value(v) << ", "
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
  end

  # ===== Native Functions =====

  # Have to take empty kwargs here b/c Ruby has a bug.
  # I reported it here: https://bugs.ruby-lang.org/issues/14415
  def set_timeout(cb=nil, ms, ast:, **)
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

  def console_log(to_log, ast:, **)
    print_recorded ast, to_log
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
