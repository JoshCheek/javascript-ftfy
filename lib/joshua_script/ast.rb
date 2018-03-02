# This class has 2 purposes:
# * Wrap the ast so I don't have to keep calling `.fetch` everywhere
# * Make the ast readable.
class JoshuaScript
  class Ast
    # initialize with parsed esprima output
    attr_reader :type, :loc
    def initialize(ast, source:)
      @source = source
      @type = ast.fetch :type
      @loc  = ast.fetch :loc
      @ast  = ast.each.with_object({}) do |(k, v), children|
        case v
        when Hash
          v = Ast.new v, source: source if v.key?(:type)
        when Array
          v = v.map do |e|
            e.kind_of?(Hash) && e.key?(:type) &&
              Ast.new(e, source: source) || e
          end
        end
        children[k] = v
      end
    end

    def [](key, *default)
      @ast.fetch key, *default
    end

    def []=(key, value)
      @ast[key] = value
    end

    alias fetch []

    # for post-dup init
    def initialize_copy(orig)
      @ast = @ast.dup
    end

    def source_code
      start_lineno = loc[:start][:line]
      start_col    = loc[:start][:column]
      end_lineno   = loc[:end][:line]
      end_col      = loc[:end][:column]
      if start_lineno == end_lineno
        line = @source.lines[start_lineno-1]
        line[start_col...end_col]
      else
        first, *mid, last = @source.lines[start_lineno-1..end_lineno-1]
        first = first[start_col..-1]
        last  = last[0...end_col]
        [first, *mid, last].join("")
      end
    end

    attr_reader :ast
    protected :ast

    # "open for extension, closed for modification" you can't extend pp
    # without guerilla patching it and overriding core methods, eg:
    # https://gist.github.com/JoshCheek/6472c8f334ae493f4ab1f7865e2470e5
    # so, we'll just build our own *sigh*
    def pretty_print(pp)
      pp.text _pretty_inspect
    end

    protected def _pretty_inspect
      # These ones are common enough they have their own custom inspect
      case type
      when 'Literal'
        return "(Literal #{self[:value].inspect})"
      when 'Identifier'
        return "(Identifier #{self[:name].inspect})"
      end

      width_limit = 80
      max_key_len = 0  # for key alignment

      children = @ast.reject do |k|
        k == :type || k == :loc || k == :scope
      end

      # inspect the children
      child_inspects = children.map do |name, child|
        name = name.to_s + ":"
        if child.kind_of? Ast
          child = child._pretty_inspect
        else
          child = child.pretty_inspect.chomp
        end
        max_key_len = [max_key_len, name.length].max
        [name, child]
      end

      # don't put 1-liners after big blocks of info (eg empty arg list after code to lookup method)
      child_inspects.sort_by! { |n, c| n.length + c.length }

      # if it's short, put it all on one line
      inspected =  "(#{type}"
      oneline   = inspected + " " + child_inspects.map { |n, c| "#{n}#{c}" }.join(', ') + ")"
      return oneline if oneline.length <= width_limit

      # fkn looks weird when we line up small #s of keys of different lengths
      if child_inspects.length < 3
        min, max = *child_inspects.map(&:first).map(&:length).sort
        max ||= min ||= 0
        max_key_len = 0 if (max-min) > 2
      end

      # print each child on its own line
      child_inspects.each do |name, child|
        inspected << "\n"
        pair = sprintf "  %-#{max_key_len}s %s,", name, child
        if pair.length <= width_limit && !pair.include?("\n")
          # put k and v on the same line
          inspected << pair
        else
          # put k and v on different lines
          inspected << "  %-#{max_key_len}s\n%s," % [name, child.gsub(/^/, "    ")]
        end
      end

      # close it off
      inspected.chomp! ","
      inspected << ")"
    end
  end
end
