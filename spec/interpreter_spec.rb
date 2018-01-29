require 'joshua_script'

RSpec.describe 'The Interpreter' do
  def js!(code, result:)
    actual = JoshuaScript.eval(code)
    expect(actual).to eq result
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

  describe 'console.log' do
    it 'prints the line number the call came from, and the inspected text'
    # maybe what happens when you pass it non-string args
  end
end
