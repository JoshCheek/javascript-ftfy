require 'continuation'
require 'joshua_script/ast'
require 'joshua_script/parser'

# TODO:
# * Switch from continuations to fibers
# * make vars fiber local so we don't have to pass them through every call to evaluate

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

    # it's an internal method: a block, method, or continuation
    if ast.respond_to? :call
      return invoke(ast, vars, [], ast: ast)
    end

    case ast[:type]
    when 'Program'
      ast[:body].map { |child| evaluate child, vars }.last

    when 'Identifier'
      name = ast[:name]
      if identifier == :resolve
        scope = find_scope vars, name
        raise "Undefined: #{name}" if !scope # FIXME: untested temp(?) hack
        scope[name]
      else
        name
      end

    when 'ExpressionStatement'
      evaluate ast[:expression], vars

    when 'Invooooooooke!' # FIXME: should just be CallExpression?
      not_implemented if ast[:code][:params].any?
      evaluate ast[:code][:body], vars

    when 'CallExpression'
      method = evaluate ast[:callee], vars
      args   = ast[:arguments].map { |arg| evaluate arg, vars }
      invoke method, vars, args, ast: ast

    when 'Literal'
      value = ast.fetch :value
      value = value.to_f if value.kind_of? Integer
      value

    when 'BlockStatement'
      ast[:body].map { |child| evaluate child, vars }.last

    when 'ArrayExpression'
      ast.fetch(:elements).map { |child| evaluate child, vars }

    when 'ObjectExpression'
      ast[:properties].each_with_object({}) do |prop, obj|
        key   = evaluate prop[:key],   vars, identifier: :to_s
        value = evaluate prop[:value], vars
        obj[key] = value
      end

    when 'BinaryExpression'
      operator = ast[:operator]
      left     = evaluate ast[:left], vars
      right    = evaluate ast[:right], vars
      left.send operator, right

    when 'VariableDeclaration'
      ast[:declarations].each { |dec| evaluate dec, vars }

    when 'VariableDeclarator'
      name  = ast[:id][:name]
      value = evaluate ast[:init], vars
      vars.last[name] = value

    when 'AssignmentExpression'
      name  = evaluate ast.fetch(:left), vars, identifier: :to_string
      value = evaluate ast.fetch(:right), vars
      scope = find_scope vars, name
      scope[name] = value

    when 'ArrowFunctionExpression', 'FunctionExpression'
      ast[:scope] = vars.dup # make it a closure
      ast

    when 'FunctionDeclaration'
      ast[:scope] = vars.dup # this is why it's a closure
      name = ast[:id]
      name = evaluate name, vars, identifier: :to_s if name
      vars.last[name] = ast
      ast

    when 'EmptyStatement' # I think it's from a semicolon on its own line
      nil

    when 'ReturnStatement'
      # FIXME: need a way to bail on the fn if we want to return early
      # right now it only works b/c the return statements are the last line
      evaluate ast[:argument], vars

    when 'MemberExpression'
      object  = evaluate ast[:object], vars
      id_type = ast[:computed] ? :resolve : :to_s
      prop    = evaluate ast[:property], vars, identifier: id_type
      begin
        object[prop]
      rescue
        # Hack that allows us to get array length. Real solution is prob to implement prototypes
        object.send prop
      end

    when 'IfStatement', 'ConditionalExpression'
      test = evaluate ast[:test], vars
      if test
        evaluate ast[:consequent], vars
      else
        evaluate ast[:alternate], vars
      end

    when 'UpdateExpression'
      name        = evaluate ast[:argument], vars, identifier: :to_s
      scope       = find_scope vars, name
      pre_value   = scope[name]
      method      = ast[:operator][0] # plus or minus
      scope[name] = scope[name].public_send(method, 1)
      ast[:prefix] ? scope[name] : pre_value

    when 'ForStatement'
      evaluate ast[:init], vars
      loop do
        break unless evaluate ast[:test], vars
        evaluate ast[:body], vars
        evaluate ast[:update], vars
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

  private def invoke(invokable, vars, args, ast:)
    if invokable.respond_to? :call
      invokable.call *args, ast: ast
    else
      evaluate invokable[:body], [
        *invokable[:scope],
        invokable[:params]
          .map { |param| evaluate param, vars, identifier: :to_string }
          .zip(args)
          .to_h]
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
