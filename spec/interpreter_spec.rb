require 'joshua_script'
require 'json'

class Result
  attr_accessor :result, :printed
  def initialize(result:, printed:)
    self.result = result
    self.printed = printed
  end

  def printed_jsons
    printed.lines.map { |line| JSON.parse line }
  end

  def printed_json
    jsons = printed_jsons
    raise "Expected one output! #{jsons.inspect}" unless jsons.length == 1
    jsons.first
  end
end

RSpec.describe 'The Interpreter' do
  def js!(code, result: :undefined)
    stdout = StringIO.new
    actual = JoshuaScript.eval(code, stdout: stdout)
    if result != :undefined
      expect(actual).to eq result
    end
    Result.new result: actual, printed: stdout.string
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

  it 'sets variables in the scope they were defined' do
    js! <<~JS, result: [1, 12, 3]
    var a = 1,
        b = a => {
          a = a + 10
          return a
        },
        c = d => a = d
    var aPre = a
    var aFromB = b(2)
    c(3)
    var aPost = a
    ;[aPre, aFromB, aPost]
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
      expect(printeds[0]).to eq '0 ms'
      expect(printeds[1]).to eq '0 ms'
      expect(printeds[2]).to match /10\d ms/
    end

    specify 'showVersion() prints the lineno and something amusing' do
      result = js! 'showVersion()'
      lineno, version = result.printed_json
      expect(lineno).to eq 1
      expect(version).to match /joshua.*script/i
    end
  end

  describe 'existing context' do
    describe 'console.log()' do
      # maybe specify what happens when you pass it non-string args?

      it 'prints the line number the call came from, and the inspected text' do
        result = js! 'console.log("hello world")'
        lineno, version = result.printed_json
        expect(lineno).to eq 1
        expect(version).to match "hello world"
      end
    end
  end
end
