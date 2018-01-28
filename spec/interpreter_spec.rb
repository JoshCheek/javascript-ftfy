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

  it 'can set and get vars', t:true do
    js! 'var a = 1, b=2; a+b', result: 3
  end
end
