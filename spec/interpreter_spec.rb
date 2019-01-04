require 'joshua_script'
require 'json'

class Result
  attr_accessor :interpreter, :value, :printed, :printed_jsons
  def initialize(interpreter:, value:, printed:)
    self.value         = value
    self.printed       = printed
    self.interpreter   = interpreter
    self.printed_jsons = printed.lines.map { |line| JSON.parse line }
  end

  def printed_json
    raise "Expected one output! #{printed_jsons.inspect}" unless printed_jsons.length == 1
    printed_jsons.first
  end

  def global
    interpreter.global
  end

  def [](key)
    interpreter.global.fetch key
  end
end

RSpec.describe 'The Interpreter' do
  def js!(code, print_every_line: false, result: :undefined)
    stdout = StringIO.new
    js     = JoshuaScript.new(stdout: stdout)
    ast    = JoshuaScript::Parser.parse code, print_every_line: print_every_line
    js.enqueue ast
    actual = js.run
    if result != :undefined
      expect(actual).to eq result
    end
    Result.new interpreter: js, value: actual, printed: stdout.string
  end

  it 'raises syntax errors for invalid code' do
    expect { js! '1+' }.to raise_error JoshuaScript::Parser::SyntaxError, /line 1\b/i
  end

  it 'interprets empty files' do
    js! '', result: nil
  end

  it 'interprets arrays' do
    js! '[1,2]', result: [1,2]
  end

  it 'interprets literals' do
    js! '[12, 1.2, "abc", true, false, null]',
        result: [12, 1.2, "abc", true, false, nil]
  end

  it 'interprets objects' do
    js! '({a: 1})', result: {'a' => 1}
    js! '({"a": 1})', result: {'a' => 1}
  end

  it 'can negate values' do
    js! <<~JS, result: [ false, true, true, false, false, false, false ]
    [!true, !false, !null, ![1,2,3], ![], !{a:1}, !{}]
    JS
  end

  it 'can add/subtract/multiply/divide/mod' do
    js! '[10+2, 10-2, 10*2, 10/2, 4%3, 5%3, 6%3, "ab"+"cd"]',
        result: [12, 8, 20, 5, 1, 2, 0, "abcd"]
  end

  it 'treats all numbers as floats' do
    js! '9/2', result: 4.5
  end

  it 'can set and get vars' do
    js! 'var a = 1, b=2; a+b', result: 3
  end

  it 'can compare numbers' do
    code = <<~JS
      [1<2,  2<1,  2<2,
       1<=2, 2<=1, 2<=2,
       1>=2, 2>=1, 2>=2,
       1>2,  2>1,  2>2,
       1==2, 2==1, 2==2]
    JS
    js! code, result: eval(code)
  end

  describe 'fix JS comparison' do
    it 'can compare arrays' do
      code = <<~JS
      [ []==[], []==[null], []==[1], [null]==[], [1]==[],
        [1]==[1], ["a"]==["a"], ["a","b"]==["a","b"], ["a","b"]==["a","c"],
        ["a","b"]==["b","a"], ["a","b"]==["a","b","c"], ["a","b","c"]==["a","b"]
      ]
      JS
      js! code, result: eval(code.gsub "null", "nil")
    end
    it 'can compare objects' do
      code = <<~JS
      [ {}=={}, {}=={a:1}, {a:1}=={},
        {a:1}=={a:1}, {a:1}=={a:2}, {a:1}=={b:1}, {b:1}=={a:1},
        {a:1,b:2}=={a:1,b:2}, {a:1,b:2}=={a:2,b:1}, {a:1,b:2}=={a:1,b:2,c:3}
      ]
      JS
      js! code, result: eval(code.gsub "null", "nil")
    end
  end

  it 'can prefix/postfix increment and decrement' do
    js! <<~JS, result: [0,0,  0,1,  2,2,  2,1]
      var a1 = 1
      var a2 = --a1

      var b1 = 1
      var b2 = b1--

      var c1 = 1
      var c2 = ++c1

      var d1 = 1
      var d2 = d1++

      ;[a1, a2,  b1,b2,  c1,c2,  d1,d2]
    JS
  end

  it 'can access array elements by index' do
    js! <<~JS, result: [300, 100, 200, 100]
      var ary = [100, 200, 300]
      var i = 0
      ;[ary[2], ary[0], ary[1], ary[i]]
    JS
  end

  it 'knows the length of arrays' do
    js! <<~JS, result: 3
      [100, 200, 300].length
    JS
  end

  it 'has for-loops' do
    js! <<~JS, result: 123
    var n = 0
    for(var i=0; i <= 3; ++i)
      n = n * 10 + i
    n
    JS
  end

  it 'can create and call functions' do
    js! <<~JS, result: [6, 9, 7, 27]
      var e = 100
      var f = function(a) { return a + a }
      var g = x => x * x
      var h = (y, z) => y + z
      function i(j) { return j*j*j }
      ;[f(3), g(3), h(3, 4), i(3)]
    JS
  end

  describe 'argument destructuring' do
    example 'arrays' do
      js! '(([a, b]) => [a, b])([1, 2])', result: [1, 2]
    end
    example 'objects' do
      js! '(({a}) => a)({a: 1})', result: 1
    end
    example 'multiple arguments' do
      js! '(({a: [b]}, [c]) => [b, c])({a: [1]}, [2])', result: [1, 2]
    end
    example 'nested arrays' do
      js! '(([[[a]]]) => a)([[[1]]])', result: 1
    end
    example 'nested objects' do
      js! '(({a: {b}}) => b)({a: {b: 1}})', result: 1
    end
    example 'objects of arrays' do
      js! '(({a: [b]}) => b)({a: [1]})', result: 1
    end
    example 'arrays ob objects' do
      js! '(([{a}]) => a)([{a: 1}])', result: 1
    end
    example 'kinda complex example, just to push it a bit' do
      js! <<~JS, result: [1, 2, 3, 4, 5, 6, 7]
      function f([a, b], {c, d: [{e: [f], g}, [[h, {i}]]]}) {
        return [a, b, c, f, g, h, i]
      }
      f([1, 2], {c: 3, d: [{e: [4], g: 5}, [[6, {i: 7}]]]})
      JS
    end
    context 'when printing every line' do
      it 'does not think the destructuring syntax are objects to print' do
        result = js! <<~JS, print_every_line: true, result: 1
        function f([a]) {
          return a
        }
        f([1])
        JS
        printed_by_line = result.printed_jsons.to_h
        expect(printed_by_line).to_not have_key 1
      end
    end
  end

  it 'sets variables in the scope they were defined' do
    js! <<~JS, result: [1, 12, 1, 3]
    var a = 1,
        b = a => {
          a = a + 10
          return a
        },
        c = d => a = d
    var aPre = a
    var aFromB = b(2)
    var midA = a
    c(3)
    var aPost = a
    ;[aPre, aFromB, midA, aPost]
    JS
  end

  it 'can see variables across function scopes' do
    js! <<~JS, result: 2+3+4+5+6
      var a = 2
      function f1(b) {
        var c = 3
        return function f2(d) {
          var e = 4
          return a + b + c + d + e
        }
      }
      f1(5)(6)
    JS
  end

  it 'can be evaluated multiple times in different scopes' do
    js! <<~JS, result: [11.0, 12.0]
    const fn = a => b => a + b
    const onePlus = fn(1)
    const twoPlus = fn(2)
    ;[onePlus(10), twoPlus(10)]
    JS
    js! <<~JS, result: [11.0, 12.0]
    function fn(a) {
      return function fnInner(b) {
        return a + b
      }
    }
    const onePlus = fn(1)
    const twoPlus = fn(2)
    ;[onePlus(10), twoPlus(10)]
    JS
  end

  it 'has those terminals!' do
    js! '(a => a ? 1 : 2)(true)', result: 1
    js! '(a => a ? 1 : 2)(false)', result: 2
  end

  it 'can look up values from objects' do
    js! <<~JS, result: 1+2+3
      var a = 1, obj = {a: 2, b: 3}
      a + obj.a + obj.b
    JS
  end


  describe 'this' do
    it 'is set to the global object by default' do
      result = js! 'this'
      expect(result.value).to eq result.global
    end

    it 'is set to the object that a method was called on' do
      result = js! <<~JS
      var a = {fn: function() { return this }}
      ;[a, a.fn()]
      JS
      a, this = result.value
      expect(this).to eq a
      expect(this).to_not eq result.global
    end

    it 'is bound to the existing this, when the function was a fat arrow' do
      result = js! <<~JS
      var a = {
        build: function() {
          return () => this
        }
      }
      var b = {getA: a.build()}
      ;[a, b.getA()]
      JS
      a, b_get_a = result.value
      expect(b_get_a).to eq a
    end

    it 'deviates from JavaScript and is bound to the object it was pulled from' do
      result = js! <<~JS
      var a = {fn: function() { return this }}
      var fn = a.fn
      ;[fn(), a]
      JS
      fn, a = result.value
      expect(fn).to eq a
    end

    it 'can set and get values from this' do
      js! <<~JS, result: 123
      var a = {setX: function(val) { this.x = val }}
      a.setX(123)
      a.x
      JS
    end
  end

  describe 'logic' do
    it 'has the if statements, y\'all' do
      js! <<~JS, result: [1, 2, 1, nil]
        // TODO: Why does this need fkn blocks around the branches?
        var a, b, c, d
        if (true)  { a = 1 } else { a = 2 }
        if (false) { b = 1 } else { b = 2 }
        if (true)  { c = 1 }
        if (false) { d = 1 }
        ;[a, b, c, d]
      JS
    end
    it 'has boolean operators' do
      js! <<~JS, result: [ 1, true, false, 4 ]
         var a = true && 1
         var b = true || 2
         var c = false && 3
         var d = false || 4
         ;[a, b, c, d]
      JS
    end
  end

  context 'when in print_every_line mode' do
    it 'will print the last thing it saw on a given line' do
      result = js! <<~JS, print_every_line: true
      import {readFile} from 'fs'
      {1;2;3}
      true
      false
      null
      101
      101.01
      ;[1,2]
      ;[1,
        2]
      ;[1,
        2
      ]
      ;({})
      ;({a:1,b:2})
      ;({a:1,
         b:
           2})
      ;(function() { 1 })
      ;() => 1
      var a = 1, b = 2
      ;[].forEach
      setTimeout
      JS

      expecteds = [
        [1,  "\"fs\""], # mostly, just don't want it to say "JoshuaScript" in the output
        [2,  "3"],
        [3,  "true"],
        [4,  "false"],
        [5,  "null"],
        [6,  "101"],
        [7,  "101.01"],
        [8,  "[1, 2]"],
        [9,  "1"],
        [10,  "[1, 2]"],
        [11, "1"],
        [12, "2"],
        [13, "[1, 2]"],
        [14, "{}"],
        [15, "{a: 1, b: 2}"],
        [16, "1"],
        [18, "{a: 1, b: 2}"],
        [19, "function() { 1 }"],
        [20, "() => 1"],
        [21, "2"],
        [22, "function() { [native code] }"],
        [23, "function() { [native code: JoshuaScript#set_timeout] }"],
      ]
      result.printed_jsons.zip(expecteds).each do |actual, expected|
        expect(actual).to eq expected
      end
    end
  end


  # consolidate the below blocks?
  describe 'custom functions' do
    specify 'showTime() prints the line number and the time' do
      result = js! <<~JS
      showTime()

      setTimeout(() => showTime(), 100)
      showTime()
      JS
      times = result.printed_jsons
      expect(times.length).to eq 3
      linenos, printeds = times.transpose
      expect(linenos).to eq [1, 4, 3]
      expect(printeds[0]).to match '[01] ms'
      expect(printeds[1]).to match '[01] ms'
      expect(printeds[2]).to match /1[01]\d ms/
    end

    specify 'showVersion() prints the lineno and something amusing' do
      result = js! 'showVersion()'
      lineno, version = result.printed_json
      expect(lineno).to eq 1
      expect(version).to match /joshua.*script/i
    end
  end



  describe 'native functions' do
    describe 'console.log()' do
      # maybe specify what happens when you pass it non-string args?

      it 'prints the line number the call came from, and the inspected text' do
        result = js! 'console.log("hello world")'
        lineno, version = result.printed_json
        expect(lineno).to eq 1
        expect(version).to match "hello world"
      end

      it 'logs objects without wrapping strings around their keys unless it needs to', t:true do
        # we're going to deviate a bit from what node prints,
        # but matching their output exactly is high difficulty with low value
        result = js! <<~JS
        console.log({a: 1, b: 2})
        console.log({"a b": 1})
        console.log({"a'b": 1})
        JS
        expect(result.printed_jsons.map(&:last)).to eq [
          '{a: 1, b: 2}',
          '{"a b": 1}',
          '{"a\'b": 1}',
        ]
      end
    end

    describe 'fs.readFile'  do
      require 'tempfile'
      before do
        @file = Tempfile.new
        @file.write "hello world!"
        @file.close
      end

      after do
        @file&.unlink
      end

      it 'reads async with a callback' do
        result = js! <<~JS
        import { readFile } from 'fs'
        let readFileResult = readFile("#{@file.path}", 'utf-8', (err, body) => console.log(body))
        JS
        printed = result.printed_json.last
        expect(printed).to eq File.read @file.path
        expect(result['readFileResult']).to eq nil # should be undefined, but I have no representation of undefined at present
      end

      it 'reads async without a callback' do
        result = js! <<~JS
        import { readFile } from 'fs'
        var body = readFile("#{@file.path}", 'utf-8')
        console.log(body)
        JS
        printed = result.printed_json.last
        expect(printed).to eq File.read @file.path
      end
    end

    describe 'import' do
      it 'can import under another name' do
        js! <<~JS, result: true
        import { readFile } from 'fs'
        import { readFile as read } from 'fs'
        readFile == read
        JS
      end
    end

    describe 'setTimeout' do
      it 'waits about the specified length of time, and then calls the fn' do
        result = js! 'setTimeout(showTime, 10)'
        lineno, time = result.printed_json
        expect(lineno).to eq 1
        expect(time).to match /^1\d ms$/
      end

      it 'asynchronously returns after the specified amount of time, when no callback is given' do
        result = js! <<~JS
        setTimeout(showTime, 50)
        setTimeout(100)
        showTime()
        JS
        ((l1, t1), (l2, t2)) = result.printed_jsons
        expect(l1).to eq 1
        expect(l2).to eq 3
        expect(t1).to match /^5\d ms/
        expect(t2).to match /^10\d ms/
      end

      it 'sets the timeout to 0 when no value is given' do
        result = js! 'setTimeout(showTime)'
        expect(result.printed_json).to eq [1, '0 ms']
      end
    end

    describe 'Array.forEach' do
      it 'passes each element to the cb' do
        js! <<~JS, result: "abc"
        var result = ""
        ;["a", "b", "c"].forEach(e => result = result + e)
        result
        JS
      end

      it 'scopes the variable correctly for working with async functions' do
        result = js! <<~JS
        let str = '', ary = ['a', 'b', 'c']
        ary.forEach(
          char => setTimeout(() => {
            str = str + char
            if(char == 'c')
              console.log(str)
          }, 0)
        )
        JS
        _, printed = result.printed_json
        expect(printed).to eq 'abc'
      end
    end

    describe 'Array.push' do
      it 'pushes an item onto the array and returns the item' do
        js! <<~JS, result: ['x', ['x']]
        var a = []
        ;[a.push('x'), a]
        JS
      end
    end
  end
end
