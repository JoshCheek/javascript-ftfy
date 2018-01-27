require 'joshua_script'

RSpec.describe 'The Interpreter' do
  def js!(code, result:)
    actual = JoshuaScript.eval(code)
    expect(actual).to eq result
  end

  it 'interprets empty files' do
    js! '', result: nil
  end

  it 'interprets literals' do
    js! '12', result: 12
    js! '1.2', result: 1.2
    js! '"abc"', result: "abc"
  end

  it 'interprets arrays' do
    js! '[1,2]', result: [1,2]
  end

  it 'interprets objects' do
    js! '({a: 1})', result: {'a' => 1}
    js! '({"a": 1})', result: {'a' => 1}
  end
end
